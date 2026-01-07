"""
Postgres build configuration.
"""

load("@pg_src//:repo.bzl", "DEFAULT_VERSION", "METADATA", "REPO_NAME", "VERSIONS")
load(":build_options.bzl", "DEFAULT_OPTION_SET", "OPTION_SETS", "build_options")

def _target(name, version, option_set, repo_name):
    """
    Creates a struct representing a Postgres build target.

    Args:
        name (str): Base name for the target (e.g. "postgres").
        version (str): Postgres version string (e.g. "16.0"). Must be one of
            the versions in `pg_src`.
        option_set (str): The name of the Postgres option sets to add to the
            target. An option set is a predefined combination of compile-time
            options.
        repo_name (str): The name of the external Bazel repository with the
            Postgres source code.

    Returns:
        A `pg_target` `struct`:
          - `name (str)`: a unique target name (e.g. "postgres~16.0").
          - `version (str)`: the Postgres version.
          - `build_options (dict)`: Meson build options that configure optional
            Postgres features and other compilation parameters.
          - `auto_features (str)`: Controls the enabling and disabling of Meson
            build options and optional Postgres features not specified in
            `build_options`.
          - `pg_src (str)`: the label of the external Bazel repository with the
            source code for the given Postgres version.
    """
    if version not in VERSIONS:
        fail("Postgres version %s is not available in pg_src" % version)

    options, auto_features = build_options(
        version,
        option_set,
        METADATA.get("build_options", {}),
    )

    pg_version = None

    if option_set == "full":
        # We want the "full" option_set to be the default Postgres target
        pg_version = struct(
            name = "~".join((name, version)),
            version = version,
        )

    return struct(
        name = "~".join((name, version, option_set)),
        version = version,
        option_set = option_set,
        build_options = options,
        auto_features = auto_features,
        pg_src = "@%s//%s" % (repo_name, version),
        pg_version = pg_version,
    )

def _new(name, versions, option_sets, repo_name):
    """
    Creates a config `struct` containing build targets for multiple Postgres versions.

    Args:
        name (str): A base name for the group of targets (e.g. "postgres").
        versions (list[str]): List of Postgres versions.
        option_sets (list[str]): The names of the Postgres option sets to
            add to the targets. An option set is a predefined combination of
            compile-time options.
        repo_name (str): The name of the external Bazel repository with the
            Postgres source code.

    Returns:
        A config `struct` with:
          - `name`: the base name,
          - `targets`: a list of `pg_target` `struct`s (see `_target`),
          - `default`: the `pg_target` corresponding to the `DEFAULT_VERSION`.
    """
    targets = []
    default_target = None

    for version in versions:
        for option_set in option_sets:
            target = _target(name, version, option_set, repo_name)

            if (
                version == DEFAULT_VERSION and
                option_set == DEFAULT_OPTION_SET
            ):
                default_target = target

            targets.append(target)

    return struct(
        name = name,
        targets = targets,
        default = default_target,
    )

cfg = struct(
    new = _new,
)

CFG = cfg.new(
    name = "postgres",
    versions = VERSIONS,
    option_sets = OPTION_SETS,
    repo_name = REPO_NAME,
    dependencies = [
        "@pg_deps_debian12//libc6",
        "@pg_deps_debian12//libstdc++6",
        "@pg_deps_debian12//libgcc-s1",
        "@pg_deps_debian12//libcom-err2",
        "@pg_deps_debian12//llvm-14-runtime",
        "@pg_deps_debian12//libllvm14",
        "@pg_deps_debian12//libffi8",
        "@pg_deps_debian12//libgomp1",
        "@pg_deps_debian12//libcap2",
        "@pg_deps_debian12//libcap-ng0",
        "@pg_deps_debian12//libselinux1",
        "@pg_deps_debian12//libavahi-compat-libdnssd1",
        "@pg_deps_debian12//libavahi-client3",
        "@pg_deps_debian12//libavahi-common3",
        "@pg_deps_debian12//liburing2",
        "@pg_deps_debian12//libkeyutils1",
        "@pg_deps_debian12//libgmp10",
        "@pg_deps_debian12//libnuma1",
        "@pg_deps_debian12//tzdata",
        "@pg_deps_debian12//libicu72",
        "@pg_deps_debian12//libidn2-0",
        "@pg_deps_debian12//libunistring2",
        "@pg_deps_debian12//libp11-kit0",
        "@pg_deps_debian12//libsasl2-2",
        "@pg_deps_debian12//libgnutls30",
        "@pg_deps_debian12//libtasn1-6",
        "@pg_deps_debian12//libnettle8",
        "@pg_deps_debian12//libhogweed6",
        "@pg_deps_debian12//libssl3",
        "@pg_deps_debian12//libcrypt1",
        "@pg_deps_debian12//libgcrypt20",
        "@pg_deps_debian12//libgpg-error0",
        "@pg_deps_debian12//libmd0",
        "@pg_deps_debian12//libaudit1",
        "@pg_deps_debian12//libpsl5",
        "@pg_deps_debian12//libacl1",
        "@pg_deps_debian12//libattr1",
        "@pg_deps_debian12//libxml2",
        "@pg_deps_debian12//libxslt1.1",
        "@pg_deps_debian12//libexpat1",
        "@pg_deps_debian12//libedit2",
        "@pg_deps_debian12//libzstd1",
        "@pg_deps_debian12//zlib1g",
        "@pg_deps_debian12//libz3-4",
        "@pg_deps_debian12//liblz4-1",
        "@pg_deps_debian12//libbz2-1.0",
        "@pg_deps_debian12//libbrotli1",
        "@pg_deps_debian12//liblzma5",
        "@pg_deps_debian12//libuuid1",
        "@pg_deps_debian12//libossp-uuid16",
        "@pg_deps_debian12//libpam0g",
        "@pg_deps_debian12//libcurl4",
        "@pg_deps_debian12//libnghttp2-14",
        "@pg_deps_debian12//librtmp1",
        "@pg_deps_debian12//gettext",
        "@pg_deps_debian12//libelogind0",
        "@pg_deps_debian12//libldap-2.5-0",
        "@pg_deps_debian12//libkrb5-3",
        "@pg_deps_debian12//libkrb5support0",
        "@pg_deps_debian12//libk5crypto3",
        "@pg_deps_debian12//libgssapi-krb5-2",
        "@pg_deps_debian12//libtinfo6",
        "@pg_deps_debian12//libbsd0",
        "@pg_deps_debian12//libdb5.3",
        "@pg_deps_debian12//libgdbm6",
        "@pg_deps_debian12//libgdbm-compat4",
        "@pg_deps_debian12//libdbus-1-3",
        "@pg_deps_debian12//libperl5.36",
        "@pg_deps_debian12//libpython3.11",
        "@pg_deps_debian12//tcl",
        "@pg_deps_debian12//libtcl8.6",
        "@pg_deps_debian12//libssh2-1",
    ],
)
