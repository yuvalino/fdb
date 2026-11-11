import 'package:flutter/material.dart';
import 'package:frt/frt.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initFrt();
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FRT Test App',
      home: const TestPage(),
    );
  }
}

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  String _status = 'Ready';
  String _input = '';
  final _items = List.generate(50, (i) => 'Item $i');
  bool _longPressed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FRT Test')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              key: const Key('tap_btn'),
              onPressed: () => setState(() => _status = 'Tapped'),
              child: const Text('Tap Me'),
            ),
          ),
          Text(_status, key: const Key('status_text')),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              key: const Key('input_field'),
              decoration: const InputDecoration(hintText: 'Type here'),
              onChanged: (v) => setState(() => _input = v),
            ),
          ),
          Text(_input, key: const Key('input_echo')),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              key: const Key('delayed_btn'),
              onPressed: () async {
                await Future.delayed(const Duration(seconds: 2));
                if (mounted) setState(() => _status = 'Delayed');
              },
              child: const Text('Delayed'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              key: const Key('long_press_target'),
              onLongPress: () => setState(() => _longPressed = true),
              child: Container(
                padding: const EdgeInsets.all(16),
                color: _longPressed ? Colors.green : Colors.grey,
                child: Text(_longPressed ? 'Long Pressed!' : 'Long Press Me'),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const Key('scroll_list'),
              itemCount: _items.length,
              itemBuilder: (_, i) => ListTile(
                key: Key('item_$i'),
                title: Text(_items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
