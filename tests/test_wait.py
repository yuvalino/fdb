"""Tests for /wait endpoint — wait for widgets to appear."""

import pytest

from frt_client import FrtClient, FrtError


async def test_wait_for_existing(frt: FrtClient):
    # Widget already exists — should return immediately
    matches = await frt.wait_for("key", "tap_btn", timeout=1000)
    assert len(matches) >= 1


async def test_wait_for_delayed(frt: FrtClient):
    # Tap the delayed button — status changes to "Delayed done" after 2s
    assert await frt.find("text", "Delayed done") == []
    await frt.tap("key", "delayed_btn")
    matches = await frt.wait_for("text", "Delayed done", timeout=5000)
    assert len(matches) == 1
    assert matches[0]["key"] == "status_text"


async def test_wait_timeout(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.wait_for("text", "This Will Never Appear", timeout=500)
    assert exc_info.value.status == 408


async def test_wait_timeout_zero_checks_once(frt: FrtClient):
    matches = await frt.wait_for("key", "tap_btn", timeout=0)
    assert len(matches) == 1
