"""Tests for /scroll endpoint — scroll lists to reveal items."""

from frt_client import FrtClient


async def test_scroll_reveals_item(frt: FrtClient):
    # Item 40 should not be visible initially
    matches = await frt.find("key", "item_40")
    assert len(matches) == 0

    # Scroll down significantly
    await frt.scroll("key", "scroll_list", dy=-3000)

    # Now item 40 should be findable
    matches = await frt.find("key", "item_40")
    assert len(matches) > 0
