"""Tests for the server's error answers."""

import pytest

from frt_client import FrtClient, FrtError


async def _status(frt: FrtClient, method: str, path: str, **kwargs) -> int:
    async with frt._session.request(method, frt._url(path), **kwargs) as resp:
        return resp.status


async def test_missing_fields_is_400(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt._post("/tap", {})
    assert exc_info.value.status == 400
    assert exc_info.value.error == "bad_request"


async def test_wrong_type_is_400(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt._post("/find", {"by": "key", "value": "tap_btn", "index": "1"})
    assert exc_info.value.status == 400


async def test_negative_index_is_400(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.find("key", "tap_btn", index=-1)
    assert exc_info.value.status == 400


async def test_malformed_json_is_400(frt: FrtClient):
    assert await _status(frt, "POST", "/find", data=b"{not json") == 400


async def test_not_found_is_404(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.tap("key", "nonexistent_widget")
    assert exc_info.value.status == 404


async def test_unknown_endpoint_is_404(frt: FrtClient):
    assert await _status(frt, "GET", "/nope") == 404


async def test_wrong_method_is_405(frt: FrtClient):
    assert await _status(frt, "GET", "/tap") == 405


async def test_oversized_body_is_413(frt: FrtClient):
    body = b'{"by": "key", "value": "' + b"x" * (2 << 20) + b'"}'
    assert await _status(frt, "POST", "/find", data=body) == 413


async def test_unbounded_duration_is_400(frt: FrtClient):
    with pytest.raises(FrtError) as exc_info:
        await frt.long_press("key", "long_press_target", duration=600_000_000)
    assert exc_info.value.status == 400


async def test_reconnect_rereads_port_file(frt: FrtClient):
    # A second connect() on the same client must follow the port file, not
    # keep the port it found the first time.
    from conftest import PORT_FILE

    client = FrtClient(port_file=PORT_FILE)
    await client.connect(timeout=5)
    real_port = client._port
    client._port = 1  # as if the app had been on another port before
    await client.connect(timeout=5)
    assert client._port == real_port
    await client.close()
