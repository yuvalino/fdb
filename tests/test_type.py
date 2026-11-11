"""Tests for /type — typing as the platform keyboard does."""

import pytest

from frt_client import FrtClient, FrtError


async def test_type_into_text_field_keeps_its_text(frt: FrtClient):
    await frt.enter_text("key", "input_field", "ab")
    await frt.type("key", "input_field", "cd")
    matches = await frt.find("key", "input_echo")
    assert matches[0]["text"] == "abcd"


async def test_type_backspace(frt: FrtClient):
    await frt.enter_text("key", "input_field", "abc")
    await frt.type("key", "input_field", "x", backspace=2)
    matches = await frt.find("key", "input_echo")
    assert matches[0]["text"] == "ax"


async def test_type_into_raw_client_one_char_at_a_time(frt: FrtClient):
    await frt.type("key", "raw_input", "hi", backspace=0)
    await frt.type("key", "raw_input", backspace=1, action="done")
    matches = await frt.find("key", "raw_log")
    assert matches[0]["text"] == "raw:+h +i - !done"


async def test_type_unknown_action_is_400(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.type("key", "raw_input", action="explode")
    assert exc_info.value.status == 400


async def test_type_read_only_is_refused(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.type("key", "readonly_field", "x")
    assert exc_info.value.status == 409
    assert exc_info.value.error == "not_editable"


async def test_type_no_client_is_409(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.type("key", "tap_btn", "x")
    assert exc_info.value.status == 409
    assert exc_info.value.error == "no_text_input"
