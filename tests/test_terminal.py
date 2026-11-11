"""Tests for the terminal endpoints, against the test app's TestShell."""

import pytest

from frt_client import FrtClient, FrtError


async def _cursor_line(frt: FrtClient) -> int:
    """The buffer line the cursor is on: where the next input is echoed.
    (lineCount is no guide: the buffer has empty rows below the cursor.)"""
    return (await frt.terminal_buffer())["cursor"]["line"]


async def _run(frt: FrtClient, line: str) -> list[str]:
    """Type a line into the test shell; return the lines it printed."""
    at = await _cursor_line(frt)
    await frt.terminal_input(line + "\r")
    # The prompt after the output says the command is done.
    await frt.terminal_wait(pattern=r"^> $", start=at + 1)
    lines = (await frt.terminal_buffer(start=at + 1))["lines"]
    return lines[: lines.index("> ")]


async def test_input_echo_and_output(frt: FrtClient):
    assert await _run(frt, "say hello") == ["hello"]


async def test_buffer_shape(frt: FrtClient):
    buf = await frt.terminal_buffer()
    assert buf["width"] > 0 and buf["height"] > 0
    assert len(buf["lines"]) == len(buf["wrapped"]) == buf["lineCount"]
    assert buf["altBuffer"] is False
    # The cursor sits after the last prompt.
    assert buf["lines"][buf["cursor"]["line"]] == "> "
    assert buf["cursor"]["x"] == 2


async def test_find_by_query(frt: FrtClient):
    by_key = await frt.terminal_buffer("terminal_view")
    by_type = await frt.terminal_buffer(by="type", value="TerminalView")
    assert by_key["lines"] == by_type["lines"]


async def test_wide_characters_take_no_extra_space(frt: FrtClient):
    assert await _run(frt, "wide") == ["漢字x"]


async def test_wrapped_line_is_joined(frt: FrtClient):
    width = (await frt.terminal_buffer())["width"]
    long = "y" * (width + 10)
    at = await _cursor_line(frt)
    await frt.terminal_input(f"say {long}\r")
    await frt.terminal_wait(pattern=r"^> $", start=at + 1)
    buf = await frt.terminal_buffer(start=at)
    assert True in buf["wrapped"]
    assert buf["text"].startswith(f"> say {long}\n{long}\n> ")


async def test_wait_regex_groups(frt: FrtClient):
    at = await _cursor_line(frt)
    await frt.terminal_input("say rc=42\r")
    # From the line after the echo, so only the output can match.
    result = await frt.terminal_wait(pattern=r"^rc=(\d+)$", start=at + 1)
    assert result["found"] is True
    assert result["groups"] == ["42"]


async def test_wait_timeout_is_408(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.terminal_wait("never printed", timeout=300)
    assert exc_info.value.status == 408


async def test_ctrl_c(frt: FrtClient):
    at = await _cursor_line(frt)
    await frt.terminal_input("half a line")
    await frt.terminal_input("\x03")
    await frt.terminal_wait("> half a line^C\n> ", start=at)


async def test_paste(frt: FrtClient):
    assert await _run(frt, "say pasted") == ["pasted"]
    at = await _cursor_line(frt)
    await frt.terminal_input("say from paste\r", paste=True)
    await frt.terminal_wait("\nfrom paste\n> ", start=at)


async def test_alt_buffer(frt: FrtClient):
    await frt.terminal_input("alt\r")
    await frt.terminal_wait(pattern=r"^> $")
    assert (await frt.terminal_buffer())["altBuffer"] is True
    await frt.terminal_input("main\r")
    await frt.terminal_wait(pattern=r"^> $")
    assert (await frt.terminal_buffer())["altBuffer"] is False


async def test_not_a_terminal_is_409(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.terminal_buffer("tap_btn")
    assert exc_info.value.status == 409
    assert exc_info.value.error == "not_terminal"


async def test_both_text_and_pattern_is_400(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.terminal_wait("a", pattern="b")
    assert exc_info.value.status == 400


async def test_view_follows_scroll(frt: FrtClient):
    for i in range(30):
        await _run(frt, f"say fill {i}")
    # To the end first: (xterm stops following output after the alt-screen
    # test, whose screen had fewer lines.)
    await frt.scroll("key", "terminal_view", dy=-2000)
    buf = await frt.terminal_buffer()
    view = buf["view"]
    assert view["last"] == buf["lineCount"] - 1 == buf["cursor"]["line"]
    rows = view["last"] - view["first"] + 1
    assert 1 <= rows <= buf["height"]

    # A drag down shows earlier lines; the buffer is no different.
    await frt.scroll("key", "terminal_view", dy=40)
    up = await frt.terminal_buffer()
    assert up["view"]["first"] < view["first"]
    assert up["view"]["last"] - up["view"]["first"] + 1 in (rows - 1, rows)
    assert up["lines"] == buf["lines"]

    # And a long drag up goes back to the end.
    await frt.scroll("key", "terminal_view", dy=-2000)
    down = await frt.terminal_buffer()
    assert down["view"] == view
