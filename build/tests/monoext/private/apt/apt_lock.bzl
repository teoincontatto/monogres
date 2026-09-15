"""
Unit tests for monoext/private/apt/apt_lock.bzl.

Covers `requested_mismatch(lock, requested)`: whether a lock was generated for
the set of roots being asked for now. Only a root carries its dependency
closure, so a lock that merely *contains* a package is not a lock that can
answer for it.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//monoext/private/apt:apt_lock.bzl", "apt_lock")
load("//tests:suite.bzl", _test_suite = "test_suite")

def _lock(requested):
    return apt_lock.new(
        snapshot = "20260316T000000Z",
        archs = ["amd64", "arm64"],
        packages = [],
        package_name_map = {},
        requested = requested,
    )

def _requested_mismatch_agrees_test_impl(ctx):
    """The same roots in a different order are the same roots."""
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        None,
        apt_lock.requested_mismatch(
            _lock(["libssl-dev", "zlib1g-dev"]),
            ["zlib1g-dev", "libssl-dev"],
        ),
    )

    return unittest.end(env)

requested_mismatch_agrees_test = unittest.make(
    _requested_mismatch_agrees_test_impl,
)

def _requested_mismatch_new_root_test_impl(ctx):
    """pgrouting's case: a catalog entry added after the lock was written."""
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        "requested but not resolved as roots: libboost-dev",
        apt_lock.requested_mismatch(
            _lock(["libgdal-dev"]),
            ["libboost-dev", "libgdal-dev"],
        ),
    )

    return unittest.end(env)

requested_mismatch_new_root_test = unittest.make(
    _requested_mismatch_new_root_test_impl,
)

def _requested_mismatch_dropped_root_test_impl(ctx):
    """A root nothing asks for any more is a stale lock just the same."""
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        "resolved as roots but no longer requested: libgdal-dev",
        apt_lock.requested_mismatch(
            _lock(["libboost-dev", "libgdal-dev"]),
            ["libboost-dev"],
        ),
    )

    return unittest.end(env)

requested_mismatch_dropped_root_test = unittest.make(
    _requested_mismatch_dropped_root_test_impl,
)

def _requested_mismatch_legacy_lock_test_impl(ctx):
    """A lock written before `requested` existed records no roots at all."""
    env = unittest.begin(ctx)

    decoded = apt_lock.decode(json.encode({
        "archs": ["amd64"],
        "package_name_map": {},
        "packages": [],
        "snapshot": "20260316T000000Z",
        "version": apt_lock.LOCK_VERSION,
    }))

    asserts.equals(env, [], decoded.requested)
    asserts.equals(
        env,
        "requested but not resolved as roots: libssl-dev",
        apt_lock.requested_mismatch(decoded, ["libssl-dev"]),
    )

    return unittest.end(env)

requested_mismatch_legacy_lock_test = unittest.make(
    _requested_mismatch_legacy_lock_test_impl,
)

TEST_SUITE_NAME = "apt_lock"

TEST_SUITE_TESTS = dict(
    requested_mismatch_agrees = requested_mismatch_agrees_test,
    requested_mismatch_new_root = requested_mismatch_new_root_test,
    requested_mismatch_dropped_root = requested_mismatch_dropped_root_test,
    requested_mismatch_legacy_lock = requested_mismatch_legacy_lock_test,
)

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
