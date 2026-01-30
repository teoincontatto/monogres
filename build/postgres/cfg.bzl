"""
Postgres build configuration.
"""

load("@pg_src//:repo.bzl", "DEFAULT_VERSION", "METADATA", "REPO_NAME", "VERSIONS")
load(":build_options.bzl", "DEFAULT_OPTION_SET", "OPTION_SETS", "build_options")

def _target(name, version, option_set, repo_name, buildtime_dependencies, runtime_dependencies, with_contrib = False):
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
        buildtime_dependencies (list[str]): List of Postgres buildtime dependencies.
        runtime_dependencies (list[str]): List of Postgres runtime dependencies.
        with_contrib (bool): If True, enable contrib extensions and use
            "postgres-contrib" as the base name.

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
          - `buildtime_dependencies (list[str])`: the list of Postgres buildtime dependencies.
          - `runtime_dependencies (list[str])`: the list of Postgres runtime dependencies.
    """
    if version not in VERSIONS:
        fail("Postgres version %s is not available in pg_src" % version)

    options, auto_features = build_options(
        version,
        option_set,
        METADATA.get("build_options", {}),
    )

    # Override contrib setting based on with_contrib flag
    if with_contrib:
        options = dict(options)
        options.pop("contrib", None)  # Remove contrib=false, default is true
        target_name = name + "-contrib"
        extra_version_suffix = "-contrib"
    else:
        target_name = name
        extra_version_suffix = ""

    # Update extra_version to reflect contrib status
    if "extra_version" in options:
        options["extra_version"] = options["extra_version"] + extra_version_suffix

    pg_version = None

    if option_set == "full" and with_contrib:
        # We want the "full" option_set with contrib to be the default Postgres target
        pg_version = struct(
            name = "~".join((target_name, version)),
            version = version,
        )

    return struct(
        name = "~".join((target_name, version, option_set)),
        version = version,
        option_set = option_set,
        build_options = options,
        auto_features = auto_features,
        pg_src = "@%s//%s" % (repo_name, version),
        pg_version = pg_version,
        buildtime_dependencies = buildtime_dependencies,
        runtime_dependencies = runtime_dependencies,
    )

def _new(name, versions, option_sets, repo_name, buildtime_dependencies, runtime_dependencies):
    """
    Creates a config `struct` containing build targets for multiple Postgres versions.

    Generates two sets of targets:
      - `postgres~<version>~<option_set>`: without contrib extensions
      - `postgres-contrib~<version>~<option_set>`: with contrib extensions

    Args:
        name (str): A base name for the group of targets (e.g. "postgres").
        versions (list[str]): List of Postgres versions.
        option_sets (list[str]): The names of the Postgres option sets to
            add to the targets. An option set is a predefined combination of
            compile-time options.
        repo_name (str): The name of the external Bazel repository with the
            Postgres source code.
        buildtime_dependencies (list[str]): List of Postgres buildtime dependencies.
        runtime_dependencies (list[str]): List of Postgres runtime dependencies.

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
            # Generate targets without contrib (postgres~<version>~<option_set>)
            target = _target(name, version, option_set, repo_name, buildtime_dependencies, runtime_dependencies, with_contrib = False)
            targets.append(target)

            # Generate targets with contrib (postgres-contrib~<version>~<option_set>)
            target_contrib = _target(name, version, option_set, repo_name, buildtime_dependencies, runtime_dependencies, with_contrib = True)

            if (
                version == DEFAULT_VERSION and
                option_set == DEFAULT_OPTION_SET
            ):
                default_target = target_contrib

            targets.append(target_contrib)

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
    buildtime_dependencies = [
        "@pg_deps_debian13//gettext",
        "@pg_deps_debian13//libavahi-compat-libdnssd-dev",
        "@pg_deps_debian13//libcurl4-openssl-dev",
        "@pg_deps_debian13//libedit-dev",
        "@pg_deps_debian13//libeditreadline-dev",
        "@pg_deps_debian13//libicu-dev",
        "@pg_deps_debian13//libkrb5-dev",
        "@pg_deps_debian13//libldap-dev",
        "@pg_deps_debian13//liblz4-dev",
        "@pg_deps_debian13//libnuma-dev",
        "@pg_deps_debian13//libossp-uuid-dev",
        "@pg_deps_debian13//libpam0g-dev",
        "@pg_deps_debian13//libperl-dev",
        "@pg_deps_debian13//libpython3-dev",
        "@pg_deps_debian13//libselinux1-dev",
        "@pg_deps_debian13//libssl-dev",
        "@pg_deps_debian13//libsystemd-dev",
        "@pg_deps_debian13//liburing-dev",
        "@pg_deps_debian13//libxml2-dev",
        "@pg_deps_debian13//libxslt1-dev",
        "@pg_deps_debian13//libzstd-dev",
        "@pg_deps_debian13//llvm-19-dev",
        "@pg_deps_debian13//tcl-dev",
        "@pg_deps_debian13//uuid-dev",
        "@pg_deps_debian13//zlib1g-dev",
    ],
    runtime_dependencies = [
        "@pg_deps_debian13//gettext",
        "@pg_deps_debian13//libavahi-compat-libdnssd1",
        "@pg_deps_debian13//libcurl4t64",
        "@pg_deps_debian13//libedit2",
        "@pg_deps_debian13//libgssapi-krb5-2",
        "@pg_deps_debian13//libicu76",
        "@pg_deps_debian13//libkrb5-3",
        "@pg_deps_debian13//libldap2",
        "@pg_deps_debian13//liblz4-1",
        "@pg_deps_debian13//libnuma1",
        "@pg_deps_debian13//libossp-uuid16",
        "@pg_deps_debian13//libpam0g",
        "@pg_deps_debian13//libperl5.40",
        "@pg_deps_debian13//libpython3.13",
        "@pg_deps_debian13//libselinux1",
        "@pg_deps_debian13//libssl3t64",
        "@pg_deps_debian13//libsystemd0",
        "@pg_deps_debian13//liburing2",
        "@pg_deps_debian13//libuuid1",
        "@pg_deps_debian13//libxml2",
        "@pg_deps_debian13//libxslt1.1",
        "@pg_deps_debian13//libzstd1",
        "@pg_deps_debian13//llvm-19-runtime",
        "@pg_deps_debian13//ncurses-term",
        "@pg_deps_debian13//tcl",
        "@pg_deps_debian13//zlib1g",
    ],
)
