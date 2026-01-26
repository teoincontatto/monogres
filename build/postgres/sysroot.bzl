"""
Rules to create a unified sysroot from dependency tarballs.

This module provides the `pg_sysroot` macro which creates a genrule that
extracts all dependency tarballs into a unified sysroot tarball. This sysroot
can then be used by the meson build via environment variables.
"""

def pg_sysroot(name, dependencies):
    """
    Creates a unified sysroot tarball from multiple dependency tarballs.

    This genrule extracts all dependency tarballs (from rules_distroless packages)
    into a temporary directory and then creates a single merged tarball. The
    merged tarball contains the standard Linux directory structure (usr/lib,
    usr/include, etc.) with all dependencies combined.

    Args:
        name (str): The name of the Bazel target to generate.
        dependencies (list[str]): List of dependency tarballs to merge. These
            are typically labels pointing to rules_distroless package tarballs.
    """
    native.genrule(
        name = name,
        srcs = dependencies,
        outs = [name + ".tar"],
        cmd = """
            SYSROOT="$$(mktemp -d)"
            for dep in $(SRCS); do
                tar -xf "$$dep" -C "$$SYSROOT"
            done
            tar -cf "$@" -C "$$SYSROOT" .
            rm -rf "$$SYSROOT"
        """,
        visibility = ["//visibility:public"],
    )
