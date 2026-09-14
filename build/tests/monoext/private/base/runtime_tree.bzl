"""
Unit tests for monoext/private/base/runtime_tree.bzl.

Covers `runtime_exclude_paths(introspection)`: the part of the runtime carve
that comes from the introspection rather than from a path glob.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//monoext/private/base:runtime_tree.bzl", "runtime_exclude_paths")
load("//tests:suite.bzl", _test_suite = "test_suite")

def _introspection(flavor):
    return {
        "contrib": {
            "hstore": {"paths": [
                "lib/hstore.so",
                "share/extension/hstore.control",
            ]},
            # Two contribs sharing a path: the carve is a set, not a list.
            "hstore_plperl": {"paths": [
                "lib/hstore.so",
                "lib/hstore_plperl.so",
            ]},
        },
        "flavor": flavor,
        "pl": {
            "plisql": {"paths": ["lib/plisql.so"]},
            "plperl": {"paths": [
                "lib/plperl.so",
                "share/extension/plperl.control",
            ]},
            "plpgsql": {"paths": [
                "lib/plpgsql.so",
                "share/extension/plpgsql.control",
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
        "share/extension/hstore.control",
        "share/extension/plperl.control",
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

TEST_SUITE_NAME = "runtime_tree"

TEST_SUITE_TESTS = dict(
    runtime_exclude_paths = runtime_exclude_paths_test,
    runtime_exclude_paths_flavor_pl = runtime_exclude_paths_flavor_pl_test,
)

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
