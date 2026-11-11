import 'package:flutter/material.dart';
import 'package:frt/frt.dart';

/// Starts frt only in builds made with `--dart-define=FRT=true`, then drive
/// the app from outside, for example:
///
/// ```sh
/// curl -X POST 127.0.0.1:$(cat /tmp/frt_port)/tap \
///      -d '{"by": "key", "value": "go"}'
/// ```
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('FRT')) initFrt();
  runApp(const MaterialApp(home: Example()));
}

class Example extends StatefulWidget {
  const Example({super.key});

  @override
  State<Example> createState() => _ExampleState();
}

class _ExampleState extends State<Example> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('go'),
          onPressed: () => setState(() => _taps++),
          child: Text('Tapped $_taps times'),
        ),
      ),
    );
  }
}
