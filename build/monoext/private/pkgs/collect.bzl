"""
Collect package groups from extension metadata.

Pure function that takes data (not `ctx`), making it unit-testable. Used by the
`@pkgs` layer to build globally-deduplicated package groups.
"""

load(":schema.bzl", _PkgsSchema = "schema")
load(":version_deps.bzl", "get_version_deps")

def _deps(metadata, kind, distro = "debian"):
    """Extracts the versioned deps spec map from metadata."""
    return metadata.get("deps", {}).get(kind, {}).get(distro, {})

def collect_package_groups(extensions):
    """Collects globally-deduplicated package groups from extensions.

    Iterates all extensions and their version-resolved deps, building a
    content-addressed map of unique package sets and a nested mapping from kind
    to `(ext_name, ext_version)` to group keys.

    Args:
        extensions: Dict of `{name: {ext_versions, metadata}}`.

    Returns:
        Tuple of `(pkgs_groups, ext_dep_groups)` where:
          - `pkgs_groups`: `{content_key: [packages]}`
          - `ext_dep_groups`:
            `{kind: {(name, version): content_key}}`
    """
    pkgs_groups = {}
    ext_dep_groups = {}

    for name, ext in sorted(extensions.items()):
        for kind in _PkgsSchema.KINDS:
            deps = _deps(ext["metadata"], kind)

            for ext_version in ext["ext_versions"]:
                packages = get_version_deps(ext_version, deps)

                if packages:
                    key = ",".join(sorted(packages))
                    pkgs_groups[key] = packages

                    if kind not in ext_dep_groups:
                        ext_dep_groups[kind] = {}

                    ext_dep_groups[kind][(name, ext_version)] = key

    return pkgs_groups, ext_dep_groups
