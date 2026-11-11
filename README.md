<div align="center">

# frt

**Flutter Release Tests: drive a running Flutter app over HTTP.**

Find widgets, tap, type, scroll and wait from any language, in the release build you ship.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![pub](https://img.shields.io/pub/v/frt.svg)](https://pub.dev/packages/frt)

</div>

## What's frt?

`integration_test`, `flutter_driver` and Patrol drive an app through Flutter's
debug service, so they test debug or profile builds made by `flutter` itself.
frt is a small HTTP server inside the app instead. It works in any build mode,
including release builds made by your own build system, and a test is just HTTP
requests from any language. A Python client and a pytest suite come with it.

It can also read the screen of an [xterm](https://pub.dev/packages/xterm)
`TerminalView`, for testing terminal apps.

## Getting Started

**1. Add the package**

```sh
flutter pub add frt
```

**2. Start it in the app**

```dart
import 'package:frt/frt.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('FRT')) initFrt();
  runApp(const MyApp());
}
```

Build with `--dart-define=FRT=true`. frt listens on every network interface
with no authentication, so keep it out of builds that ship to users.

**3. Drive it**

The server picks a free port and writes it to `$FRT_PORT_FILE` (default
`/tmp/frt_port`).

```sh
port=$(cat /tmp/frt_port)
curl -X POST localhost:$port/tap -d '{"by": "key", "value": "login"}'
curl -X POST localhost:$port/wait -d '{"by": "text", "value": "Welcome", "timeout": 5000}'
```

## API

Widgets are found by `"by"`: `key` (a `ValueKey`'s value), `text` (a `Text`,
`RichText` or text field containing `"value"`) or `type` (the widget's class
name). An optional `"index"` picks one of several matches. Tap, type, scroll
and long press wait for the app's frames to settle before they answer.

| Endpoint | Body | Does |
|---|---|---|
| `GET /ping` | | Health check: `{"ok": true}` |
| `POST /find` | `by`, `value`, `index` | Matching widgets, with type, key, text and on-screen bounds |
| `POST /tap` | `by`, `value`, `index` | Calls the widget's tap handler, or taps its centre |
| `POST /enter-text` | `by`, `value`, `text` | Focuses a text field and sets its text |
| `POST /scroll` | `by`, `value`, `dx`, `dy` | Drags from the widget's centre |
| `POST /long-press` | `by`, `value`, `duration` | Holds for `duration` ms (default 500) |
| `POST /wait` | `by`, `value`, `timeout` | Waits up to `timeout` ms (default 5000) for a match; 408 if none |
| `GET /tree?depth=` | | The widget tree (default depth 50) |
| `POST /terminal-buffer` | `key` | An xterm `TerminalView`'s lines and size (default key `terminal_view`) |

Errors come back as `{"error": ..., "message": ...}` with a 4xx or 5xx status.

## Python client

`tests/frt_client.py` is an async client (`aiohttp`) with the same calls:

```python
client = FrtClient(port_file="/tmp/frt_port")
await client.connect()
await client.tap("key", "login")
await client.wait_for("text", "Welcome")
```

## Running the tests

The suite drives a small Linux app in `tests/app`:

```sh
cd tests/app && flutter build linux --debug && cd ..
python3 -m pip install pytest pytest-asyncio aiohttp
python3 -m pytest -v
```

## License

MIT ([LICENSE](LICENSE)).
