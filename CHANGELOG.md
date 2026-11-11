## 0.2.0

- **Breaking:** listens on loopback by default; pass
  `initFrt(address: InternetAddress.anyIPv4)` to drive the app from another
  machine. The CORS header is gone.
- **Breaking:** `/tap` is a real pointer tap at the widget's centre instead of
  calling the first tap handler found near it, and gestures that wouldn't
  reach their widget fail with 409.
- `initFrt()` returns a future and takes `port` and `portFile`; `FRT_PORT`
  and `FRT_HOST` set the port and address when the parameters don't, so a
  test can turn frt on at launch. The port file is written
  after the server listens, atomically, and defaults to the app's temporary
  directory on iOS, Android and in a sandboxed macOS app. A failed write is
  logged instead of stopping the server.
- `/wait` answers 408 on timeout, checks at least once, and times out even
  when the app produces no frames. Actions settle until the app stops
  scheduling frames, for up to `settle` ms (default 1000), instead of for at
  most 10 frames. `duration` and `timeout` are capped.
- Taps work on touch devices (the pointer had no button). Scrolls are touch
  drags, which desktop lists accept. Gestures go to the widget's own view
  with their own device id, and run one at a time.
- `/enter-text` goes through the field like typing: `onChanged` fires and
  input formatters apply. It also works when matched on the `EditableText`,
  and refuses read-only fields.
- Malformed requests answer 400 instead of 500, wrong methods 405, oversized
  bodies 413. Negative `index` is a 400.
- Bounds that aren't finite (a box under a scale of 0, mid-animation) are
  left out instead of failing the whole answer with a 500, and a gesture on
  such a box answers 409 `no_box`.
- `by: text` matches a `Text` once instead of again through its `RichText`;
  `by: key, value: "null"` no longer matches keyless widgets; `/tree` shows
  text field contents.
- Terminals: `/terminal-buffer` finds the terminal by any query, can keep
  only the rows in view or from a line on, and answers soft-wrap flags, the
  joined `text`, the cursor, the alt-screen state and the lines the view
  is scrolled to (`view`); a wide character no
  longer gains a space after it. New `/terminal-input` types or pastes into
  a terminal, and `/terminal-wait` waits for text or a regex.
- New `/type`: types into any `TextInputClient` the way the platform
  keyboard does (characters one per edit, backspaces, an input action),
  for apps with their own keyboard handling such as terminals.
- Python client: re-reads the port file while connecting, closes its session
  on failure, takes `host`/`port`, uses `127.0.0.1`, and passes `index` on
  every call (and `settle` on actions), and has methods for the terminal
  endpoints.

## 0.1.0

- First release: an HTTP server in the app (`initFrt()`) with `/ping`,
  `/find`, `/tap`, `/enter-text`, `/scroll`, `/long-press`, `/wait`, `/tree`
  and `/terminal-buffer`, and an async Python client (`tests/frt_client.py`).
