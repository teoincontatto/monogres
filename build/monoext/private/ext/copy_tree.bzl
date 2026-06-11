"""
Tree-artifact copy of a source directory, dereferencing symlinks.

bazel_lib's `copy_directory` silently drops directory symlinks — e.g. citus's
`src/backend/distributed/safeclib -> ../../../vendor/safestringlib/safeclib` —
which breaks Makefile wildcards over the copied tree (the safestringlib
objects never make it into the citus.so link). This rule materializes the
directory with `cp -rL` so symlinked files and directories become regular
content in the tree artifact.
"""

def _copy_tree_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.out)

    # --preserve=timestamps keeps the relative mtime order of e.g. citus's
    # configure vs configure.ac; a plain copy gives files fresh mtimes in copy
    # order, which can make autoconf-based Makefiles try to re-run autoreconf
    # (not available in the build sandbox).
    ctx.actions.run_shell(
        inputs = ctx.files.src,
        outputs = [out],
        command = 'cp -rL --preserve=timestamps "$1/." "$2/"',
        arguments = [ctx.file.src.path, out.path],
        mnemonic = "CopyTreeDeref",
        progress_message = "Copying directory (dereferencing symlinks) %{label}",
    )

    return [DefaultInfo(files = depset([out]))]

copy_tree = rule(
    implementation = _copy_tree_impl,
    doc = "Copies a source directory into a tree artifact, dereferencing symlinks.",
    attrs = {
        "src": attr.label(
            doc = "Source directory (e.g. a download_archives `:dir` target).",
            allow_single_file = True,
            mandatory = True,
        ),
        "out": attr.string(
            doc = "Name of the output tree artifact.",
            mandatory = True,
        ),
    },
)
