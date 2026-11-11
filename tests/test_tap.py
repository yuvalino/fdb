"""Tests for /tap endpoint — tap a widget and verify state changes."""

from frt_client import FrtClient


async def test_tap_changes_text(frt: FrtClient):
    await frt.tap("key", "tap_btn")
    matches = await frt.find("key", "status_text")
    assert len(matches) == 1
    assert matches[0]["text"] == "Tapped"
