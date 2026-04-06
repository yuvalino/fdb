"""Tests for /tree endpoint — widget tree dump."""

from fdb_client import FdbClient


async def test_tree_dump(fdb: FdbClient):
    data = await fdb.tree(depth=5)
    assert "tree" in data
    tree = data["tree"]
    assert "type" in tree
    assert "children" in tree
