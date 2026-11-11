"""Tests for /find endpoint — widget discovery by key, text, and type."""

import pytest

from frt_client import FrtClient


async def test_find_by_key(frt: FrtClient):
    matches = await frt.find("key", "tap_btn")
    assert len(matches) == 1
    assert "ElevatedButton" in matches[0]["type"]


async def test_find_by_text(frt: FrtClient):
    # A Text matches once, not again through the RichText it builds.
    matches = await frt.find("text", "Ready")
    assert len(matches) == 1
    assert matches[0]["type"] == "Text"


async def test_find_by_type(frt: FrtClient):
    matches = await frt.find("type", "TextField")
    assert len(matches) >= 1


async def test_find_returns_bounds(frt: FrtClient):
    matches = await frt.find("key", "tap_btn")
    assert len(matches) == 1
    bounds = matches[0].get("bounds")
    assert bounds is not None
    assert "x" in bounds
    assert "y" in bounds
    assert "w" in bounds
    assert "h" in bounds
    assert bounds["w"] > 0
    assert bounds["h"] > 0


async def test_find_not_found(frt: FrtClient):
    matches = await frt.find("key", "nonexistent_widget")
    assert len(matches) == 0


async def test_find_multiple(frt: FrtClient):
    # There are 50 list items
    matches = await frt.find("type", "ListTile")
    # Some should be rendered (visible ones)
    assert len(matches) > 0


async def test_find_index(frt: FrtClient):
    every = await frt.find("type", "ListTile")
    second = await frt.find("type", "ListTile", index=1)
    assert second == [every[1]]
    assert await frt.find("type", "ListTile", index=len(every)) == []


async def test_find_key_null_matches_nothing(frt: FrtClient):
    assert await frt.find("key", "null") == []
