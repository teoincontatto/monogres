"""
Rules to build Postgres PGXS extensions from source.

Internal to monoext; invoked from generated `@{name}_ext//...` BUILD files.
"""

load("//monoext/private/base/build_options:pg.bzl", "DEFAULT_PREFIX_DISTRO")

def pgxs_build(name, pgxs_src, deps_buildtime, base_version, base_hub, prefix_distro = DEFAULT_PREFIX_DISTRO, debug = False):
    """Builds a PGXS extension with the [PGXS build system].

    [PGXS build system]: https://www.postgresql.org/docs/current/extend-pgxs.html

    Args:
        name (str): The name of the Bazel target to generate.
        pgxs_src (str): The repo with the extension source code.
        deps_buildtime (list[str]): List of dependencies needed to build the
            extension.
        base_version (dict): `dict` with `name` and `version` keys to select the
            Postgres build that will be used when building the extension.
        base_hub (str): The base hub repo name (e.g. `"@pg"`). PG build targets
            and toolchains are resolved from this repo.
        prefix_distro (str): The base prefix path for the distro install
            (defaults to `DEFAULT_PREFIX_DISTRO`).
        debug (bool): If `True`, prints a debug message for each command
            executed.
    """

    # remove leading slash for use in relative paths within the tar
    prefix_distro_rel = prefix_distro.lstrip("/")

    tar_file, log_file = ["%s%s" % (name, file) for file in (".tar", ".log")]

    native.genrule(
        name = name,
        srcs = [
            "%s//%s" % (base_hub, base_version["version"]),
            pgxs_src,
        ] + deps_buildtime,
        outs = [tar_file, log_file],
        cmd = """
        tar_() {{
            local tar_file="$$1"; shift
            local args=("$$@")

            local tar_cmd="{tar_cmd}"
            local tar_args=(
                {tar_args}
            )

            LC_ALL=C $$tar_cmd \
                -cf "$$tar_file" \
                "$${{tar_args[@]}}" \
                "$${{args[@]}}"
        }}

        setup_deps_buildtime() {{
            local deps_buildtime_path="$$1"; shift
            local deps_buildtime=("$$@");

            echo "# $$(date) - setup_deps_buildtime"

            [[ $${{#deps_buildtime[@]}} -eq 0 ]] && return

            mkdir -p "$$deps_buildtime_path"

            echo
            echo "Extracting deps_buildtime in: $$deps_buildtime_path"

            for dep in "$${{deps_buildtime[@]}}"; do
                echo "  - $$dep"
                tar -xf "$$dep" -C "$$deps_buildtime_path"
            done
            echo
        }}

        compile_extension() {{
            local cc="$$1"; shift
            local pgxs_src="$$1"; shift
            local deps_buildtime_path="$$1"; shift
            local installdir="$$1"; shift

            # NOTE:
            # Unlike Meson, configure-make builds may write to the source tree.
            # While off-tree (VPATH) builds are theoretically supported, I haven't
            # found a reliable way to use it and still get all extension files
            # installed correctly into the pgxs_installdir (lib, share, etc).
            # To avoid this, we copy the pgxs_src tree and build from the copy.

            local pgxs_src_copy="$$EXT_BUILD_ROOT/pgxs_src_copy"

            # NOTE: -L because we need to copy the actual dir and not the symlink
            # NOTE: chmod because pgxs_src is a tree artifact (read-only in Bazel)
            cp -raL "$$pgxs_src" "$$pgxs_src_copy"
            chmod -R u+w "$$pgxs_src_copy"

            local arch
            arch="$$(uname -m)"

            # NOTE:
            # We use -idirafter for include paths so they are searched AFTER
            # system directories. This prevents sysroot headers from conflicting
            # with system libc headers while still making them available.
            local pg_cflags=(
                "-idirafter $$deps_buildtime_path/usr/include"
                "-idirafter $$deps_buildtime_path/usr/include/$${{arch}}-linux-gnu"
            )
            local pg_ldflags=(
                "-L$$deps_buildtime_path/usr/lib/$${{arch}}-linux-gnu"
            )

            # NOTE:
            # Set up environment variables for pkg-config and runtime library loading.
            # This mirrors the setup in postgres/pg_build.bzl for consistency.
            export PKG_CONFIG_SYSROOT_DIR="$$deps_buildtime_path"
            export PKG_CONFIG_PATH="$$deps_buildtime_path/usr/lib/$${{arch}}-linux-gnu/pkgconfig:$$deps_buildtime_path/usr/share/pkgconfig"
            export LIBRARY_PATH="$$deps_buildtime_path/usr/lib/$${{arch}}-linux-gnu"
            export LD_LIBRARY_PATH="$$deps_buildtime_path/usr/lib/$${{arch}}-linux-gnu:$$deps_buildtime_path/usr/lib"

            # NOTE:
            # PGXS flag variables are exported as environment variables (not
            # passed on the make command line) so that extensions can freely
            # override or append to them in their Makefiles. In GNU Make,
            # command-line variables (priority 2) crush Makefile assignments
            # (priority 3), while environment variables (priority 4) act as
            # defaults. This lets the standard PGXS mechanism in pgxs.mk
            # (e.g. override CPPFLAGS := PG_CPPFLAGS + CPPFLAGS) merge
            # extension-defined flags with our sysroot flags correctly.
            export PG_CFLAGS="$${{pg_cflags[*]}}"
            export PG_CPPFLAGS="$${{pg_cflags[*]}}"
            export CPPFLAGS="$${{pg_cflags[*]}}"
            export PG_LDFLAGS="$${{pg_ldflags[*]}}"

            echo "# $$(date) - compile_extension"
            echo
            echo "pgxs_src: $$pgxs_src"
            echo "pgxs_src_copy: $$pgxs_src_copy"
            echo "PKG_CONFIG_SYSROOT_DIR: $$PKG_CONFIG_SYSROOT_DIR"
            echo "PKG_CONFIG_PATH: $$PKG_CONFIG_PATH"

            if [ -f "$$pgxs_src_copy/configure" ]
            then
                echo
                echo "configure"
                echo
                env -C "$$pgxs_src_copy" \
                    CC="$$cc" \
                    PG_CONFIG="$$EXT_BUILD_ROOT/$(PG_CONFIG)" \
                    CFLAGS="$${{pg_cflags[*]}}" \
                    CPPFLAGS="$${{pg_cflags[*]}}" \
                    LDFLAGS="$${{pg_ldflags[*]}}" \
                    PG_CONFIG="$$EXT_BUILD_ROOT/$(PG_CONFIG)" \
                    "$$pgxs_src_copy/configure" || return $$?
            fi

            echo
            echo "make"
            echo
            "$$EXT_BUILD_ROOT/$(MAKE)" \
                -C "$$pgxs_src_copy" \
                CC="$$cc" \
                CXX="$$cc" \
                CPP="$$cc -E" \
                PG_CONFIG="$$EXT_BUILD_ROOT/$(PG_CONFIG)" \
                USE_PGXS=1 || return $$?

            echo
            echo "make install"
            echo
            "$$EXT_BUILD_ROOT/$(MAKE)" \
                -C "$$pgxs_src_copy" \
                CC="$$cc" \
                CXX="$$cc" \
                CPP="$$cc -E" \
                PG_CONFIG="$$EXT_BUILD_ROOT/$(PG_CONFIG)" \
                USE_PGXS=1 \
                DESTDIR="$$installdir" \
                install || return $$?

            echo
            echo "Extension compiled OK"
        }}

        make_pgxs_installdir() {{
            local installdir="$$1"; shift

            # HACK:
            # The `install` target in the [`PGXS`] Makefile ([`pgxs.mk`])
            # installs the extension at `DESTDIR/datadir/extension/`.
            #
            # `datadir` appears to be set to the absolute path from where
            # [`pg_config`] runs. This is problematic because of two reasons.
            #
            # First, the `pg_config` binary comes from a Postgres toolchain.
            # Like all external dependencies, it's read-only inside the
            # sandbox. We can work around this by setting [`DESTDIR`] to point
            # the install root to a writable directory inside the sandbox.
            #
            # Second, and where the hack is really needed: the rule that
            # creates the Postgres toolchain (template_variable_info) can't run
            # binaries. It only uses the paths of the Postgres binaries which
            # are relative to the sandbox where Postgres was compiled. Thus,
            # the `PG_INSTALL_DIR` template variable in the toolchain is not
            # set to the absolute path that we need.
            #
            # The only workaround is to run `pg_config` here and extract the
            # install path ourselves, just like the `PGXS` Makefile seems to be
            # doing.
            #
            # [`PGXS`]: https://www.postgresql.org/docs/16/extend-pgxs.html
            # [`pgxs.mk`]: https://github.com/postgres/postgres/blob/REL_16_0/src/makefiles/pgxs.mk#L237-L240
            # [`pg_config`]: https://www.postgresql.org/docs/16/app-pgconfig.html
            # [`DESTDIR`]: https://www.gnu.org/software/make/manual/html_node/DESTDIR.html

            local abs_pg_config_bindir
            abs_pg_config_bindir="$$($(PG_CONFIG) --bindir)"

            local abs_pg_install_dir
            abs_pg_install_dir="$$(dirname "$$abs_pg_config_bindir")"

            {{
                echo
                echo "installdir (DESTDIR): $$installdir"
                echo "abs_pg_install_dir: $$abs_pg_install_dir"
                echo "PG_INSTALL_DIR: $(PG_INSTALL_DIR)"
                echo
            }} >> "$$LOG_FILE"

            echo "$$installdir/$$abs_pg_install_dir"
        }}

        errors() {{
            {{
                echo
                echo
                echo "# $$(date)"
                echo
                echo

                env
            }} >> "$$LOG_FILE"

            # Copy the log out of the sandbox to a persistent location under
            # the bazel cache so the reported path stays valid after sandbox
            # teardown. The sandbox execroot has the shape
            #   /postgres/.cache/bazel/_bazel_<user>/<id>/sandbox/<strategy>/<N>/execroot/<repo>
            # Strip everything from "/sandbox/" on to recover the cache root
            # (which is persistent). Falls back to the in-sandbox log path
            # if the copy can't be made.
            local cache_root real_log_file dest_dir dest
            cache_root="$$(printf %s "$$PWD" | sed -E 's|/sandbox/.*||')"
            real_log_file="$$LOG_FILE"
            if [ -n "$$cache_root" ] && [ "$$cache_root" != "$$PWD" ]; then
                dest_dir="$$cache_root/monogres-action-logs"
                dest="$$dest_dir/$$(basename "$$LOG_FILE")"
                mkdir -p "$$dest_dir" 2>/dev/null || :
                if cp -f "$$LOG_FILE" "$$dest" 2>/dev/null; then
                    real_log_file="$$dest"
                fi
            fi

            {{
                echo
                echo
                echo "========================================================"
                echo "  >> LOG: $$real_log_file"
                echo "========================================================"
                echo
                echo
            }} | tee /dev/stderr >> "$$LOG_FILE"

            exit 1
        }}

        trap errors ERR

        DEBUG="{debug}"
        [ "$$DEBUG" != True ] || set -x

        # =================================================================== #

        export EXT_BUILD_ROOT="$$PWD"

        TAR_FILE="$$EXT_BUILD_ROOT/{tar_file}"
        LOG_FILE="$$EXT_BUILD_ROOT/{log_file}"
        PGXS_SRC="$$EXT_BUILD_ROOT/{pgxs_src}"
        DEPS_BUILDTIME=({deps_buildtime})

        DEPS_BUILDTIME_PATH="$$EXT_BUILD_ROOT/deps_buildtime"
        INSTALLDIR="$$EXT_BUILD_ROOT/$$(basename "$$TAR_FILE" .tar)"

        PGXS_INSTALLDIR="$$(make_pgxs_installdir "$$INSTALLDIR")"
        RELOCATED_PGXS_INSTALLDIR="$$EXT_BUILD_ROOT/relocated"

        CC="$$EXT_BUILD_ROOT/$(CC)"

        export LOG_FILE

        {{
            setup_deps_buildtime "$$DEPS_BUILDTIME_PATH" "$${{DEPS_BUILDTIME[@]}}"
            compile_extension "$$CC" "$$PGXS_SRC" "$$DEPS_BUILDTIME_PATH" "$$INSTALLDIR"
            mkdir -p "$$RELOCATED_PGXS_INSTALLDIR/{prefix_distro_rel}/{base_version}"
            mv -t "$$RELOCATED_PGXS_INSTALLDIR/{prefix_distro_rel}/{base_version}/." "$$PGXS_INSTALLDIR"/*
            tar_ "$$TAR_FILE" --directory "$$RELOCATED_PGXS_INSTALLDIR" .
        }} >> "$$LOG_FILE" 2>&1
        """.format(
            tar_cmd = "$(BSDTAR_BIN)",
            # NOTE: https://reproducible-builds.org/docs/archives/
            # We are using bsd tar which has less flags available. Consider
            # writing an mtree and/or find a way to use tar.bzl tar rule like we
            # did in extensions/contrib
            tar_args = "\n".join([
                "--format=posix",
                "--numeric-owner",
                "--owner=0",
                "--group=0",
            ]),
            tar_file = "$(locations %s)" % tar_file,
            log_file = "$(locations %s)" % log_file,
            prefix_distro_rel = prefix_distro_rel,
            base_version = base_version["version"],
            pgxs_src = "$(locations %s)" % pgxs_src,
            deps_buildtime = " ".join([
                "$(locations %s)" % dep_buildtime
                for dep_buildtime in deps_buildtime
            ]),
            debug = "%s" % debug,
        ),
        target_compatible_with = select({
            # bsdtar.exe: -s is not supported by this version of bsdtar
            "@platforms//os:windows": ["@platforms//:incompatible"],
            "//conditions:default": [],
        }),
        toolchains = [
            "@bazel_tools//tools/cpp:current_cc_toolchain",
            "@bsd_tar_toolchains//:resolved_toolchain",
            "@rules_foreign_cc//toolchains:current_make_toolchain",
            "%s//%s:toolchain" % (base_hub, base_version["version"]),
        ],
        visibility = ["//visibility:public"],
    )
