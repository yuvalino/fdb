"""Tests for /tap endpoint — tap a widget and verify state changes."""

import pytest

from frt_client import FrtClient, FrtError


async def test_tap_changes_text(frt: FrtClient):
    await frt.tap("key", "tap_btn")
    matches = await frt.find("key", "status_text")
    assert len(matches) == 1
    assert matches[0]["text"] == "Tapped"


async def test_tap_ignored_widget_is_refused(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.tap("key", "ignored_btn")
    assert exc_info.value.status == 409
    assert exc_info.value.error == "not_hittable"
