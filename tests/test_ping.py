"""Tests for /ping and how the app is started."""

from conftest import APP_PORT
from frt_client import FrtClient


async def test_ping(frt: FrtClient):
    assert await frt.ping()


async def test_listens_on_frt_port(frt: FrtClient):
    # The port file names the port FRT_PORT asked for.
    assert frt._port == APP_PORT


async def test_connect_to_fixed_port(frt: FrtClient):
    client = FrtClient(port_file="/nonexistent", port=APP_PORT)
    await client.connect(timeout=5)
    assert await client.ping()
    await client.close()
