"""Tests for /long-press endpoint."""

from frt_client import FrtClient


async def test_long_press(frt: FrtClient):
    await frt.long_press("key", "long_press_target", duration=600)
    matches = await frt.find("text", "Long Pressed!")
    assert len(matches) > 0
