"""Tests for /long-press endpoint."""

from fdb_client import FdbClient


async def test_long_press(fdb: FdbClient):
    await fdb.long_press("key", "long_press_target", duration=600)
    matches = await fdb.find("text", "Long Pressed!")
    assert len(matches) > 0
