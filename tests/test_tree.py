"""Tests for /tree endpoint — widget tree dump."""

from frt_client import FrtClient


async def test_tree_dump(frt: FrtClient):
    data = await frt.tree(depth=5)
    assert "tree" in data
    tree = data["tree"]
    assert "type" in tree
    assert "children" in tree
