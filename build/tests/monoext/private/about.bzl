"""
Unit tests for monoext/about.bzl.

A versioned `about.json` is the newest version in full under `latest` and every
older one as a JSON Merge Patch over the version after it; these pin down that
each version resolves to what monobot wrote for it.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//monoext:about.bzl", "about_versions", "apply_patch")
load("//tests:suite.bzl", _test_suite = "test_suite")

def _apply_patch_test_impl(ctx):
    """Objects merge, anything else replaces, and `null` removes."""
    env = unittest.begin(ctx)

    target = {"a": {"b": 1, "c": 2}, "d": [1, 2], "e": "x"}
    merged = apply_patch(target, {"a": {"c": None, "f": 3}, "d": [3], "e": None})

    asserts.equals(env, {"a": {"b": 1, "f": 3}, "d": [3]}, merged)
    asserts.equals(
        env,
        {"a": {"b": 1, "c": 2}, "d": [1, 2], "e": "x"},
        target,
        "the target was modified",
    )

    return unittest.end(env)

apply_patch_test = unittest.make(_apply_patch_test_impl)

def _about_versions_test_impl(ctx):
    """Older versions apply newest first, each over the one after it."""
    env = unittest.begin(ctx)

    resolved = about_versions({
        "latest": {
            "version": "2.0",
            "description": "new",
            "license": "MIT",
            "ref": "v2.0",
            "contrib": {"one": {"description": "one"}, "two": {"description": "two"}},
        },
        "versions": {
            "1.1": {},
            "1.0": {
                "description": "old",
                "license": None,
                "ref": "v1.0",
                "contrib": {"one": {"description": "the first"}, "two": None},
            },
        },
    })

    asserts.equals(env, ["2.0", "1.1", "1.0"], resolved.keys())
    asserts.equals(
        env,
        {
            "description": "new",
            "license": "MIT",
            "ref": "v2.0",
            "contrib": {"one": {"description": "one"}, "two": {"description": "two"}},
        },
        resolved["1.1"],
    )
    asserts.equals(
        env,
        {
            "description": "old",
            "ref": "v1.0",
            "contrib": {"one": {"description": "the first"}},
        },
        resolved["1.0"],
    )
    asserts.equals(env, "two", resolved["2.0"]["contrib"]["two"]["description"])

    return unittest.end(env)

about_versions_test = unittest.make(_about_versions_test_impl)

def _about_versions_empty_test_impl(ctx):
    """A document with no `latest` describes no version."""
    env = unittest.begin(ctx)

    asserts.equals(env, {}, about_versions({}))

    return unittest.end(env)

about_versions_empty_test = unittest.make(_about_versions_empty_test_impl)

TEST_SUITE_NAME = "about"

TEST_SUITE_TESTS = dict(
    about_versions = about_versions_test,
    about_versions_empty = about_versions_empty_test,
    apply_patch = apply_patch_test,
)

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
