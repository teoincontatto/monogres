"""
Rule to build the PostgreSQL regression test helper module (regress.so).

This module provides helper functions used by the PostgreSQL regression test suite.
It's built from src/test/regress/regress.c in the PostgreSQL source.
"""

load("//postgres:build_options.bzl", "DEFAULT_PREFIX_DISTRO")

def regress_build(name, pg_src, pg_version, prefix_distro = None):
    """
    Builds the regress.so test helper module for a specific PostgreSQL version.

    Args:
        name (str): The name of the Bazel target to generate.
        pg_src (str): The label of the PostgreSQL source repository.
        pg_version (struct): struct containing metadata about the PostgreSQL build.
        prefix_distro (str): The base prefix path for the distro install.
    """
    if prefix_distro == None:
        prefix_distro = DEFAULT_PREFIX_DISTRO

    prefix_distro_rel = prefix_distro.lstrip("/")
    tar_file = "%s.tar" % name
    log_file = "%s.log" % name

    native.genrule(
        name = name,
        srcs = [
            "//postgres:%s" % pg_version.name,
            pg_src,
        ],
        outs = [tar_file, log_file],
        cmd = """
        set -euo pipefail

        EXT_BUILD_ROOT="$$PWD"
        TAR_FILE="$$EXT_BUILD_ROOT/{tar_file}"
        LOG_FILE="$$EXT_BUILD_ROOT/{log_file}"
        PG_SRC_FILES=({pg_src_files})
        PG_CONFIG="$$EXT_BUILD_ROOT/$(PG_CONFIG)"
        CC="$$EXT_BUILD_ROOT/$(CC)"

        # Find regress.c in the source files
        REGRESS_C=""
        for f in "$${{PG_SRC_FILES[@]}}"; do
            if [[ "$$f" == */src/test/regress/regress.c ]]; then
                REGRESS_C="$$EXT_BUILD_ROOT/$$f"
                break
            fi
        done

        if [[ -z "$$REGRESS_C" ]]; then
            echo "ERROR: Could not find src/test/regress/regress.c in source files" >> "$$LOG_FILE"
            exit 1
        fi

        # Get PostgreSQL build paths
        PG_INCLUDEDIR_SERVER="$$("$$PG_CONFIG" --includedir-server)"
        PG_PKGLIBDIR="$$("$$PG_CONFIG" --pkglibdir)"
        PG_CFLAGS="$$("$$PG_CONFIG" --cflags)"

        echo "Building regress.so" >> "$$LOG_FILE"
        echo "  PG_CONFIG: $$PG_CONFIG" >> "$$LOG_FILE"
        echo "  PG_INCLUDEDIR_SERVER: $$PG_INCLUDEDIR_SERVER" >> "$$LOG_FILE"
        echo "  PG_PKGLIBDIR: $$PG_PKGLIBDIR" >> "$$LOG_FILE"
        echo "  REGRESS_C: $$REGRESS_C" >> "$$LOG_FILE"

        # Create output directory
        INSTALLDIR="$$EXT_BUILD_ROOT/install/{prefix_distro_rel}/{pg_version}/lib"
        mkdir -p "$$INSTALLDIR"

        # Compile regress.c to regress.so
        # Using -shared and -fPIC to create a shared library
        "$$CC" \
            -shared \
            -fPIC \
            -o "$$INSTALLDIR/regress.so" \
            -I"$$PG_INCLUDEDIR_SERVER" \
            $$PG_CFLAGS \
            "$$REGRESS_C" \
            >> "$$LOG_FILE" 2>&1

        echo "Successfully built regress.so" >> "$$LOG_FILE"

        # Create tarball
        tar \
            --format=posix \
            --numeric-owner \
            --owner=0 \
            --group=0 \
            -cf "$$TAR_FILE" \
            -C "$$EXT_BUILD_ROOT/install" \
            .

        echo "Created tarball: $$TAR_FILE" >> "$$LOG_FILE"
        """.format(
            tar_file = "$(locations %s)" % tar_file,
            log_file = "$(locations %s)" % log_file,
            pg_src_files = "$(locations %s)" % pg_src,
            prefix_distro_rel = prefix_distro_rel,
            pg_version = pg_version.version,
        ),
        toolchains = [
            "@bazel_tools//tools/cpp:current_cc_toolchain",
            "//postgres:%s--toolchain" % pg_version.name,
        ],
        visibility = ["//visibility:public"],
    )

def regress_build_all(name, cfg):
    """
    Builds regress.so for all configured PostgreSQL versions.

    Args:
        name (str): Base name for the targets (unused, for consistency).
        cfg (struct): PostgreSQL config struct from cfg.bzl.
    """
    for target in cfg.targets:
        # Only build for contrib+full builds (which have pg_version set)
        if target.pg_version:
            regress_build(
                name = "regress~%s" % target.pg_version.version,
                pg_src = target.pg_src,
                pg_version = target.pg_version,
            )
