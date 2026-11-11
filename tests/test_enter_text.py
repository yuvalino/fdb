"""Tests for /enter-text endpoint — type into text fields."""

import pytest

from frt_client import FrtClient, FrtError


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


async def test_enter_text_read_only_is_refused(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.enter_text("key", "readonly_field", "changed")
    assert exc_info.value.status == 409
    assert exc_info.value.error == "not_editable"
    matches = await frt.find("key", "readonly_field")
    assert matches[0]["text"] == "fixed"


async def test_enter_text_not_a_field_is_refused(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.enter_text("key", "tap_btn", "nope")
    assert exc_info.value.status == 409
    assert exc_info.value.error == "not_editable"
