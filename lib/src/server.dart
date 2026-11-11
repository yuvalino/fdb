import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Element;

import 'actions.dart';
import 'errors.dart';
import 'finder.dart';
import 'tree_dump.dart';
import 'waiter.dart';

/// The largest request body frt reads.
const int _maxBodyBytes = 1 << 20;

/// Caps on the times a request may ask for, so a seconds-for-milliseconds
/// slip can't hold the gesture queue (or a pointer) for days.
const int _maxDurationMs = 60 * 1000;
const int _maxTimeoutMs = 10 * 60 * 1000;

typedef _Handler = Future<void> Function(HttpRequest request);

class FrtServer {
  static Future<void>? _starting;
  late final HttpServer _httpServer;

  /// Gestures run one at a time: two overlapping requests would otherwise
  /// interleave their pointers into an accidental multi-touch.
  Future<void> _gestureQueue = Future<void>.value();

  FrtServer._();

  /// Starts the server once; later calls return the first call's future.
  static Future<void> start({
    required InternetAddress address,
    required int port,
    String? portFile,
  }) {
    return _starting ??= FrtServer._()._bind(address, port, portFile);
  }

  /// Where the port goes when neither `initFrt(portFile:)` nor
  /// `FRT_PORT_FILE` says: `/tmp/frt_port` on desktop, and the app's own
  /// temporary directory on iOS and Android, where `/tmp` isn't writable.
  static String _defaultPortFile() {
    if (Platform.isLinux || Platform.isMacOS) return '/tmp/frt_port';
    return '${Directory.systemTemp.path}${Platform.pathSeparator}frt_port';
  }

