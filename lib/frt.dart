library;

import 'dart:io';

import 'src/server.dart';

/// Starts Flutter Release Tests' HTTP server.
///
/// Each setting comes from its parameter, else from an environment variable,
/// else from a default:
///
/// - [address], else `FRT_HOST`, else loopback (`127.0.0.1`), so only the
///   same machine can reach it. Pass `InternetAddress.anyIPv4` (or set
///   `FRT_HOST=0.0.0.0`) to drive the app from another machine, such as a
///   phone from your desktop; anyone on the network can then drive it, as
///   frt has no authentication.
/// - [port], else `FRT_PORT`, else 0: a free port the system picks.
/// - [portFile], else `FRT_PORT_FILE`, else `/tmp/frt_port` on Linux and
///   macOS and `frt_port` in the app's temporary directory elsewhere (iOS,
///   Android, a sandboxed macOS app). The bound port is written there, and
///   printed to the log.
///
/// The returned future completes once the server is listening; await it to
/// see errors such as a failed bind or a malformed `FRT_HOST`/`FRT_PORT`.
/// Calling it again does nothing.
///
/// To start frt only when a test launches the app, check the environment:
///
/// ```dart
/// import 'dart:io';
/// import 'package:frt/frt.dart';
///
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   if (Platform.environment.containsKey('FRT_PORT')) await initFrt();
///   runApp(MyApp());
/// }
/// ```
Future<void> initFrt({InternetAddress? address, int? port, String? portFile}) {
  final env = Platform.environment;
  try {
    address ??= _envAddress(env['FRT_HOST']) ?? InternetAddress.loopbackIPv4;
    port ??= _envPort(env['FRT_PORT']) ?? 0;
  } on FormatException catch (e) {
    return Future.error(e);
  }
  if (port < 0 || port > 65535) {
    return Future.error(RangeError.range(port, 0, 65535, 'port'));
  }
  return FrtServer.start(address: address, port: port, portFile: portFile);
}

InternetAddress? _envAddress(String? value) {
  if (value == null || value.isEmpty) return null;
  return InternetAddress.tryParse(value) ??
      (throw FormatException('FRT_HOST is not an IP address', value));
}

int? _envPort(String? value) {
  if (value == null || value.isEmpty) return null;
  final port = int.tryParse(value);
  if (port == null || port < 0 || port > 65535) {
    throw FormatException('FRT_PORT is not a port number', value);
  }
  return port;
}
