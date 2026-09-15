"""What the shippable runtime tree leaves behind -- and what picks it back up.

`pg_install_tree` derives the runtime `:tar` by carving paths out of the full
install tree `:tar.dev` captured. Two of the things it carves cannot be named
by a path glob: contrib and the procedural languages install into `lib/` and
`share/extension/` right beside the backend's own loadable modules and
plpgsql's, so nothing in the layout separates them. Their paths come from the
introspection instead, which attributes every installed file to the part of the
tree that built it.

Carving something out of the base is only half a decision: the other half is
the layer that carries it, and a carve no layer answers is a file gone from
every image. So both halves read one function here. `layered_entries` names
everything the base leaves out, under the name its layer goes by;
`runtime_exclude_paths` is the flat path set of the same thing.
`tools/gen_contrib.bzl` reads the first to generate the catalog the layers are
built from, and this package's generated BUILD file reads the second to carve.
Splitting that table in two is how the procedural languages came to be carved
out of every base image and published nowhere (ongres/stackgres-cloud#133).

Loaded by the generated `@<hub>//<version>/<option_set>/BUILD.bazel`, next to
that package's Layer 1 `INTROSPECTION`.
"""

load("//monoext/private/base/introspect:metadata.bzl", "PL_LANGUAGES")

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

# What an entry is, for the `repo.json` the catalog generator writes. Nothing
# dispatches on it -- both kinds are carved the same way and build the same
# targets -- but it is the only thing in a generated file that says why
# `plperl` sits in a directory of contrib extensions.
KIND_CONTRIB = "contrib"
KIND_PL = "pl"

def _pl_entry_name(language):
    """The name a language's layer, and its `CREATE EXTENSION`, goes by.

    `PL_LANGUAGES` lists a language's extensions with the trusted one first,
    and that is the name to carry: it is how a dependent contrib's `.control
    requires` spells the prerequisite, which is what lets `//postgres:cfg.bzl`
    resolve `hstore_plpython`'s requires to an image without being told about
    procedural languages at all. Note it is not the language's own key --
    `plpython` is spelled `plpython3u` everywhere it is named.

    The untrusted twin rides along inside the same entry rather than getting
    one of its own: `plperl` and `plperlu` are two control files over one
    `lib/plperl.so`, and there is nothing to split.
    """
    return PL_LANGUAGES[language].extensions[0]

def layered_entries(introspection, _fail = fail):
    """Everything the base image does not ship, keyed by its layer's name.

    Args:
        introspection: The Layer 1 `INTROSPECTION` of one (version, option set):
            a `flavor`, a `contrib` dict and a `pl` dict, the latter two keyed by
            name with a `paths` list each.
        _fail: Seam for testing the failure path.

    Returns:
        `{name: entry}`. Each entry is the introspection's own -- `paths`, plus
        `requires` / `features` where it has them -- with a `kind` added
        (`KIND_CONTRIB` or `KIND_PL`). Contrib is here in full: an extension
        ships as its own layer, composed onto the base image on demand, and is
        carved from `:tar.dev` -- which this does not touch -- so the base has
        no reason to carry a copy. A procedural language is here unless the
        flavor is defined by it.
    """
    shipped = {
        language: True
        for language in _SHIPPED_PL_LANGUAGES.get(
            introspection["flavor"],
            _DEFAULT_SHIPPED_PL_LANGUAGES,
        )
    }

    entries = {
        name: dict(entry, kind = KIND_CONTRIB)
        for name, entry in introspection["contrib"].items()
    }

    for language, entry in introspection["pl"].items():
        if language in shipped:
            continue

        name = _pl_entry_name(language)

        # Both kinds end up as one directory in the extensions catalog and one
        # repository in the registry, so the names share a namespace. Nothing
        # upstream forbids a contrib called `pltcl`, and if one ever arrives
        # the two would silently become one layer holding whichever won.
        if name in entries:
            return _fail(
                ("ERROR: procedural language %r wants the entry name %r, " +
                 "which contrib already uses") % (language, name),
            )

        entries[name] = dict(entry, kind = KIND_PL)

    return entries

def runtime_exclude_paths(introspection):
    """The installed paths the runtime tree does not ship.

    Args:
        introspection: As `layered_entries`.

    Returns:
        Sorted, de-duplicated install-relative paths, for
        `pg_install_tree(exclude_paths = ...)`.
    """
    excluded = {}

    for entry in layered_entries(introspection).values():
        for path in entry["paths"]:
            excluded[path] = True

    return sorted(excluded.keys())
