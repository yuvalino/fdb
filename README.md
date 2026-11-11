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
requests from any language. The repository also has a Python client and a
pytest suite in `tests/` (they aren't part of the pub package).

It can also read the screen of an [xterm](https://pub.dev/packages/xterm)
`TerminalView`, for testing terminal apps.

## Getting Started

**1. Add the package**

```sh
flutter pub add frt
```

**2. Start it in the app**

Start it when the test launches the app, so the build you test is the build
you ship:

```dart
import 'dart:io';
import 'package:frt/frt.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.environment.containsKey('FRT_PORT')) await initFrt();
  runApp(const MyApp());
}
```

Launched normally, the app never opens the socket. Or leave frt out of
shipped builds altogether: `if (const bool.fromEnvironment('FRT'))` and
`--dart-define=FRT=true`.

It listens on loopback, so only the same machine can drive the app. To drive
it from another machine, such as a phone from your desktop, launch it with
`FRT_HOST=0.0.0.0` (or call `initFrt(address: InternetAddress.anyIPv4)`);
anyone on the network can then drive it, as frt has no authentication. On
iOS, `xcrun devicectl device process launch -e '{"FRT_PORT": "4800",
"FRT_HOST": "0.0.0.0"}' <bundle id>` passes the variables.

**3. Drive it**

The server listens on `$FRT_PORT` (or a free port), prints the port to the
log, and writes it to `initFrt(portFile:)`, else `$FRT_PORT_FILE`, else
`/tmp/frt_port` on Linux and macOS (`frt_port` in the app's temporary
directory on iOS and Android).

```sh
port=$(cat /tmp/frt_port)
curl -X POST 127.0.0.1:$port/tap -d '{"by": "key", "value": "login"}'
curl -X POST 127.0.0.1:$port/wait -d '{"by": "text", "value": "Welcome", "timeout": 5000}'
```

## API

Widgets are found by `"by"`: `key` (a `ValueKey`'s value), `text` (a `Text`,
`RichText` or text field containing `"value"`) or `type` (the widget's class
name; with `--obfuscate` that is the obfuscated name, so use keys there). An
optional `"index"` picks one of several matches.

Tap, scroll and long press are real pointer gestures at the widget's centre,
run one at a time. If the pointer wouldn't reach the widget there (covered by
a dialog, inside `IgnorePointer`, off-screen, or nothing hittable at its
centre) they fail with 409, as they would for a user. Two taps on one spot
within 300 ms count as a double tap, and a drag loses the touch slop (about
18 px) before it starts scrolling; a scroll shorter than that is a tap.

All four actions then wait until the app stops scheduling frames, for up to
`"settle"` ms (default 1000, at most 60000; `0` waits for one frame). A focused text field whose cursor
fades (`CupertinoTextField`, or `TextField` on iOS) keeps scheduling frames,
so lower `settle` when that slows a test down.

| Endpoint | Body | Does |
|---|---|---|
| `GET /ping` | | Health check: `{"ok": true}` |
| `POST /find` | `by`, `value`, `index` | Matching widgets, with type, key, text and on-screen bounds |
| `POST /tap` | `by`, `value`, `index`, `settle` | Taps the widget's centre |
| `POST /enter-text` | `by`, `value`, `index`, `settle`, `text` | Taps a text field to focus it and replaces its text, firing `onChanged` |
| `POST /scroll` | `by`, `value`, `index`, `settle`, `dx`, `dy` | Drags (by touch) from the widget's centre |
| `POST /long-press` | `by`, `value`, `index`, `settle`, `duration` | Holds for `duration` ms (default 600, at most 60000) |
| `POST /wait` | `by`, `value`, `index`, `timeout` | Waits up to `timeout` ms (default 5000, at most 600000) for a match; 408 if none |
| `GET /tree?depth=` | | The widget tree (default depth 50) |
| `POST /terminal-buffer` | `key` | An xterm `TerminalView`'s lines and size (default key `terminal_view`) |

Errors come back as `{"error": ..., "message": ...}` with a 4xx or 5xx status:
400 for a malformed request, 404 when no widget matches, 405 for the wrong
method, 408 for a `/wait` timeout, 413 for a body over 1 MiB, and 409 when an
action can't be done: `not_hittable`, `not_editable` (no text field there, or
a read-only one), `not_mounted`, `no_box` or `no_view`.

## Python client

`tests/frt_client.py` is an async client (`aiohttp`) with the same calls:

```python
client = FrtClient(port_file="/tmp/frt_port")  # or FrtClient(host=..., port=...)
await client.connect()
await client.tap("key", "login")
await client.wait_for("text", "Welcome")
```

## Running the tests

The suite drives a small app in `tests/app`, built for Linux by default:

```sh
cd tests/app && flutter build linux --debug && cd ..
python3 -m pip install pytest pytest-asyncio aiohttp
python3 -m pytest -v
```

To run it against a build for another platform, point `FRT_TEST_APP` at its
executable. The app's output goes to `frt_test_app.log` in the temporary
directory.

## License

MIT ([LICENSE](LICENSE)).
