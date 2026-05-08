import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'finder.dart';
import 'actions.dart';
import 'waiter.dart';
import 'tree_dump.dart';

class FdbServer {
  static FdbServer? _instance;
  late HttpServer _httpServer;

  FdbServer._();

  static Future<void> start() async {
    if (_instance != null) return;
    _instance = FdbServer._();
    await _instance!._bind();
  }

  Future<void> _bind() async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final port = _httpServer.port;

    final portFilePath =
        Platform.environment['FDB_PORT_FILE'] ?? '/tmp/fdb_port';
    File(portFilePath).writeAsStringSync('$port');

    // ignore: avoid_print
    print('[fdb] listening on port $port (written to $portFilePath)');
    _httpServer.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers
        .set('Content-Type', 'application/json; charset=utf-8');

    // Handle CORS preflight
    if (request.method == 'OPTIONS') {
      request.response.headers
          .set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      request.response.headers
          .set('Access-Control-Allow-Headers', 'Content-Type');
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }

    try {
      final path = request.uri.path;
      final method = request.method;

      if (method == 'GET' && path == '/ping') {
        _jsonResponse(request, {'ok': true});
      } else if (method == 'POST' && path == '/find') {
        await _handleFind(request);
      } else if (method == 'POST' && path == '/tap') {
        await _handleTap(request);
      } else if (method == 'POST' && path == '/enter-text') {
        await _handleEnterText(request);
      } else if (method == 'POST' && path == '/scroll') {
        await _handleScroll(request);
      } else if (method == 'POST' && path == '/long-press') {
        await _handleLongPress(request);
      } else if (method == 'POST' && path == '/wait') {
        await _handleWait(request);
      } else if (method == 'GET' && path == '/tree') {
        await _handleTree(request);
      } else if (method == 'POST' && path == '/terminal-buffer') {
        await _handleTerminalBuffer(request);
      } else {
        _errorResponse(request, 404, 'not_found', 'Unknown endpoint: $path');
      }
    } catch (e, st) {
      _errorResponse(request, 500, 'internal', '$e\n$st');
    }

    await request.response.close();
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.isEmpty) return {};
    return jsonDecode(body) as Map<String, dynamic>;
  }

  FindQuery _parseQuery(Map<String, dynamic> body) {
    final by = body['by'] as String?;
    final value = body['value'] as String?;
    if (by == null || value == null) {
      throw _BadRequest('Missing required fields: "by" and "value"');
    }
    final index = body['index'] as int?;
    return FindQuery(by: by, value: value, index: index);
  }

  Future<void> _handleFind(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final query = _parseQuery(body);
    final matches = findElements(query);
    _jsonResponse(request, {'matches': matches.map(serializeElement).toList()});
  }

  Future<void> _handleTap(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final query = _parseQuery(body);
    final element = findOneElement(query);
    if (element == null) {
      _errorResponse(request, 404, 'not_found',
          'No widget matches {by: ${query.by}, value: ${query.value}}');
      return;
    }
    await performTap(element);
    await settleFrames();
    _jsonResponse(request, {'ok': true});
  }

  Future<void> _handleEnterText(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final query = _parseQuery(body);
    final text = body['text'] as String?;
    if (text == null) {
      _errorResponse(request, 400, 'bad_request', 'Missing "text" field');
      return;
    }
    final element = findOneElement(query);
    if (element == null) {
      _errorResponse(request, 404, 'not_found',
          'No widget matches {by: ${query.by}, value: ${query.value}}');
      return;
    }
    await performEnterText(element, text);
    await settleFrames();
    _jsonResponse(request, {'ok': true});
  }

  Future<void> _handleScroll(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final query = _parseQuery(body);
    final dx = (body['dx'] as num?)?.toDouble() ?? 0.0;
    final dy = (body['dy'] as num?)?.toDouble() ?? 0.0;
    final element = findOneElement(query);
    if (element == null) {
      _errorResponse(request, 404, 'not_found',
          'No widget matches {by: ${query.by}, value: ${query.value}}');
      return;
    }
    await performScroll(element, dx, dy);
    await settleFrames();
    _jsonResponse(request, {'ok': true});
  }

  Future<void> _handleLongPress(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final query = _parseQuery(body);
    final duration = body['duration'] as int? ?? 500;
    final element = findOneElement(query);
    if (element == null) {
      _errorResponse(request, 404, 'not_found',
          'No widget matches {by: ${query.by}, value: ${query.value}}');
      return;
    }
    await performLongPress(element, durationMs: duration);
    await settleFrames();
    _jsonResponse(request, {'ok': true});
  }

  Future<void> _handleWait(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final query = _parseQuery(body);
    final timeout = body['timeout'] as int? ?? 5000;
    final result = await waitForElement(query, timeoutMs: timeout);
    if (!result.found) {
      request.response.statusCode = 408;
    }
    _jsonResponse(request, {
      'found': result.found,
      'elapsed_ms': result.elapsedMs,
      'matches': result.matches.map(serializeElement).toList(),
    });
  }

  Future<void> _handleTree(HttpRequest request) async {
    final depthParam = request.uri.queryParameters['depth'];
    final depth = depthParam != null ? int.tryParse(depthParam) ?? 50 : 50;
    final tree = dumpTree(maxDepth: depth);
    _jsonResponse(request, {'tree': tree});
  }

  Future<void> _handleTerminalBuffer(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final key = body['key'] as String? ?? 'terminal_view';

    final element = findOneElement(FindQuery(by: 'key', value: key));
    if (element == null) {
      _errorResponse(
          request, 404, 'not_found', 'No widget with key "$key" found');
      return;
    }

    try {
      // Access xterm's TerminalView.terminal via dynamic dispatch so FDB
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
      _errorResponse(request, 500, 'internal',
          'Failed to read terminal buffer: $e');
    }
  }

  void _jsonResponse(HttpRequest request, Map<String, dynamic> data) {
    request.response.statusCode = 200;
    request.response.write(jsonEncode(data));
  }

  void _errorResponse(
      HttpRequest request, int status, String error, String message) {
    request.response.statusCode = status;
    request.response.write(jsonEncode({'error': error, 'message': message}));
  }
}

class _BadRequest implements Exception {
  final String message;
  _BadRequest(this.message);
  @override
  String toString() => message;
}
