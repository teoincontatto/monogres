"""
Unit tests for monoext/private/base/runtime_tree.bzl.

Covers the two halves of one decision: `layered_entries(introspection)`, which
names what the base image leaves out and the layer that carries it, and
`runtime_exclude_paths(introspection)`, the part of the runtime carve that comes
from the introspection rather than from a path glob.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load(
    "//monoext/private/base:runtime_tree.bzl",
    "layered_entries",
    "runtime_exclude_paths",
)
load("//tests:suite.bzl", _test_suite = "test_suite")

def _introspection(flavor):
    return {
        "contrib": {
            "hstore": {"paths": [
                "lib/hstore.so",
                "share/extension/hstore.control",
            ]},
            # Two contribs sharing a path: the carve is a set, not a list.
            "hstore_plperl": {
                "paths": [
                    "lib/hstore.so",
                    "lib/hstore_plperl.so",
                ],
                "requires": ["hstore", "plperl", "plperlu"],
            },
        },
        "flavor": flavor,
        "pl": {
            "plisql": {"paths": ["lib/plisql.so"]},
            "plperl": {"paths": [
                "lib/plperl.so",
                "share/extension/plperl.control",
                # The untrusted twin is the same install, not a second entry.
                "share/extension/plperlu.control",
            ]},
            "plpgsql": {"paths": [
                "lib/plpgsql.so",
                "share/extension/plpgsql.control",
            ]},
            # Keyed `plpython`, created as `plpython3u`, served by
            # `plpython3.so`: the one language where all three names differ.
            "plpython": {"paths": [
                "lib/plpython3.so",
                "share/extension/plpython3u.control",
            ]},
        },
    }

def _runtime_exclude_paths_test_impl(ctx):
    """All of contrib, every PL but plpgsql; sorted and de-duplicated."""
    env = unittest.begin(ctx)

    asserts.equals(env, [
        "lib/hstore.so",
        "lib/hstore_plperl.so",
        "lib/plisql.so",
        "lib/plperl.so",
        "lib/plpython3.so",
        "share/extension/hstore.control",
        "share/extension/plperl.control",
        "share/extension/plperlu.control",
        "share/extension/plpython3u.control",
    ], runtime_exclude_paths(_introspection("postgres")))

    return unittest.end(env)

runtime_exclude_paths_test = unittest.make(_runtime_exclude_paths_test_impl)

def _runtime_exclude_paths_flavor_pl_test_impl(ctx):
    """A flavor's own PL stays: plisql is to IvorySQL what plpgsql is to PG."""
    env = unittest.begin(ctx)

    excluded = runtime_exclude_paths(_introspection("ivorysql"))

    asserts.false(env, "lib/plisql.so" in excluded)
    asserts.false(env, "lib/plpgsql.so" in excluded)
    asserts.true(env, "lib/plperl.so" in excluded)

    return unittest.end(env)

runtime_exclude_paths_flavor_pl_test = unittest.make(
    _runtime_exclude_paths_flavor_pl_test_impl,
)

def _layered_entries_test_impl(ctx):
    """Contrib in full, plus every PL the flavor is not defined by.

    A PL entry is named the way `CREATE EXTENSION` names it -- which is also how
    a dependent contrib's `.control requires` names it, and so what lets
    `hstore_plpython`'s requires resolve to a layer -- not the way the language
    is keyed.
    """
    env = unittest.begin(ctx)

    entries = layered_entries(_introspection("postgres"))

    asserts.equals(env, [
        "hstore",
        "hstore_plperl",
        "plisql",
        "plperl",
        "plpython3u",
    ], sorted(entries))

    return unittest.end(env)

layered_entries_test = unittest.make(_layered_entries_test_impl)

def _layered_entries_kind_test_impl(ctx):
    """Each entry says what it is, and keeps the introspection's own fields."""
    env = unittest.begin(ctx)

    entries = layered_entries(_introspection("postgres"))

    asserts.equals(env, "contrib", entries["hstore_plperl"]["kind"])
    asserts.equals(env, "pl", entries["plpython3u"]["kind"])

    # `requires` is what the catalog's prerequisite metadata is generated from,
    # so it has to survive the kind being added.
    asserts.equals(
        env,
        ["hstore", "plperl", "plperlu"],
        entries["hstore_plperl"]["requires"],
    )
    asserts.equals(
        env,
        ["lib/plpython3.so", "share/extension/plpython3u.control"],
        entries["plpython3u"]["paths"],
    )

    return unittest.end(env)

layered_entries_kind_test = unittest.make(_layered_entries_kind_test_impl)

def _layered_entries_flavor_pl_test_impl(ctx):
    """A shipped language gets no entry: nothing layers what the base carries."""
    env = unittest.begin(ctx)

    entries = layered_entries(_introspection("ivorysql"))

    asserts.equals(env, [
        "hstore",
        "hstore_plperl",
        "plperl",
        "plpython3u",
    ], sorted(entries))

    return unittest.end(env)

layered_entries_flavor_pl_test = unittest.make(
    _layered_entries_flavor_pl_test_impl,
)

def _layered_entries_collision_test_impl(ctx):
    """A contrib named after a PL would otherwise silently become one layer."""
    env = unittest.begin(ctx)

    introspection = _introspection("postgres")
    introspection["contrib"]["plpython3u"] = {"paths": ["lib/imposter.so"]}

    failures = []
    layered_entries(introspection, _fail = failures.append)

    asserts.equals(env, 1, len(failures))
    asserts.true(
        env,
        "which contrib already uses" in failures[0],
        "unexpected failure message: %s" % failures,
    )

    return unittest.end(env)

layered_entries_collision_test = unittest.make(
    _layered_entries_collision_test_impl,
)

TEST_SUITE_NAME = "runtime_tree"

TEST_SUITE_TESTS = dict(
    layered_entries = layered_entries_test,
    layered_entries_collision = layered_entries_collision_test,
    layered_entries_flavor_pl = layered_entries_flavor_pl_test,
    layered_entries_kind = layered_entries_kind_test,
    runtime_exclude_paths = runtime_exclude_paths_test,
    runtime_exclude_paths_flavor_pl = runtime_exclude_paths_flavor_pl_test,
)

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
