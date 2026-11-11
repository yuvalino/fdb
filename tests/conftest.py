"""Pytest configuration for FRT integration tests.

Launches the pre-built test app and provides an async FRT client fixture.

Build the test app first:
    cd tests/app && flutter create --platforms=linux . && flutter build linux --debug

Then run tests:
    cd tests && python3 -m pytest -v -s
"""

import os
import subprocess
import sys
import tempfile

import pytest
import pytest_asyncio

from frt_client import FrtClient

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
TEST_APP_DIR = os.path.join(TESTS_DIR, "app")
PORT_FILE = os.path.join(tempfile.gettempdir(), "frt_test_port")


def _find_binary():
    """Find the built test_app binary (debug or release)."""
    for mode in ("debug", "release"):
        bundle_dir = os.path.join(
            TEST_APP_DIR, "build", "linux", "x64", mode, "bundle"
        )
        binary = os.path.join(bundle_dir, "frt_test_app")
        if os.path.exists(binary):
            return binary, bundle_dir
    return None, None


def pytest_configure(config):
    """Remove stale port file before session starts."""
    if os.path.exists(PORT_FILE):
        os.remove(PORT_FILE)


@pytest.fixture(scope="session")
def app_process():
    """Launch pre-built test app for entire test session."""
    binary, bundle_dir = _find_binary()
    if binary is None:
        pytest.exit(
            "test app binary not found. Build it first:\n"
            "  cd tests/app && flutter create --platforms=linux . "
            "&& flutter build linux --debug",
            returncode=1,
        )

    env = {**os.environ, "FRT_PORT_FILE": PORT_FILE}
    proc = subprocess.Popen(
        [binary],
        cwd=bundle_dir,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    yield proc

    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()

    if os.path.exists(PORT_FILE):
        os.remove(PORT_FILE)


@pytest_asyncio.fixture(scope="session")
async def frt(app_process):
    """Async FRT client connected to running test app."""
    client = FrtClient(port_file=PORT_FILE)
    await client.connect(timeout=30)
    yield client
    await client.close()
