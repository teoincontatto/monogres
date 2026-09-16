"""
Unit tests for monoext/private/base.bzl pure helpers.

Exercises `_build_entries(base_data, versions_deps, hub_name)`, the pure
function that maps a `BaseData` + per-version deps into the JSON-encoded
`BaseEntry` values passed to `base_repo.entries`. `hub_name` is used to
pre-qualify `@{hub_name}//{version}/deps/...` alias labels baked onto each
`BaseTarget.deps` before the JSON boundary.

Also covers the option-conditional deps: `_group_metadata` (what the flavor
requests -- the union, so the hub can name every package and one apt lock
answers for every option set) and `_option_excluded_packages` /
`_filter_version_deps` (what one target lists -- only the options its build
actually has).
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//monoext/private:base.bzl", _Base = "testing")

# buildifier: disable=bzl-visibility
load("//monoext/private/base:schema.bzl", _BaseSchema = "schema")

# buildifier: disable=bzl-visibility
load("//monoext/private/base/build_options:pg.bzl", "OPTION_SETS")

# buildifier: disable=bzl-visibility
load("//monoext/private/pkgs:schema.bzl", _PkgsSchema = "schema")
load("//tests:suite.bzl", _test_suite = "test_suite")

def _base_data(versions):
    return _BaseSchema.BaseData.new(
        default_version = versions[-1],
        introspect_repos = {},
        introspect_paths_repos = {},
        metadata = {},
        pkgs_group = struct(
            name = "postgres",
            versions = versions,
            metadata = {},
        ),
        source_repo = "pg_src",
        versions = versions,
    )

def _buildtime_deps(sysroot_labels_by_arch):
    bt = _PkgsSchema.DepsInfo.new(
        packages = ["libssl-dev"],
        pkgs_labels = ["@pg_pkgs//deb/libssl-dev:libssl-dev"],
        sysroot_labels_by_arch = sysroot_labels_by_arch,
    )
    return _PkgsSchema.VersionDeps.new(buildtime = bt)

# --- build_entries ---------------------------------------------------------

def _build_entries_one_version_no_deps_test_impl(ctx):
    """One PG version, no deps → one entry with len(OPTION_SETS) targets."""
    env = unittest.begin(ctx)

    entries = _Base._build_entries(
        _base_data(["18.1"]),
        versions_deps = {},
        hub_name = "pg",
    )

    asserts.equals(env, ["18.1"], sorted(entries))

    entry = _BaseSchema.BaseEntry.decode(entries["18.1"])
    asserts.equals(env, "pg_src", entry.source_repo)
    asserts.equals(env, len(OPTION_SETS), len(entry.targets))
    asserts.equals(env, _PkgsSchema.VersionDeps.new(), entry.versions_deps)

    # entry carries a per-version source struct with hub-qualified labels
    asserts.equals(env, "18.1", entry.source.version)
    asserts.equals(env, "@pg//18.1:dir", entry.source.dir)
    asserts.equals(env, "@pg//18.1:files", entry.source.files)

    # every target has deps with sysroot=None (no deps at this version)
    for target in entry.targets:
        asserts.equals(env, None, target.deps.buildtime.sysroot)
        asserts.equals(env, [], target.deps.buildtime.packages)
        asserts.equals(env, None, target.deps.runtime.sysroot)
        asserts.equals(env, [], target.deps.runtime.packages)
        asserts.equals(env, "18.1", target.version)
        asserts.equals(
            env,
            "@pg//18.1/%s:tar" % target.option_set,
            target.artifact,
        )
        asserts.equals(env, entry.source, target.source)

    return unittest.end(env)

build_entries_one_version_no_deps_test = unittest.make(
    _build_entries_one_version_no_deps_test_impl,
)

def _build_entries_option_sets_coverage_test_impl(ctx):
    """Every option set appears exactly once per version."""
    env = unittest.begin(ctx)

    entries = _Base._build_entries(
        _base_data(["18.1"]),
        versions_deps = {},
        hub_name = "pg",
    )

    entry = _BaseSchema.BaseEntry.decode(entries["18.1"])
    option_sets_seen = sorted([t.option_set for t in entry.targets])
    asserts.equals(env, sorted(OPTION_SETS), option_sets_seen)

    return unittest.end(env)

build_entries_option_sets_coverage_test = unittest.make(
    _build_entries_option_sets_coverage_test_impl,
)

def _build_entries_bakes_qualified_deps_test_impl(ctx):
    """A version with buildtime deps → every target carries pre-qualified alias labels."""
    env = unittest.begin(ctx)

    shared_labels_by_arch = {
        "amd64": "@pgbuildtime-abc//debian/12/amd64:sysroot",
        "arm64": "@pgbuildtime-abc//debian/12/arm64:sysroot",
    }
    entries = _Base._build_entries(
        _base_data(["18.1"]),
        versions_deps = {"18.1": _buildtime_deps(shared_labels_by_arch)},
        hub_name = "mypg",
    )

    entry = _BaseSchema.BaseEntry.decode(entries["18.1"])
    for target in entry.targets:
        asserts.equals(
            env,
            "@mypg//18.1/deps/buildtime:sysroot",
            target.deps.buildtime.sysroot,
        )
        asserts.equals(
            env,
            ["@mypg//18.1/deps/buildtime/pkgs:libssl-dev"],
            target.deps.buildtime.packages,
        )

        # artifact + source labels also use the hub_name
        asserts.equals(
            env,
            "@mypg//18.1/%s:tar" % target.option_set,
            target.artifact,
        )
        asserts.equals(env, "@mypg//18.1:dir", target.source.dir)

    # entry-level versions_deps carries the per-arch @pgbuildtime labels for the
    # BUILD-file writers (`versions.bzl::write_base_version`), not for the
    # consumer surface.
    asserts.equals(
        env,
        shared_labels_by_arch,
        entry.versions_deps.buildtime.sysroot_labels_by_arch,
    )

    return unittest.end(env)

build_entries_bakes_qualified_deps_test = unittest.make(
    _build_entries_bakes_qualified_deps_test_impl,
)

def _build_entries_multiple_versions_test_impl(ctx):
    """One entry per PG version, sorted."""
    env = unittest.begin(ctx)

    entries = _Base._build_entries(
        _base_data(["16.5", "17.0", "18.1"]),
        versions_deps = {},
        hub_name = "pg",
    )

    asserts.equals(env, ["16.5", "17.0", "18.1"], sorted(entries))

    # each entry is independently decodable and points at its own version
    for v in ("16.5", "17.0", "18.1"):
        entry = _BaseSchema.BaseEntry.decode(entries[v])
        for target in entry.targets:
            asserts.equals(env, v, target.version)

    return unittest.end(env)

build_entries_multiple_versions_test = unittest.make(
    _build_entries_multiple_versions_test_impl,
)

# --- option-conditional deps ----------------------------------------------

_LLVM_OPTION_DEPS = {
    "llvm": {
        "runtime": {
            "debian": {
                "12": {"*": ["libllvm14", "llvm-14-runtime"]},
                "13": {"*": ["libllvm19", "llvm-19-runtime"]},
            },
        },
    },
}

_BASE_DEPS = {
    "runtime": {"debian": {"13": {"*": ["libssl3", "zlib1g"]}}},
}

def _group_metadata_test_impl(ctx):
    """The flavor requests the union, so every package stays nameable."""
    env = unittest.begin(ctx)

    merged = _Base._group_metadata({
        "deps": _BASE_DEPS,
        "option_deps": _LLVM_OPTION_DEPS,
    })

    asserts.equals(
        env,
        ["libllvm19", "libssl3", "llvm-19-runtime", "zlib1g"],
        merged["deps"]["runtime"]["debian"]["13"]["*"],
    )

    # A release the base block says nothing about still gets its option's
    # packages -- the union is over both, not an intersection.
    asserts.equals(
        env,
        ["libllvm14", "llvm-14-runtime"],
        merged["deps"]["runtime"]["debian"]["12"]["*"],
    )

    # The caller's metadata is also what the build options and the test payload
    # read, so it must come back untouched.
    asserts.equals(
        env,
        ["libssl3", "zlib1g"],
        _BASE_DEPS["runtime"]["debian"]["13"]["*"],
    )

    return unittest.end(env)

group_metadata_test = unittest.make(_group_metadata_test_impl)

def _group_metadata_no_options_test_impl(ctx):
    """A flavor with no option_deps is handed back as it came."""
    env = unittest.begin(ctx)

    metadata = {"deps": _BASE_DEPS}
    asserts.equals(env, metadata, _Base._group_metadata(metadata))

    return unittest.end(env)

group_metadata_no_options_test = unittest.make(
    _group_metadata_no_options_test_impl,
)

def _option_excluded_packages_test_impl(ctx):
    """Off means: named by no set that builds it, and not auto-detected."""
    env = unittest.begin(ctx)

    # `minimal`: no llvm, and auto-features off -- nothing detects it.
    asserts.equals(
        env,
        {"runtime": {
            "libllvm14": True,
            "libllvm19": True,
            "llvm-14-runtime": True,
            "llvm-19-runtime": True,
        }},
        _Base._option_excluded_packages(_LLVM_OPTION_DEPS, {}, "disabled"),
    )

    # `regular`: named explicitly.
    asserts.equals(
        env,
        {},
        _Base._option_excluded_packages(
            _LLVM_OPTION_DEPS,
            {"llvm": "enabled"},
            "disabled",
        ),
    )

    # `full`: not named, but auto-features finds it -- which is how that set
    # gets plperl and pltcl without listing them either.
    asserts.equals(
        env,
        {},
        _Base._option_excluded_packages(_LLVM_OPTION_DEPS, {}, "enabled"),
    )

    # Explicitly off beats auto-detection.
    asserts.equals(
        env,
        {"runtime": {
            "libllvm14": True,
            "libllvm19": True,
            "llvm-14-runtime": True,
            "llvm-19-runtime": True,
        }},
        _Base._option_excluded_packages(
            _LLVM_OPTION_DEPS,
            {"llvm": "disabled"},
            "enabled",
        ),
    )

    return unittest.end(env)

option_excluded_packages_test = unittest.make(
    _option_excluded_packages_test_impl,
)

def _filter_version_deps_test_impl(ctx):
    """`packages` and its parallel labels narrow together; the sysroot does not."""
    env = unittest.begin(ctx)

    runtime = _PkgsSchema.DepsInfo.new(
        packages = ["libllvm19", "libssl3", "llvm-19-runtime", "zlib1g"],
        pkgs_labels = [
            "@pg_pkgs//deb/libllvm19:libllvm19",
            "@pg_pkgs//deb/libssl3:libssl3",
            "@pg_pkgs//deb/llvm-19-runtime:llvm-19-runtime",
            "@pg_pkgs//deb/zlib1g:zlib1g",
        ],
        sysroot_tar_labels_by_arch = {"amd64": "@pgbuildtime-rt//13/amd64:t"},
    )
    vd = _PkgsSchema.VersionDeps.new(runtime = runtime)

    filtered = _Base._filter_version_deps(
        vd,
        {"runtime": {"libllvm19": True, "llvm-19-runtime": True}},
    )

    asserts.equals(env, ["libssl3", "zlib1g"], filtered.runtime.packages)
    asserts.equals(
        env,
        [
            "@pg_pkgs//deb/libssl3:libssl3",
            "@pg_pkgs//deb/zlib1g:zlib1g",
        ],
        filtered.runtime.pkgs_labels,
    )

    # A sysroot is a built tree, one per group, and only the regress harness
    # reads it -- so it stays whole rather than becoming a tree nothing built.
    asserts.equals(
        env,
        {"amd64": "@pgbuildtime-rt//13/amd64:t"},
        filtered.runtime.sysroot_tar_labels_by_arch,
    )

    # A kind the exclusion says nothing about is passed through by identity.
    asserts.equals(env, vd.buildtime, filtered.buildtime)

    return unittest.end(env)

filter_version_deps_test = unittest.make(_filter_version_deps_test_impl)

def _filter_version_deps_nothing_excluded_test_impl(ctx):
    """Nothing to drop returns the input itself, not a rebuilt copy."""
    env = unittest.begin(ctx)

    vd = _PkgsSchema.VersionDeps.new(
        runtime = _PkgsSchema.DepsInfo.new(packages = ["libssl3"]),
    )

    asserts.equals(env, vd, _Base._filter_version_deps(vd, {}))
    asserts.equals(
        env,
        vd,
        _Base._filter_version_deps(vd, {"buildtime": {"clang-19": True}}),
    )

    return unittest.end(env)

filter_version_deps_nothing_excluded_test = unittest.make(
    _filter_version_deps_nothing_excluded_test_impl,
)

TEST_SUITE_NAME = "base_top"

TEST_SUITE_TESTS = dict(
    build_entries_bakes_qualified_deps = build_entries_bakes_qualified_deps_test,
    build_entries_multiple_versions = build_entries_multiple_versions_test,
    build_entries_one_version_no_deps = build_entries_one_version_no_deps_test,
    build_entries_option_sets_coverage = build_entries_option_sets_coverage_test,
    filter_version_deps = filter_version_deps_test,
    filter_version_deps_nothing_excluded = (
        filter_version_deps_nothing_excluded_test
    ),
    group_metadata = group_metadata_test,
    group_metadata_no_options = group_metadata_no_options_test,
    option_excluded_packages = option_excluded_packages_test,
)

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
