"""Tests for /enter-text endpoint — type into text fields."""

from fdb_client import FdbClient


async def test_enter_text(fdb: FdbClient):
    await fdb.enter_text("key", "input_field", "hello world")
    matches = await fdb.find("key", "input_echo")
    assert len(matches) == 1
    assert matches[0]["text"] == "hello world"


async def test_enter_text_replaces(fdb: FdbClient):
    # Enter text twice — second should replace first
    await fdb.enter_text("key", "input_field", "first")
    await fdb.enter_text("key", "input_field", "second")
    matches = await fdb.find("key", "input_echo")
    assert len(matches) == 1
    assert matches[0]["text"] == "second"
