library;

import 'src/server.dart';

/// Initialize Flutter Release Tests.
///
/// Starts an HTTP server on a random port. The port number is written to
/// the file path specified by the `FRT_PORT_FILE` environment variable
/// (defaults to `/tmp/frt_port`).
///
/// Call this before `runApp()`:
/// ```dart
/// import 'package:frt/frt.dart';
///
/// void main() {
///   initFrt();
///   runApp(MyApp());
/// }
/// ```
void initFrt() {
  FrtServer.start();
}
