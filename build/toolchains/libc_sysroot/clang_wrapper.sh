#!/bin/sh
# Self-relative wrapper for Postgres JIT bitcode compile + PGXS extensions.
# Bakes `--sysroot=<sysroot>` into every clang invocation so PGXS / JIT bitcode
# compilation runs against the hermetic Debian sysroot, not host headers.
# `readlink -f $0` follows symlink chains to the canonical file location so
# the path arithmetic stays correct even when invoked via the apt-sysroot
# symlink that pg_build planted at `$SYSROOT_DIR/usr/lib/llvm-14/bin/clang`.
#
# Wrapper lives at:
#   <external>/<libc_sysroot>/<distro>/<version>/<arch>/usr/lib/llvm-14/bin/clang
# Five dirnames from $real reach the per-arch sysroot root (passed to clang as
# --sysroot=); four more reach bazel's external/ dir.
#
# The sysroot's arch (`amd64` / `arm64`, the basename of $sysroot) is the
# TARGET arch: the arch of the headers/libs in the tree, i.e. what this
# invocation compiles FOR. The arch the wrapper is RUNNING on (the EXEC arch)
# is the kernel's `uname -m`. The two split independently:
#
# - The exec'd clang binary must be an EXEC-arch ELF, so the
#   `cc_toolchain_layout` adapter repo (`@llvm_toolchain_<arch>`, whose `bin/`
#   carries the Debian-sourced clang hardlinked from the matching
#   `@llvm_sysroot` tree) is selected by the EXEC arch. Debian's clang is a
#   native cross-compiler (all LLVM targets enabled), so one host binary
#   serves every target arch.
# - When the two arches differ (cross-compile), clang needs an explicit
#   `--target=` for the sysroot's arch; bare clang defaults to the arch it
#   runs on and would emit EXEC-arch code against TARGET-arch headers/libs.
#   When they match (native), no flag is passed and clang's default triple
#   applies, keeping native invocations byte-identical to a plain
#   `clang --sysroot=...` call.
real=$(readlink -f "${0}")
sysroot=$(dirname "$(dirname "$(dirname "$(dirname "$(dirname "${real}")")")")")
external=$(dirname "$(dirname "$(dirname "$(dirname "${sysroot}")")")")
target_arch=$(basename "${sysroot}")

exec_machine=$(uname -m)
case "${exec_machine}" in
    x86_64) exec_arch=amd64 ;;
    aarch64) exec_arch=arm64 ;;
    *)
        echo "clang_wrapper: unsupported exec arch '${exec_machine}'" >&2
        exit 1
        ;;
esac

target_flag=
if [ "${target_arch}" != "${exec_arch}" ]; then
    case "${target_arch}" in
        amd64) target_flag=--target=x86_64-linux-gnu ;;
        arm64) target_flag=--target=aarch64-linux-gnu ;;
        *)
            echo "clang_wrapper: unsupported sysroot arch '${target_arch}'" >&2
            exit 1
            ;;
    esac
fi

# No linker selection here: the wrapper serves compile-only invocations (JIT
# bitcode `-c`) as well as links, and a link-only flag would draw "argument
# unused during compilation" warnings that confuse autoconf probes which
# parse compiler warnings. Cross link invocations carry `-fuse-ld=lld` via
# the LDFLAGS their build system passes (`pg_build_make` bakes it into
# `Makefile.global` under cross-compile).
#
# The clang to exec lives in the `cc_toolchain_layout` adapter repo for the EXEC
# arch, whose directory under `external/` is its CANONICAL repo name. The only
# part of that name we choose is the apparent name it ends with, the one this
# repo is declared under; everything before it Bazel derives, and derives
# differently between versions (`~` separators before Bazel 8, `+` from 8 on)
# and by position, since a repo declared with `use_repo_rule` is numbered by
# where its declaring call sits among all of them in `MODULE.bazel`. So match on
# the apparent name alone and let Bazel spell the rest however it likes.
#
# That leaves the match pinned by three things: the arch-suffixed apparent name,
# which no other repo in the graph ends with (`toolchains_llvm`'s own hub ends
# at `llvm_toolchain`, unsuffixed); the `bin/clang` below it; and `-x`. Globbing
# one directory level is cheap, and in a sandboxed action there is barely
# anything to walk, since only declared inputs are staged.
#
# The path cannot be passed in instead: `pg_build` redirects the sysroot's
# `usr/lib/llvm-<major>/bin/clang` here so that meson's `find_program` and the
# `$(CLANG)` in Postgres's installed `Makefile.global` resolve to it, and both
# invoke it by that one absolute path with no argument of ours. Hence `$0`, as
# the adapter's own shim likewise takes its exec root.
#
# An unmatched glob stays literal in POSIX sh, so the `-x` test fails and the
# empty `clang` reports it rather than exec'ing a pattern.
clang=
for candidate in "${external}"/*"llvm_toolchain_${exec_arch}"/bin/clang; do
    if [ -x "${candidate}" ]; then
        clang="${candidate}"
        break
    fi
done

if [ -z "${clang}" ]; then
    echo "clang_wrapper: no llvm_toolchain_${exec_arch}/bin/clang under" \
        "${external}" >&2
    exit 1
fi

# aarch64 links get compiler-rt's builtins archive as a last input. On aarch64,
# clang lowers some 128-bit arithmetic to `__muloti4`, which libgcc does not
# provide (GCC never emits it). PostgreSQL's configure probe for `__int128`
# is such code, so it failed to link and every arm64 build went without
# 128-bit integers. Plain PostgreSQL falls back to slower code; Babelfish's
# `pg_bswap.h` uses `uint128` unconditionally and fails to compile.
#
# The archive is an extra input, not `--rtlib=compiler-rt`: libgcc stays the
# runtime library, and the linker takes from the archive only what is still
# undefined when it reaches it. It comes from the TARGET arch's @llvm_sysroot
# (libclang-rt-<major>-dev), found under `external/` the same way as the clang
# above, so the path is never baked into a `Makefile.global` that outlives this
# action. Only link invocations get it: on a compile-only one it would draw
# "argument unused during compilation" warnings (see above).
rt_builtins=
if [ "${target_arch}" = arm64 ]; then
    links=1
    has_input=
    for arg in "$@"; do
        case "${arg}" in
            -c | -S | -E | -M | -MM | -fsyntax-only | -emit-llvm | -\#\#\# | \
                --version | -v | -dumpversion | -dumpmachine | -print-*)
                links=
                break
                ;;
            -*) ;;
            *) has_input=1 ;;
        esac
    done
    if [ -n "${links}" ] && [ -n "${has_input}" ]; then
        distro_version=$(dirname "${sysroot}")
        version=$(basename "${distro_version}")
        distro=$(basename "$(dirname "${distro_version}")")
        for candidate in "${external}"/*llvm_sysroot/"${distro}/${version}/${target_arch}"/usr/lib/llvm-*/lib/clang/*/lib/linux/libclang_rt.builtins-aarch64.a; do
            if [ -f "${candidate}" ]; then
                rt_builtins="${candidate}"
                break
            fi
        done
    fi
fi

# ${target_flag:+...} and ${rt_builtins:+...} expand to nothing when unset, so
# no empty argument is passed.
exec "${clang}" ${target_flag:+"${target_flag}"} --sysroot="${sysroot}" "$@" \
    ${rt_builtins:+"${rt_builtins}"}
