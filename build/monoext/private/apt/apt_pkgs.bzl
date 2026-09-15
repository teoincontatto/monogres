"""
Shared dependency package pool for `monoext`'s apt resolution.

Creates a single set of `deb_import` repos and one `deb_translate_lock` repo for
all package groups, eliminating package duplication across groups.

Wraps `@rules_distroless`'s private apt API intentionally:

  - the public `apt` module extension cannot be nested inside another module
    extension; using it would force callers to manually declare an additional
    root-level `use_extension(...)` / `use_repo(...)` flow.
  - the legacy `apt.install(...)` macro is WORKSPACE-oriented and incomplete
    by itself; its documented usage needs a second
    `load("@<repo>//:packages.bzl", "<repo>_packages")` followed by
    `<repo>_packages()` to create the per-package repos, which is not a clean
    fit for a module extension that needs one self-contained helper.

The resolver itself lives in the generic
`@sysroots//apt/private:apt_resolve.bzl`; this module is the `monoext`-specific
orchestration on top of that.
"""

# buildifier: disable=bzl-visibility
load("@rules_distroless//apt/private:deb_import.bzl", "deb_import")

# buildifier: disable=bzl-visibility
load(
    "@rules_distroless//apt/private:deb_translate_lock.bzl",
    "deb_translate_lock",
)

# buildifier: disable=bzl-visibility
load("@rules_distroless//apt/private:lockfile.bzl", "lockfile")

# buildifier: disable=bzl-visibility
load("@sysroots//apt/private:apt_resolve.bzl", "resolve")
load("//monoext/private/apt:apt_lock.bzl", _AptLock = "apt_lock")
load("//monoext/private/apt:schema.bzl", _AptSchema = "schema")
load("//monoext/private/apt:snapshot.bzl", "SNAPSHOT")
load("//platforms:targets.bzl", "ARCHS")

# Packages no image should get by way of a dependency edge, because a PostgreSQL
# install is already the provider of that soname and a second copy does not sit
# quietly beside the first.
#
# `deb_translate_lock` renders one `filegroup` per package whose `srcs` are its
# whole transitive closure, and that filegroup is what an image layer depends
# on. So an extension layer that reaches libpq5 -- nothing asks for it, GDAL
# does, which is how postgis came by it -- lands Debian's
# `usr/lib/<arch>-linux-gnu/libpq.so.5` on top of the symlink the base image
# points at `/postgres/<version>/lib/libpq.so.5`, and every client binary in the
# composed image loads Debian's instead. The failure is not a missing symbol but
# a quieter one: `pg_isready` prints the socket directory *its own* build
# compiled in and connects to the one Debian's libpq did, so a healthy server
# answers "no response".
#
# Only the edges are cut, and only in the lock handed to `deb_translate_lock`.
# A package that names one of these directly still resolves, and
# `apt_result.packages` keeps them, so the compile sysroots `apt_group` builds
# are untouched -- an out-of-tree extension still links against libpq there,
# where there is no PostgreSQL install to provide it.
_PROVIDED_BY_THE_BASE_IMAGE = ["libpq5"]

def _without_provided_edges(packages):
    """Drop dependency edges onto `_PROVIDED_BY_THE_BASE_IMAGE`.

    Args:
        packages: Lockfile-shaped package dicts.

    Returns:
        The same packages, each with those edges removed from `dependencies`.
    """
    provided = {name: True for name in _PROVIDED_BY_THE_BASE_IMAGE}

    pruned = []
    for pkg in packages:
        deps = pkg.get("dependencies", [])
        kept = [dep for dep in deps if dep["name"] not in provided]
        if len(kept) == len(deps):
            pruned.append(pkg)
        else:
            pruned.append(dict(pkg, dependencies = kept))

    return pruned

def apt_pkgs(ctx, name, package_groups, lock = None):
    """Creates a shared repo of Debian packages.

    Resolves ALL unique packages from all groups in a single pass and creates:
      - one `deb_import` per unique `(package, version, arch)`
      - one `deb_translate_lock` repo that organizes them

    When `lock` is provided, skips live resolution entirely and uses the cached
    lockfile data.

    Args:
        ctx: The module extension context.
        name: Internal lock repo name (e.g., `"pkgs_deb"`).
        package_groups: Dict of `{group_key: [packages]}`.
        lock: An `AptLock` struct, or `None` for live resolution.

    Returns:
        A tuple of `(AptResult, lock_json)` where `lock_json` is the JSON
        serialized `AptLock`.
    """
    requested = sorted(set([
        pkg
        for pkgs in package_groups.values()
        for pkg in pkgs
    ]))

    # The roots this lock was generated for have to be the roots being asked for
    # now, or its closures answer a different question. `monoext.bzl` validates
    # the lock too, but against a superset -- every spec of the active release,
    # not the specs these versions actually select -- so the exact comparison
    # belongs here, where `package_groups` is already filtered.
    if lock:
        mismatch = _AptLock.requested_mismatch(lock, requested)
        if mismatch:
            # buildifier: disable=print
            print((
                "WARNING: apt lockfile for '%s' is stale (%s). " +
                "Falling back to live resolution.\n" +
                "Regenerate with: bazel run @%s//deb/lock:update"
            ) % (name, mismatch, name))
            lock = None

    if lock:
        packages = lock.packages
        package_name_map = lock.package_name_map
        lock_content = json.encode({
            "packages": _without_provided_edges(lock.packages),
            "version": lock.version,
        })
    else:
        # live resolution
        lockf, package_name_map = resolve(
            ctx,
            name,
            list(ARCHS),
            requested,
            SNAPSHOT,
        )

        packages = lockf.packages()
        lock_content = json.encode({
            "packages": _without_provided_edges(packages),
            "version": json.decode(lockf.as_json())["version"],
        })
        lock = _AptLock.new(
            snapshot = SNAPSHOT,
            archs = list(ARCHS),
            packages = packages,
            package_name_map = package_name_map,
            requested = requested,
        )

    for p in packages:
        key = lockfile.make_package_key(p["name"], p["version"], p["arch"])
        deb_import(
            name = "%s_%s" % (name, key),
            sha256 = p["sha256"],
            urls = p["urls"],
        )

    deb_translate_lock(name = name, lock_content = lock_content)

    apt_result = _AptSchema.AptResult.new(
        packages = packages,
        package_groups = package_groups,
        package_name_map = package_name_map,
    )

    return apt_result, _AptLock.encode(lock)
