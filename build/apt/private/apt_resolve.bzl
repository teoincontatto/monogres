"""
Apt dependency resolution against the shared Debian baseline.

This file is the canonical source of truth for the Debian snapshot inputs and
provides in-process package resolution used by `apt_deps.bzl` to create the
internal dependency repos.
"""

# buildifier: disable=bzl-visibility
load("@rules_distroless//apt/private:apt_deb_repository.bzl", "deb_repository")

# buildifier: disable=bzl-visibility
load("@rules_distroless//apt/private:apt_dep_resolver.bzl", "dependency_resolver")

# buildifier: disable=bzl-visibility
load("@rules_distroless//apt/private:lockfile.bzl", "lockfile")

# buildifier: disable=bzl-visibility
load("@rules_distroless//apt/private:version_constraint.bzl", "version_constraint")
load("//platforms:archs.bzl", "ARCHS")

_CODENAME = "trixie"
_SNAPSHOT_URL = "https://snapshot-cloudflare.debian.org/archive"
SNAPSHOT = "20260112T000000Z"

_SOURCES = [
    (
        ["%s/debian/%s" % (_SNAPSHOT_URL, SNAPSHOT)],
        _CODENAME,
        "main",
    ),
    (
        ["%s/debian-security/%s" % (_SNAPSHOT_URL, SNAPSHOT)],
        "%s-security" % _CODENAME,
        "main",
    ),
    (
        ["%s/debian/%s" % (_SNAPSHOT_URL, SNAPSHOT)],
        "%s-updates" % _CODENAME,
        "main",
    ),
]

def resolve(ctx, name, packages):
    """Resolves apt packages against the shared Debian baseline.

    For each requested package and architecture, resolves the full transitive
    dependency closure and records any virtual package name substitutions.

    Args:
      ctx: The module extension context.
      name: The name of the generated repository.
      packages: List of package constraint strings.

    Returns:
      A tuple of (lockfile, package_name_map).
    """
    lockf = lockfile.empty(ctx)
    package_name_map = {}

    if not packages:
        return lockf, package_name_map

    repository = deb_repository.new(ctx, archs = ARCHS, sources = _SOURCES)
    resolver = dependency_resolver.new(repository)

    for arch in ARCHS:
        seen = {}

        for dep_constraint in packages:
            if dep_constraint in seen:
                msg = "%s: duplicate package %r"
                fail(msg % (name, dep_constraint))

            seen[dep_constraint] = True
            constraint = version_constraint.parse_depends(dep_constraint).pop()

            package, dependencies, _ = resolver.resolve_all(
                arch = arch,
                include_transitive = True,
                name = constraint["name"],
                version = constraint["version"],
            )

            if not package:
                msg = "%s: unable to locate package %r for architecture %s"
                fail(msg % (name, dep_constraint, arch))

            resolved_name = package["Package"]
            requested_name = constraint["name"]

            if resolved_name != requested_name:
                package_name_map[requested_name] = resolved_name

            lockf.add_package(package, arch)

            for dep in dependencies:
                lockf.add_package(dep, arch)
                lockf.add_package_dependency(package, dep, arch)

    return lockf, package_name_map
