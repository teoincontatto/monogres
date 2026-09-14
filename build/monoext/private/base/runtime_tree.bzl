"""What the shippable runtime tree leaves behind.

`pg_install_tree` derives the runtime `:tar` by carving paths out of the full
install tree `:tar.dev` captured. Two of the things it carves cannot be named
by a path glob: contrib and the procedural languages install into `lib/` and
`share/extension/` right beside the backend's own loadable modules and
plpgsql's, so nothing in the layout separates them. Their paths come from the
introspection instead, which attributes every installed file to the part of the
tree that built it.

Loaded by the generated `@<hub>//<version>/<option_set>/BUILD.bazel`, next to
that package's Layer 1 `INTROSPECTION`.
"""

# The procedural languages a base image ships. A PL the flavor is *defined* by
# stays -- plisql is IvorySQL's whole point, the way plpgsql is PostgreSQL's.
# Every other one is an optional add-on, and belongs in a layer of its own for
# the same reason contrib does: it drags a language runtime (libperl, libpython,
# libtcl) into every image whether or not anything uses it. Flavors absent from
# this table ship plpgsql alone.
_SHIPPED_PL_LANGUAGES = {
    "ivorysql": ["plisql", "plpgsql"],
}

_DEFAULT_SHIPPED_PL_LANGUAGES = ["plpgsql"]

def runtime_exclude_paths(introspection):
    """The installed paths the runtime tree does not ship.

    Args:
        introspection: The Layer 1 `INTROSPECTION` of one (version, option set):
            a `flavor`, a `contrib` dict and a `pl` dict, the latter two keyed by
            name with a `paths` list each.

    Returns:
        Sorted, de-duplicated install-relative paths, for
        `pg_install_tree(exclude_paths = ...)`.
    """
    shipped = _SHIPPED_PL_LANGUAGES.get(
        introspection["flavor"],
        _DEFAULT_SHIPPED_PL_LANGUAGES,
    )

    excluded = {}

    # All of it: a contrib extension ships as its own layer, composed onto the
    # base image on demand, and is carved from `:tar.dev` -- which this does not
    # touch -- so the base has no reason to carry a copy.
    for entry in introspection["contrib"].values():
        for path in entry["paths"]:
            excluded[path] = True

    for language, entry in introspection["pl"].items():
        if language in shipped:
            continue

        for path in entry["paths"]:
            excluded[path] = True

    return sorted(excluded.keys())
