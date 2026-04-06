"""Tests for /wait endpoint — wait for widgets to appear."""

import pytest

from fdb_client import FdbClient, FdbError


async def test_wait_for_existing(fdb: FdbClient):
    # Widget already exists — should return immediately
    matches = await fdb.wait_for("key", "tap_btn", timeout=1000)
    assert len(matches) >= 1


async def test_wait_for_delayed(fdb: FdbClient):
    # Tap the delayed button — status changes to "Delayed" after 2s
    await fdb.tap("key", "delayed_btn")
    matches = await fdb.wait_for("text", "Delayed", timeout=5000)
    assert len(matches) > 0


async def test_wait_timeout(fdb: FdbClient):
    with pytest.raises(FdbError) as exc_info:
        await fdb.wait_for("text", "This Will Never Appear", timeout=500)
    assert exc_info.value.status == 408
