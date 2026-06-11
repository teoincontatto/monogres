"""
Rule to build the PostgreSQL regression test helper module (`regress.so`).

`regress.so` provides helper C functions used by the PostgreSQL regression test
suite (it is loaded by `test_setup` and required by many regression tests). It
is built from `src/test/regress/regress.c` in the PostgreSQL source.

The companion `pg_build` (`pg_build.bzl`) target named `tar` installs Postgres
with `prefix_distro = /postgres/<version>`, so `pg_config` reports the *runtime*
distro paths, not the bazel-out install. We therefore use the `PG_INSTALL_DIR`
make variable from the sibling `:toolchain` target (which is the real bazel-out
install dir) for the server headers, rather than `pg_config --includedir-server`.
"""

def regress_build(name, pg_src):
    """Compile `regress.so` for the PostgreSQL build in this package.

    Produces `<name>.so` (and `<name>.so.log`). Expects the sibling `:tar`
    (the `pg_build` install tree) and `:toolchain`
    (`pg_template_variable_info`, exposing `PG_INSTALL_DIR`) in the same package.

    Args:
        name: Target name (use `"regress"` → output `regress.so`).
        pg_src: Label of the PostgreSQL source files filegroup (contains
            `src/test/regress/regress.c`).
    """
    native.genrule(
        name = name,
        srcs = [
            pg_src,
            ":tar",
        ],
        outs = [
            "%s.so" % name,
            "%s.so.log" % name,
        ],
        cmd = """
        set -euo pipefail

        EXT="$$PWD"
        OUT="$$EXT/$(location {name}.so)"
        LOG="$$EXT/$(location {name}.so.log)"
        CC="$$EXT/$(CC)"
        # PG_INSTALL_DIR is the real bazel-out install dir (from :toolchain);
        # the server headers live under include/server there.
        INC="$$EXT/$(PG_INSTALL_DIR)/include/server"

        # Locate src/test/regress/regress.c in the Postgres source tree.
        REGRESS_C=
        for f in $(locations {pg_src}); do
            case "$$f" in
                */src/test/regress/regress.c)
                    REGRESS_C="$$EXT/$$f"
                    break
                    ;;
            esac
        done

        if [ -z "$$REGRESS_C" ]; then
            echo "ERROR: src/test/regress/regress.c not found in {pg_src}" | tee "$$LOG" >&2
            exit 1
        fi

        {{
            echo "CC=$$CC"
            echo "INC=$$INC"
            echo "REGRESS_C=$$REGRESS_C"
        }} > "$$LOG"

        # regress.so is dlopen'd by the backend (which provides the PG symbols),
        # so it only needs the server headers and -shared -fPIC; no linking.
        "$$CC" -shared -fPIC -I"$$INC" "$$REGRESS_C" -o "$$OUT" >> "$$LOG" 2>&1
        """.format(
            name = name,
            pg_src = pg_src,
        ),
        toolchains = [
            ":toolchain",
            "@bazel_tools//tools/cpp:current_cc_toolchain",
        ],
        visibility = ["//visibility:public"],
    )
