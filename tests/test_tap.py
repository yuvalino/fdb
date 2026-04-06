"""Tests for /tap endpoint — tap a widget and verify state changes."""

from fdb_client import FdbClient


async def test_tap_changes_text(fdb: FdbClient):
    await fdb.tap("key", "tap_btn")
    matches = await fdb.find("key", "status_text")
    assert len(matches) == 1
    assert matches[0]["text"] == "Tapped"
