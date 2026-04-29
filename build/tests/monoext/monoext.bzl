"""
Unit tests for monoext/monoext.bzl::_tag_key.

`_tag_key` hashes a module-ext tag's attrs (minus `exclude_attrs`) so
conflicting declarations can be detected: two `monoext.monogres(...)` calls with
the same `name` but different configs must produce different keys; two calls
with identical configs must produce the same key; `name` differences alone must
be ignored when `name` is in `exclude_attrs`.

Bazel's real tag objects only expose their attrs via `dir(tag)` + `getattr`. A
plain `struct(...)` has exactly the same surface for these two built-ins, so
mock tags are just structs.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//monoext:monoext.bzl", _Monoext = "testing")
load("//tests:suite.bzl", _test_suite = "test_suite")

def _mock_tag(name, base, extensions = None, build_repo = "monogres"):
    return struct(
        name = name,
        base = base,
        extensions = extensions,
        build_repo = build_repo,
    )

# --- tag_key ---------------------------------------------------------------

def _same_config_same_key_test_impl(ctx):
    """Two identical tag configs → same key."""
    env = unittest.begin(ctx)

    a = _mock_tag("pg", "//catalog/postgres:repo.json")
    b = _mock_tag("pg", "//catalog/postgres:repo.json")

    asserts.equals(
        env,
        _Monoext._tag_key(a),
        _Monoext._tag_key(b),
    )

    return unittest.end(env)

same_config_same_key_test = unittest.make(_same_config_same_key_test_impl)

def _different_attr_different_key_test_impl(ctx):
    """Differ on `base` → different keys."""
    env = unittest.begin(ctx)

    a = _mock_tag("pg", "//catalog/postgres:repo.json")
    b = _mock_tag("pg", "//other/postgres:repo.json")

    asserts.true(
        env,
        _Monoext._tag_key(a) != _Monoext._tag_key(b),
    )

    return unittest.end(env)

different_attr_different_key_test = unittest.make(
    _different_attr_different_key_test_impl,
)

def _different_extensions_different_key_test_impl(ctx):
    """Differ only on `extensions` → different keys."""
    env = unittest.begin(ctx)

    a = _mock_tag("pg", "//catalog/postgres:repo.json", extensions = None)
    b = _mock_tag(
        "pg",
        "//catalog/postgres:repo.json",
        extensions = "//catalog/extensions:index.json",
    )

    asserts.true(
        env,
        _Monoext._tag_key(a) != _Monoext._tag_key(b),
    )

    return unittest.end(env)

different_extensions_different_key_test = unittest.make(
    _different_extensions_different_key_test_impl,
)

def _exclude_name_attr_test_impl(ctx):
    """Different `name`, same other attrs → same key when name is excluded."""
    env = unittest.begin(ctx)

    a = _mock_tag("pg", "//catalog/postgres:repo.json")
    b = _mock_tag("alt", "//catalog/postgres:repo.json")

    # without excluding name → different keys
    asserts.true(
        env,
        _Monoext._tag_key(a) != _Monoext._tag_key(b),
    )

    # excluding name → same key
    asserts.equals(
        env,
        _Monoext._tag_key(a, exclude_attrs = ["name"]),
        _Monoext._tag_key(b, exclude_attrs = ["name"]),
    )

    return unittest.end(env)

exclude_name_attr_test = unittest.make(_exclude_name_attr_test_impl)

def _exclude_attr_not_named_name_test_impl(ctx):
    """exclude_attrs accepts any attr list; test with `build_repo`."""
    env = unittest.begin(ctx)

    a = _mock_tag("pg", "//catalog/postgres:repo.json", build_repo = "monogres")
    b = _mock_tag("pg", "//catalog/postgres:repo.json", build_repo = "other_build_repo")

    asserts.true(
        env,
        _Monoext._tag_key(a) != _Monoext._tag_key(b),
    )
    asserts.equals(
        env,
        _Monoext._tag_key(a, exclude_attrs = ["build_repo"]),
        _Monoext._tag_key(b, exclude_attrs = ["build_repo"]),
    )

    return unittest.end(env)

exclude_attr_not_named_name_test = unittest.make(
    _exclude_attr_not_named_name_test_impl,
)

TEST_SUITE_NAME = "tag_key"

TEST_SUITE_TESTS = dict(
    different_attr_different_key = different_attr_different_key_test,
    different_extensions_different_key = different_extensions_different_key_test,
    exclude_attr_not_named_name = exclude_attr_not_named_name_test,
    exclude_name_attr = exclude_name_attr_test,
    same_config_same_key = same_config_same_key_test,
)

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
