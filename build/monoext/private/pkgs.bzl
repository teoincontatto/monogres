"""
Public API for the shared package hub repo layer.

This module runs in module extension context. It collects package groups from
all contributors (base flavor + extensions), resolves them via `apt_pkgs`,
computes sysroot groups, and delegates hub file generation to the `pkgs_repo`
repository rule in `pkgs/hub.bzl`.
"""

load("//apt:apt_pkgs.bzl", "apt_pkgs")
load("//monoext/private:repo_names.bzl", "bind", "repo_names")
load("//monoext/private/pkgs:collect.bzl", "collect_package_groups")
load("//monoext/private/pkgs:hub.bzl", "pkgs_repo")
load("//monoext/private/pkgs:schema.bzl", _PkgsSchema = "schema")
load("//utils:stable_key.bzl", "stable_key")

def _group_labels(hub_name, group):
    """Builds @pkgs//deb/ labels for a resolved `AptGroup`."""
    labels = []
    for r in group.resolved_names:
        f = bind(hub = hub_name, pkg = r)
        labels.append(f("@{hub}//deb/{pkg}:{pkg}"))
    return labels

def pkgs_group(name, versions, metadata):
    """Construct a pkgs group entry: the metadata contract for `create_pkgs`.

    Each group contributes one "thing" (e.g. the base flavor, or one extension)
    with a set of versions and a metadata dict from which deb deps are
    extracted.

    Args:
        name: Group name (used as key in the resolved `versions_deps`).
        versions: List of version strings for this group.
        metadata: Metadata dict with `deps.{build,run}time.debian.{spec:
            [pkgs]}`.

    Returns:
        A `struct` with `name`, `versions`, and `metadata` fields.
    """
    return struct(
        name = name,
        versions = versions,
        metadata = metadata,
    )

def create_pkgs(ctx, hub_name, groups, lock = None):
    """Creates the shared package repo and hub from a list of groups.

    Encapsulates the full `@{hub_name}` lifecycle: collect package groups from
    all contributors, resolve packages, compute sysroot groups, generate the hub
    repo, and map resolved deps back to each group version.

    NOTE: without a lockfile, this function downloads 3 Debian snapshot sources
    x 2 architectures = 6 Package index files from
    snapshot-cloudflare.debian.org on every cold evaluation.  The `deb_lock`
    attr on the monogres tag provides a lockfile that eliminates these downloads
    entirely.  See `//apt:apt_lock.bzl`.

    Args:
        ctx: The module extension context.
        hub_name: Hub repo name (e.g. `"pg_pkgs"`).
        groups: List of `pkgs_group` structs.
        lock: A lock data struct from `apt_lock.bzl`, or `None` for live
            resolution (with a warning).

    Returns:
        A `PkgsResult` struct.
    """
    if not lock:
        # buildifier: disable=print
        print((
            "WARNING: No apt lockfile for '%s'. Resolving live " +
            "(downloading 6 Debian Package indices).\n" +
            "To generate a lockfile, run:\n" +
            "    bazel run @%s//deb/lock:update\n" +
            "Then add to your monogres tag:\n" +
            '    deb_lock = "//catalog/locks:%s.lock"'
        ) % (hub_name, hub_name, hub_name))

    entries = {
        g.name: {"ext_versions": g.versions, "metadata": g.metadata}
        for g in groups
    }

    pkgs_groups, ext_dep_groups = collect_package_groups(entries)

    deb_repo = repo_names.deb_repo(hub_name)
    apt_result, lock_json = apt_pkgs(ctx, deb_repo, pkgs_groups, lock)

    # build sysroot_groups and group_dep_info in one pass
    sysroot_groups = {}
    group_dep_info = {}

    for group_key, group in apt_result.groups.items():
        labels = _group_labels(hub_name, group)
        sk = stable_key(labels, prefix = "sysroot")
        sysroot_groups[sk] = labels
        f = bind(hub = hub_name, key = sk)
        group_dep_info[group_key] = _PkgsSchema.DepsInfo.new(
            packages = group.packages,
            pkgs_labels = labels,
            sysroot_label = f("@{hub}//deb/sysroots:{key}"),
        )

    pkgs_repo(
        name = hub_name,
        deb_repo = deb_repo,
        deb_packages = apt_result.deb_packages,
        pkg_info = apt_result.pkg_info,
        sysroot_groups = sysroot_groups,
        lock_json = lock_json,
        lock_path = "catalog/locks/%s.lock" % hub_name,
    )

    # map group dep info back to per-group versions_deps
    versions_deps = {}
    for name, entry in entries.items():
        vd = {}
        for version in entry["ext_versions"]:
            vd[version] = _PkgsSchema.VersionDeps.new(
                buildtime = group_dep_info.get(
                    ext_dep_groups.get("buildtime", {}).get((name, version)),
                ),
                runtime = group_dep_info.get(
                    ext_dep_groups.get("runtime", {}).get((name, version)),
                ),
            )
        versions_deps[name] = vd

    return _PkgsSchema.PkgsResult.new(
        package_name_map = apt_result.package_name_map,
        versions_deps = versions_deps,
    )

testing = struct(
    _group_labels = _group_labels,
)
