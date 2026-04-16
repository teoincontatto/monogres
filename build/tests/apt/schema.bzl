"""Unit tests for build/apt/schema.bzl."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//apt:schema.bzl", _AptSchema = "schema")
load("//tests:suite.bzl", _test_suite = "test_suite")

def _apt_group_new_test_impl(ctx):
    env = unittest.begin(ctx)

    g = _AptSchema.AptGroup.new(
        packages = ["libssl-dev"],
        resolved_names = ["libssl-dev"],
    )
    asserts.equals(env, ["libssl-dev"], g.packages)
    asserts.equals(env, ["libssl-dev"], g.resolved_names)

    return unittest.end(env)

apt_group_new_test = unittest.make(_apt_group_new_test_impl)

def _apt_group_defaults_test_impl(ctx):
    env = unittest.begin(ctx)

    g = _AptSchema.AptGroup.new()
    asserts.equals(env, [], g.packages)
    asserts.equals(env, [], g.resolved_names)

    return unittest.end(env)

apt_group_defaults_test = unittest.make(_apt_group_defaults_test_impl)

def _apt_group_serde_roundtrip_test_impl(ctx):
    env = unittest.begin(ctx)

    original = _AptSchema.AptGroup.new(
        packages = ["libssl-dev", "libc6-dev"],
        resolved_names = ["libssl-dev", "libc6-dev"],
    )
    decoded = _AptSchema.AptGroup.from_dict(
        json.decode(json.encode(original)),
    )
    asserts.equals(env, original, decoded)

    return unittest.end(env)

apt_group_serde_roundtrip_test = unittest.make(_apt_group_serde_roundtrip_test_impl)

def _apt_result_new_test_impl(ctx):
    env = unittest.begin(ctx)

    r = _AptSchema.AptResult.new(
        packages = [
            {"arch": "amd64", "name": "libc6", "version": "2.36-9"},
            {"arch": "amd64", "name": "libssl3", "version": "3.0.0"},
        ],
        package_groups = {"k1": ["libssl-dev"]},
        package_name_map = {"libssl-dev": "libssl3-dev"},
    )
    asserts.equals(env, {"libssl-dev": "libssl3-dev"}, r.package_name_map)
    asserts.equals(env, ["libc6", "libssl3"], r.deb_packages)
    asserts.equals(env, ["libssl-dev"], r.groups["k1"].packages)
    asserts.equals(env, ["libssl3-dev"], r.groups["k1"].resolved_names)
    asserts.equals(env, {"amd64": "3.0.0"}, r.pkg_info["libssl3"])
    asserts.equals(env, {"amd64": "2.36-9"}, r.pkg_info["libc6"])

    return unittest.end(env)

apt_result_new_test = unittest.make(_apt_result_new_test_impl)

def _apt_result_defaults_test_impl(ctx):
    env = unittest.begin(ctx)

    r = _AptSchema.AptResult.new()
    asserts.equals(env, {}, r.package_name_map)
    asserts.equals(env, [], r.deb_packages)
    asserts.equals(env, {}, r.groups)
    asserts.equals(env, {}, r.pkg_info)

    return unittest.end(env)

apt_result_defaults_test = unittest.make(_apt_result_defaults_test_impl)

def _apt_result_serde_roundtrip_test_impl(ctx):
    env = unittest.begin(ctx)

    original = _AptSchema.AptResult.new(
        packages = [
            {"arch": "amd64", "name": "libc6", "version": "2.36-9"},
            {"arch": "arm64", "name": "libc6", "version": "2.36-9"},
            {"arch": "amd64", "name": "libssl3", "version": "3.0.0"},
        ],
        package_groups = {
            "k1": ["libc6-dev"],
            "k2": ["libssl-dev"],
        },
        package_name_map = {"libssl-dev": "libssl3-dev"},
    )
    decoded = _AptSchema.AptResult.from_dict(
        json.decode(json.encode(original)),
    )
    asserts.equals(env, original, decoded)

    return unittest.end(env)

apt_result_serde_roundtrip_test = unittest.make(_apt_result_serde_roundtrip_test_impl)

def _apt_result_from_empty_test_impl(ctx):
    env = unittest.begin(ctx)

    r = _AptSchema.AptResult.from_dict({})
    asserts.equals(env, _AptSchema.AptResult.new(), r)

    r2 = _AptSchema.AptResult.from_dict(None)
    asserts.equals(env, _AptSchema.AptResult.new(), r2)

    return unittest.end(env)

apt_result_from_empty_test = unittest.make(_apt_result_from_empty_test_impl)

TEST_SUITE_NAME = "schema"

TEST_SUITE_TESTS = dict(
    AptGroup_defaults = apt_group_defaults_test,
    AptGroup_new = apt_group_new_test,
    AptGroup_serde_roundtrip = apt_group_serde_roundtrip_test,
    AptResult_defaults = apt_result_defaults_test,
    AptResult_from_empty = apt_result_from_empty_test,
    AptResult_new = apt_result_new_test,
    AptResult_serde_roundtrip = apt_result_serde_roundtrip_test,
)

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
