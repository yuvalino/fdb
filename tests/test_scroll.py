"""Tests for /scroll endpoint — scroll lists to reveal items."""

from fdb_client import FdbClient


async def test_scroll_reveals_item(fdb: FdbClient):
    # Item 40 should not be visible initially
    matches = await fdb.find("key", "item_40")
    assert len(matches) == 0

    # Scroll down significantly
    await fdb.scroll("key", "scroll_list", dy=-3000)

    # Now item 40 should be findable
    matches = await fdb.find("key", "item_40")
    assert len(matches) > 0
