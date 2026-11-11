"""Flutter Release Tests async Python client."""

import asyncio
import os

import aiohttp


class FrtError(Exception):
    """Error from FRT server."""

    def __init__(self, status: int, error: str, message: str):
        self.status = status
        self.error = error
        self.message = message
        super().__init__(f"[{status}] {error}: {message}")


def _query(
    by: str, value: str, index: int | None, settle: int | None = None
) -> dict:
    body = {"by": by, "value": value}
    if index is not None:
        body["index"] = index
    if settle is not None:
        body["settle"] = settle
    return body


class FrtClient:
    """Async HTTP client for Flutter Release Tests.

    Mirrors WidgetTester semantics: find widgets, tap, enter text, scroll,
    wait for conditions. Actions settle frames before returning, for up to
    ``settle`` ms (the server's default is 1000).

    The server is found at ``host`` on ``port``, or on the port written to
    ``port_file`` when no port is given. The server listens on loopback
    unless the app passes another address to ``initFrt``.
    """

    def __init__(
        self,
        port_file: str = "/tmp/frt_port",
        host: str = "127.0.0.1",
        port: int | None = None,
    ):
        self._port_file = port_file
        self._host = host
        self._fixed_port = port  # as given; None means "read port_file"
        self._port = port  # the port in use
        self._session: aiohttp.ClientSession | None = None

    def _read_port(self) -> int | None:
        try:
            with open(self._port_file) as f:
                content = f.read().strip()
        except OSError:
            return None
        try:
            return int(content)
        except ValueError:
            return None

    def _url(self, path: str) -> str:
        return f"http://{self._host}:{self._port}{path}"

    async def connect(self, timeout: float = 30.0):
        """Find the server's port and poll until /ping responds.

        The port file is read again on every attempt, so a stale file from
        an earlier run is followed as soon as the app replaces it.
        """
        fixed_port = self._fixed_port
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        await self.close()
        session = aiohttp.ClientSession()
        try:
            while loop.time() < deadline:
                port = fixed_port if fixed_port is not None else self._read_port()
                if port is not None:
                    self._port = port
                    try:
                        async with session.get(
                            self._url("/ping"),
                            timeout=aiohttp.ClientTimeout(total=2),
                        ) as resp:
                            if resp.status == 200:
                                self._session = session
                                return
                    except (aiohttp.ClientError, asyncio.TimeoutError):
                        pass
                await asyncio.sleep(0.2)
        except BaseException:
            await session.close()
            raise
        await session.close()
        where = (
            f"port {fixed_port}"
            if fixed_port is not None
            else f"the port in {self._port_file}"
        )
        raise TimeoutError(f"FRT server not responding on {where} within {timeout}s")

    async def close(self):
        if self._session:
            await self._session.close()
            self._session = None

    @staticmethod
    async def _result(resp: aiohttp.ClientResponse) -> dict:
        try:
            data = await resp.json(content_type=None)
        except (aiohttp.ContentTypeError, ValueError):
            data = {"error": "unknown", "message": await resp.text()}
        if resp.status >= 400:
            raise FrtError(
                resp.status,
                data.get("error", "unknown"),
                data.get("message", ""),
            )
        return data

    async def _post(self, path: str, body: dict, timeout: float = 300) -> dict:
        assert self._session is not None, "Not connected"
        async with self._session.post(
            self._url(path),
            json=body,
            timeout=aiohttp.ClientTimeout(total=timeout),
        ) as resp:
            return await self._result(resp)

    async def _get(self, path: str, **params) -> dict:
        assert self._session is not None, "Not connected"
        async with self._session.get(self._url(path), params=params) as resp:
            return await self._result(resp)

    # --- Finding ---

    async def find(
        self, by: str, value: str, index: int | None = None
    ) -> list[dict]:
        """Find all widgets matching the query (or the index-th one)."""
        data = await self._post("/find", _query(by, value, index))
        return data["matches"]

    async def find_one(
        self, by: str, value: str, index: int | None = None
    ) -> dict:
        """Find exactly one widget. Raises if 0 or >1."""
        matches = await self.find(by, value, index)
        if len(matches) == 0:
            raise FrtError(404, "not_found", f"No widget: {by}={value}")
        if len(matches) > 1:
            raise FrtError(
                400,
                "ambiguous",
                f"Found {len(matches)} matches for {by}={value}",
            )
        return matches[0]

    # --- Actions ---

    async def tap(
        self,
        by: str,
        value: str,
        index: int | None = None,
        settle: int | None = None,
    ):
        """Tap a widget."""
        await self._post("/tap", _query(by, value, index, settle))

    async def enter_text(
        self,
        by: str,
        value: str,
        text: str,
        index: int | None = None,
        settle: int | None = None,
    ):
        """Enter text into a text field."""
        await self._post(
            "/enter-text", {**_query(by, value, index, settle), "text": text}
        )

    async def scroll(
        self,
        by: str,
        value: str,
        dx: float = 0,
        dy: float = 0,
        index: int | None = None,
        settle: int | None = None,
    ):
        """Scroll/drag a widget."""
        await self._post(
            "/scroll",
            {**_query(by, value, index, settle), "dx": dx, "dy": dy},
        )

    async def long_press(
        self,
        by: str,
        value: str,
        duration: int = 600,
        index: int | None = None,
        settle: int | None = None,
    ):
        """Long press a widget."""
        await self._post(
            "/long-press",
            {**_query(by, value, index, settle), "duration": duration},
            timeout=duration / 1000 + 300,
        )

    async def type(
        self,
        by: str,
        value: str,
        text: str = "",
        *,
        backspace: int = 0,
        action: str | None = None,
        index: int | None = None,
        settle: int | None = None,
    ):
        """Type into the text input client at or under a widget as the
        keyboard does: ``backspace`` deletions, then ``text`` a character at
        a time, then ``action`` (a TextInputAction name such as "done")."""
        body = {**_query(by, value, index, settle), "text": text}
        if backspace:
            body["backspace"] = backspace
        if action is not None:
            body["action"] = action
        await self._post("/type", body)

    # --- Waiting ---

    async def wait_for(
        self,
        by: str,
        value: str,
        timeout: int = 5000,
        index: int | None = None,
    ) -> list[dict]:
        """Wait until a widget appears. Returns matches.

        Raises FrtError with status 408 when none appears in time.
        """
        data = await self._post(
            "/wait",
            {**_query(by, value, index), "timeout": timeout},
            timeout=timeout / 1000 + 30,
        )
        return data["matches"]

    async def wait_gone(
        self, by: str, value: str, timeout: int = 5000
    ):
        """Wait until a widget disappears."""
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout / 1000
        while True:
            matches = await self.find(by, value)
            if len(matches) == 0:
                return
            if loop.time() >= deadline:
                break
            await asyncio.sleep(0.1)
        raise FrtError(
            408, "timeout", f"Widget {by}={value} still present after {timeout}ms"
        )

    # --- Terminals ---
    #
    # Each takes the terminal's widget by key (``key``), or by the usual
    # query (``by``/``value``/``index``) at or above it.

    @staticmethod
    def _terminal_query(
        key: str | None, by: str | None, value: str | None, index: int | None
    ) -> dict:
        if by is not None:
            return _query(by, value or "", index)
        return {"key": key or "terminal_view"}

    async def terminal_buffer(
        self,
        key: str | None = None,
        *,
        by: str | None = None,
        value: str | None = None,
        index: int | None = None,
        screen: bool = False,
        start: int = 0,
    ) -> dict:
        """The terminal's lines, wrap flags, joined ``text``, cursor, size
        and alt-screen state. ``screen`` keeps only the lines in view;
        ``start`` drops buffer lines before that index."""
        return await self._post(
            "/terminal-buffer",
            {
                **self._terminal_query(key, by, value, index),
                "screen": screen,
                "from": start,
            },
        )

    async def terminal_input(
        self,
        text: str,
        key: str | None = None,
        *,
        by: str | None = None,
        value: str | None = None,
        index: int | None = None,
        paste: bool = False,
    ):
        """Send ``text`` to the terminal's program as typed input, or as a
        paste. Return is ``"\r"``; Ctrl-C is ``"\x03"``."""
        await self._post(
            "/terminal-input",
            {
                **self._terminal_query(key, by, value, index),
                "text": text,
                "paste": paste,
            },
        )

    async def terminal_wait(
        self,
        text: str | None = None,
        key: str | None = None,
        *,
        pattern: str | None = None,
        by: str | None = None,
        value: str | None = None,
        index: int | None = None,
        timeout: int = 5000,
        screen: bool = False,
        start: int = 0,
    ) -> dict:
        """Wait until the terminal shows ``text``, or matches the regex
        ``pattern`` (multi-line; soft wraps undone). Returns ``match`` and
        ``groups``; raises FrtError with status 408 on timeout."""
        body = {
            **self._terminal_query(key, by, value, index),
            "timeout": timeout,
            "screen": screen,
            "from": start,
        }
        if text is not None:
            body["text"] = text
        if pattern is not None:
            body["pattern"] = pattern
        return await self._post(
            "/terminal-wait", body, timeout=timeout / 1000 + 30
        )

    # --- Debug ---

    async def tree(self, depth: int = 50) -> dict:
        """Get widget tree dump."""
        return await self._get("/tree", depth=str(depth))

    async def ping(self) -> bool:
        """Health check."""
        try:
            data = await self._get("/ping")
            return data.get("ok", False)
        except Exception:
            return False
