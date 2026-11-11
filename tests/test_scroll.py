"""Tests for /scroll endpoint — scroll lists to reveal items."""

from frt_client import FrtClient


async def test_scroll_reveals_item(frt: FrtClient):
    # Item 40 should not be visible initially
    matches = await frt.find("key", "item_40")
    assert len(matches) == 0

    # Scroll down in steps until it is built. (One long drag could fling
    # past it in a short list.)
    for _ in range(30):
        await frt.scroll("key", "scroll_list", dy=-150)
        matches = await frt.find("key", "item_40")
        if matches:
            break
    assert len(matches) > 0
