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


class FrtClient:
    """Async HTTP client for Flutter Release Tests.

    Mirrors WidgetTester semantics: find widgets, tap, enter text, scroll,
    wait for conditions. All actions settle frames before returning.
    """

    def __init__(self, port_file: str = "/tmp/frt_port"):
        self._port_file = port_file
        self._port: int | None = None
        self._session: aiohttp.ClientSession | None = None

    async def connect(self, timeout: float = 30.0):
        """Read port from file and poll until /ping responds."""
        # Wait for port file to appear
        deadline = asyncio.get_event_loop().time() + timeout
        while asyncio.get_event_loop().time() < deadline:
            if os.path.exists(self._port_file):
                with open(self._port_file) as f:
                    content = f.read().strip()
                    if content:
                        self._port = int(content)
                        break
            await asyncio.sleep(0.2)

        if self._port is None:
            raise TimeoutError(
                f"Port file {self._port_file} not found within {timeout}s"
            )

        self._session = aiohttp.ClientSession(f"http://localhost:{self._port}")

        # Poll until server responds
        while asyncio.get_event_loop().time() < deadline:
            try:
                async with self._session.get("/ping") as resp:
                    if resp.status == 200:
                        return
            except aiohttp.ClientError:
                pass
            await asyncio.sleep(0.2)

        raise TimeoutError(f"FRT server not responding on port {self._port}")

    async def close(self):
        if self._session:
            await self._session.close()
            self._session = None

    async def _post(self, path: str, body: dict) -> dict:
        assert self._session is not None, "Not connected"
        async with self._session.post(path, json=body) as resp:
            data = await resp.json()
            if resp.status >= 400:
                raise FrtError(
                    resp.status,
                    data.get("error", "unknown"),
                    data.get("message", ""),
                )
            return data

    async def _get(self, path: str, **params) -> dict:
        assert self._session is not None, "Not connected"
        async with self._session.get(path, params=params) as resp:
            data = await resp.json()
            if resp.status >= 400:
                raise FrtError(
                    resp.status,
                    data.get("error", "unknown"),
                    data.get("message", ""),
                )
            return data

    # --- Finding ---

    async def find(self, by: str, value: str) -> list[dict]:
        """Find all widgets matching the query."""
        data = await self._post("/find", {"by": by, "value": value})
        return data["matches"]

    async def find_one(self, by: str, value: str) -> dict:
        """Find exactly one widget. Raises if 0 or >1."""
        matches = await self.find(by, value)
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

    async def tap(self, by: str, value: str, index: int = 0):
        """Tap a widget."""
        await self._post("/tap", {"by": by, "value": value, "index": index})

    async def enter_text(self, by: str, value: str, text: str):
        """Enter text into a text field."""
        await self._post(
            "/enter-text", {"by": by, "value": value, "text": text}
        )

    async def scroll(self, by: str, value: str, dx: float = 0, dy: float = 0):
        """Scroll/drag a widget."""
        await self._post(
            "/scroll", {"by": by, "value": value, "dx": dx, "dy": dy}
        )

    async def long_press(
        self, by: str, value: str, duration: int = 500
    ):
        """Long press a widget."""
        await self._post(
            "/long-press",
            {"by": by, "value": value, "duration": duration},
        )

    # --- Waiting ---

    async def wait_for(
        self, by: str, value: str, timeout: int = 5000
    ) -> list[dict]:
        """Wait until a widget appears. Returns matches."""
        data = await self._post(
            "/wait", {"by": by, "value": value, "timeout": timeout}
        )
        if not data["found"]:
            raise FrtError(
                408, "timeout", f"Widget {by}={value} not found in {timeout}ms"
            )
        return data["matches"]

    async def wait_gone(
        self, by: str, value: str, timeout: int = 5000
    ):
        """Wait until a widget disappears."""
        deadline = asyncio.get_event_loop().time() + timeout / 1000
        while asyncio.get_event_loop().time() < deadline:
            matches = await self.find(by, value)
            if len(matches) == 0:
                return
            await asyncio.sleep(0.1)
        raise FrtError(
            408, "timeout", f"Widget {by}={value} still present after {timeout}ms"
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
