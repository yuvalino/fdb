"""Tests for /enter-text endpoint — type into text fields."""

from frt_client import FrtClient


async def test_enter_text(frt: FrtClient):
    await frt.enter_text("key", "input_field", "hello world")
    matches = await frt.find("key", "input_echo")
    assert len(matches) == 1
    assert matches[0]["text"] == "hello world"


async def test_enter_text_replaces(frt: FrtClient):
    # Enter text twice — second should replace first
    await frt.enter_text("key", "input_field", "first")
    await frt.enter_text("key", "input_field", "second")
    matches = await frt.find("key", "input_echo")
    assert len(matches) == 1
    assert matches[0]["text"] == "second"
