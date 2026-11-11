library;

import 'dart:io';

import 'src/server.dart';

/// Starts Flutter Release Tests' HTTP server on a free port.
///
/// The server listens on [address], loopback by default so only the same
/// machine can reach it. Pass `InternetAddress.anyIPv4` to drive the app
/// from another machine, such as a phone from your desktop; anyone on the
/// network can then drive it, as frt has no authentication.
///
/// The port number is written to [portFile], else to the path in the
/// `FRT_PORT_FILE` environment variable, else to `/tmp/frt_port` on Linux
/// and macOS and to `frt_port` in the app's temporary directory elsewhere.
/// It is also printed to the log.
///
/// The returned future completes once the server is listening; await it to
/// see errors such as a failed bind. Calling it again does nothing.
///
/// ```dart
/// import 'package:frt/frt.dart';
///
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   initFrt();
///   runApp(MyApp());
/// }
/// ```
Future<void> initFrt({InternetAddress? address, String? portFile}) {
  return FrtServer.start(
    address: address ?? InternetAddress.loopbackIPv4,
    portFile: portFile,
  );
}
