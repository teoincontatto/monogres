"""
Private e2e tests for the `@pg_pkgs` hub.

Three-phase pattern:
- Phase 1: walk a sample of packages + sysroot groups at BUILD time.
- Phase 2: unittest invariants on the expected label shapes.
- Phase 3: `build_test` on one sysroot flatten target (forces @pg_pkgs to
  produce at least one resolved artifact).
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("@monogres//utils:stable_key.bzl", "stable_key")

def _invariants_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.true(
        env,
        len(ctx.attr.packages) >= 1,
        "at least one sample package",
    )

    # every package has a non-empty version and at least one arch
    for p in json.decode(ctx.attr.package_info_json):
        asserts.true(env, p["package"] != "")
        asserts.true(env, p["version"] != "")
        asserts.true(env, len(p["archs"]) >= 1)

    # every sysroot group has a stable key
    for s in json.decode(ctx.attr.sysroot_keys_json):
        asserts.true(env, s["group"] != "")
        asserts.true(env, s["key"].startswith("sysroot-"))

    return unittest.end(env)

_invariants_test = unittest.make(
    _invariants_test_impl,
    attrs = dict(
        packages = attr.string_list(mandatory = True),
        package_info_json = attr.string(mandatory = True),
        sysroot_keys_json = attr.string(mandatory = True),
    ),
)

def e2e_tests(name, packages, sysroot_groups):
    """Phase 2 + Phase 3 targets for `@pg_pkgs`.

    Args:
        name: test-suite name.
        packages: `{pkg: {archs: [...], version: ...}}`.
        sysroot_groups: `{group_name: [pkg_labels]}`.
    """

    pkg_names = sorted(packages.keys())
    package_info = [
        dict(package = pkg, version = info["version"], archs = sorted(info["archs"]))
        for pkg, info in sorted(packages.items())
    ]
    sysroot_keys = [
        dict(group = group, key = stable_key(labels, prefix = "sysroot"))
        for group, labels in sorted(sysroot_groups.items())
    ]

    _invariants_test(
        name = "%s_invariants" % name,
        packages = pkg_names,
        package_info_json = json.encode(package_info),
        sysroot_keys_json = json.encode(sysroot_keys),
        size = "small",
    )

    # --- Phase 3: real build ---
    # build one sysroot target (forces package resolution and flatten action),
    # pick the largest group by label count
    largest_group_labels = None
    largest_count = 0
    for _, labels in sorted(sysroot_groups.items()):
        if len(labels) > largest_count:
            largest_count = len(labels)
            largest_group_labels = labels

    if largest_group_labels:
        sk = stable_key(largest_group_labels, prefix = "sysroot")

        # size reflects the weight of the underlying build, not the test action.
        build_test(
            name = "%s_build" % name,
            size = "large",
            timeout = "short",
            targets = ["@pg_pkgs//deb/sysroots:%s" % sk],
        )
