library fdb;

import 'src/server.dart';

/// Initialize Flutter Debug Bridge.
///
/// Starts an HTTP server on a random port. The port number is written to
/// the file path specified by the `FDB_PORT_FILE` environment variable
/// (defaults to `/tmp/fdb_port`).
///
/// Call this before `runApp()`:
/// ```dart
/// import 'package:fdb/fdb.dart';
///
/// void main() {
///   initFdb();
///   runApp(MyApp());
/// }
/// ```
void initFdb() {
  FdbServer.start();
}