  Future<void> _bind(
      InternetAddress address, int requestedPort, String? portFile) async {
    _httpServer = await HttpServer.bind(address, requestedPort);
    _httpServer.listen(_handleRequest);
    final port = _httpServer.port;

    final fromEnv = Platform.environment['FRT_PORT_FILE'];
    final path = portFile ??
        (fromEnv == null || fromEnv.isEmpty ? _defaultPortFile() : fromEnv);
    File? temp;
    try {
      // Write a fresh file and rename it into place, so a reader never sees
      // a half-written port and a symlink planted at [path] is replaced
      // rather than followed.
      final file =
          File('$path.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
      // exclusive: fail rather than follow anything already at that name.
      await file.create(exclusive: true);
      temp = file;
      await file.writeAsString('$port', flush: true);
      await file.rename(path);
      temp = null;
      // ignore: avoid_print
      print('[frt] listening on ${address.address}:$port (port in $path)');
    } catch (e) {
      try {
        await temp?.delete();
      } catch (_) {}
      // ignore: avoid_print
      print('[frt] listening on ${address.address}:$port, '
          'but could not write the port to $path: $e');
    }
  }

  late final Map<String, (String, _Handler)> _routes = {
    '/ping': ('GET', (r) async => _jsonResponse(r, {'ok': true})),
    '/find': ('POST', _handleFind),
    '/tap': ('POST', _handleTap),
    '/enter-text': ('POST', _handleEnterText),
    '/scroll': ('POST', _handleScroll),
    '/long-press': ('POST', _handleLongPress),
    '/wait': ('POST', _handleWait),
    '/tree': ('GET', _handleTree),
    '/terminal-buffer': ('POST', _handleTerminalBuffer),
  };

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      request.response.headers
          .set('Content-Type', 'application/json; charset=utf-8');
      try {
        final route = _routes[request.uri.path];
        if (route == null) {
          throw FrtException(
              404, 'not_found', 'Unknown endpoint: ${request.uri.path}');
        }
        final (method, handler) = route;
        if (request.method != method) {
          request.response.headers.set('Allow', method);
          throw FrtException(405, 'method_not_allowed',
              '${request.uri.path} takes $method, not ${request.method}');
        }
        await handler(request);
      } on FrtException catch (e) {
        _errorResponse(request, e.status, e.code, e.message);
      } catch (e, st) {
        _errorResponse(request, 500, 'internal', '$e\n$st');
      }
      await request.response.close();
    } catch (_) {
      // The client went away mid-request (a long /wait, say); there is no
      // one left to answer.
    }
  }

  /// Runs [action] after every gesture before it has finished.
  Future<void> _serialised(Future<void> Function() action) {
    final run = _gestureQueue.then((_) => action());
    _gestureQueue = run.catchError((_) {});
    return run;
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final bytes = BytesBuilder(copy: false);
    var tooLarge = false;
    await for (final chunk in request) {
      // Past the limit, keep reading but drop the rest: answering before the
      // body is consumed closes the connection under a client still sending.
      if (tooLarge) continue;
      bytes.add(chunk);
      tooLarge = bytes.length > _maxBodyBytes;
    }
    if (tooLarge) {
      throw FrtException(
          413, 'too_large', 'Request body is over $_maxBodyBytes bytes');
    }
    if (bytes.isEmpty) return {};
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException catch (e) {
      throw FrtException.badRequest('Body is not valid JSON: ${e.message}');
    }
    if (body is! Map<String, dynamic>) {
      throw FrtException.badRequest('Body must be a JSON object');
    }
    return body;
  }

  static T? _field<T>(Map<String, dynamic> body, String name, String what) {
    final value = body[name];
    if (value == null || value is T) return value as T?;
    throw FrtException.badRequest('"$name" must be $what');
  }

  /// An integer field; a whole-numbered float such as `600.0` counts.
  static int? _intField(Map<String, dynamic> body, String name) {
    final value = _field<num>(body, name, 'an integer');
    if (value == null) return null;
    if (value is int) return value;
    if (value.isFinite && value == value.roundToDouble()) return value.toInt();
    throw FrtException.badRequest('"$name" must be an integer');
  }

  /// A time in milliseconds between 0 and [max].
  static int? _msField(Map<String, dynamic> body, String name, int max) {
    final value = _intField(body, name);
    if (value != null && (value < 0 || value > max)) {
      throw FrtException.badRequest('"$name" must be 0 to $max ms');
    }
    return value;
  }

  static double? _doubleField(Map<String, dynamic> body, String name) =>
      _field<num>(body, name, 'a number')?.toDouble();

  FindQuery _parseQuery(Map<String, dynamic> body) {
    final by = _field<String>(body, 'by', 'a string');
    final value = _field<String>(body, 'value', 'a string');
    if (by == null || value == null) {
      throw FrtException.badRequest(
          'Missing required fields: "by" and "value"');
    }
    if (by != 'key' && by != 'text' && by != 'type') {
      throw FrtException.badRequest(
          '"by" must be "key", "text" or "type", not "$by"');
    }
    final index = _intField(body, 'index');
    if (index != null && index < 0) {
      throw FrtException.badRequest('"index" must be 0 or more');
    }
    return FindQuery(by: by, value: value, index: index);
  }

  static Element _findOne(FindQuery query) {
    final element = findOneElement(query);
    if (element == null) {
      throw FrtException(404, 'not_found', 'No widget matches $query');
    }
    return element;
  }

  Future<void> _handleFind(HttpRequest request) async {
    final query = _parseQuery(await _readJsonBody(request));
    final matches = findElements(query);
    _jsonResponse(request, {'matches': matches.map(serializeElement).toList()});
  }

  Future<void> _gestureEndpoint(
    HttpRequest request,
    Future<void> Function(Map<String, dynamic> body, FindQuery query) action,
  ) async {
    final body = await _readJsonBody(request);
    final query = _parseQuery(body);
    final settle = _msField(body, 'settle', _maxDurationMs);
    await _serialised(() async {
      await action(body, query);
      await settleFrames(
        timeout: settle == null ? defaultSettle : Duration(milliseconds: settle),
      );
    });
    _jsonResponse(request, {'ok': true});
  }

  Future<void> _handleTap(HttpRequest request) =>
      _gestureEndpoint(request, (body, query) => performTap(_findOne(query)));

  Future<void> _handleEnterText(HttpRequest request) =>
      _gestureEndpoint(request, (body, query) {
        final text = _field<String>(body, 'text', 'a string');
        if (text == null) throw FrtException.badRequest('Missing "text" field');
        return performEnterText(_findOne(query), text);
      });

  Future<void> _handleScroll(HttpRequest request) =>
      _gestureEndpoint(request, (body, query) {
        final dx = _doubleField(body, 'dx') ?? 0.0;
        final dy = _doubleField(body, 'dy') ?? 0.0;
        return performScroll(_findOne(query), dx, dy);
      });

  Future<void> _handleLongPress(HttpRequest request) =>
      _gestureEndpoint(request, (body, query) {
        final duration =
            _msField(body, 'duration', _maxDurationMs) ?? defaultLongPressMs;
        return performLongPress(_findOne(query), durationMs: duration);
      });

  Future<void> _handleWait(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final query = _parseQuery(body);
    final timeout = _msField(body, 'timeout', _maxTimeoutMs) ?? 5000;
    final result = await waitForElement(query, timeoutMs: timeout);
    _jsonResponse(
      request,
      {
        'found': result.found,
        'elapsed_ms': result.elapsedMs,
        'matches': result.matches.map(serializeElement).toList(),
        if (!result.found) ...{
          'error': 'timeout',
          'message': 'No widget matches $query after ${timeout}ms',
        },
      },
      status: result.found ? 200 : 408,
    );
  }

  Future<void> _handleTree(HttpRequest request) async {
    final depthParam = request.uri.queryParameters['depth'];
    final depth = depthParam != null ? int.tryParse(depthParam) ?? 50 : 50;
    final tree = dumpTree(maxDepth: depth);
    _jsonResponse(request, {'tree': tree});
  }

  Future<void> _handleTerminalBuffer(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final key = _field<String>(body, 'key', 'a string') ?? 'terminal_view';

    final element = findOneElement(FindQuery(by: 'key', value: key));
    if (element == null) {
      throw FrtException(404, 'not_found', 'No widget with key "$key" found');
    }

    try {
      // Access xterm's TerminalView.terminal via dynamic dispatch so FRT
      // doesn't need a compile-time dependency on the xterm package.
      final dynamic widget = element.widget;
      final dynamic terminal = widget.terminal;
      final int width = terminal.viewWidth as int;
      final int height = terminal.viewHeight as int;
      final dynamic buffer = terminal.buffer;
      final int lineCount = buffer.lines.length as int;

      final lines = <String>[];
      for (int i = 0; i < lineCount; i++) {
        final dynamic line = buffer.lines[i];
        final int trimLen = line.getTrimmedLength(width) as int;
        final buf = StringBuffer();
        for (int c = 0; c < trimLen; c++) {
          final int cp = line.getCodePoint(c) as int;
          buf.writeCharCode(cp == 0 ? 0x20 : cp);
        }
        lines.add(buf.toString());
      }

      _jsonResponse(request, {
        'width': width,
        'height': height,
        'lines': lines,
        'lineCount': lineCount,
      });
    } catch (e) {
      throw FrtException(
          500, 'internal', 'Failed to read terminal buffer: $e');
    }
  }

  void _jsonResponse(
    HttpRequest request,
    Map<String, dynamic> data, {
    int status = 200,
  }) {
    request.response.statusCode = status;
    request.response.write(jsonEncode(data));
  }

  void _errorResponse(
      HttpRequest request, int status, String error, String message) {
    request.response.statusCode = status;
    request.response.write(jsonEncode({'error': error, 'message': message}));
  }
}
