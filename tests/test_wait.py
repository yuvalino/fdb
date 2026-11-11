"""Tests for /wait endpoint — wait for widgets to appear."""

import pytest

from frt_client import FrtClient, FrtError


async def test_wait_for_existing(frt: FrtClient):
    # Widget already exists — should return immediately
    matches = await frt.wait_for("key", "tap_btn", timeout=1000)
    assert len(matches) >= 1


async def test_wait_for_delayed(frt: FrtClient):
    # Tap the delayed button — status changes to "Delayed" after 2s
    await frt.tap("key", "delayed_btn")
    matches = await frt.wait_for("text", "Delayed", timeout=5000)
    assert len(matches) > 0


async def test_wait_timeout(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.wait_for("text", "This Will Never Appear", timeout=500)
    assert exc_info.value.status == 408
