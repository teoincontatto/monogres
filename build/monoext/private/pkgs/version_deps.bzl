"""
Version-aware dependency resolution for extension packages.

Resolves which packages apply to a specific extension version by matching
against versioned spec maps from `repo.json`.

Spec strings support an optional `/arch` suffix so that deps can vary per
architecture::

    "*"          any version, any arch (backward compat) "*/*"        any
    version, any arch (explicit) "*/amd64"    any version, amd64 only
    ">=14/arm64" version >=14, arm64 only ">=14"       version >=14, any arch
    (no slash = any arch)
"""

load("@version_utils//spec:spec.bzl", Spec = "spec")
load("@version_utils//version:version.bzl", Version = "version")

def _parse_spec(spec_str):
    """Split `version_spec[/arch_spec]` into a `(version_spec, arch_spec)` pair.

    When no `/` is present the arch spec defaults to `"*"` (any arch).
    """
    parts = spec_str.split("/", 1)
    return (parts[0], parts[1]) if len(parts) == 2 else (parts[0], "*")

def _arch_matches(arch_spec, arch):
    if arch == None or arch_spec == "*":
        return True
    return arch_spec == arch

def spec_matches(spec_str, version, arch = None):
    """Checks whether a version spec matches a version string and optional arch.

    The `"*"` wildcard matches unconditionally. Other specs use the `SEMVER`
    scheme which handles `major.minor.patch` versions (e.g. `0.3.0`, `13.2.0`)
    natively. An optional `/arch` suffix restricts the match to a specific
    architecture.

    Args:
        spec_str: Version constraint expression, optionally with `/arch` suffix
            (e.g. `"*"`, `">=13.2.0"`, `"*/amd64"`).
        version: Extension version string.
        arch: Architecture name (e.g. `"amd64"`), or `None` to skip arch
            matching.

    Returns:
        `True` if the spec matches.
    """
    version_spec, arch_spec = _parse_spec(spec_str)

    if not _arch_matches(arch_spec, arch):
        return False

    if version_spec == "*":
        return True

    spec = Spec.new(version_spec, version_scheme = Version.SCHEME.SEMVER)
    return spec.match(version)

def get_version_deps(version, deps, arch = None, _fail = fail):
    """Gets which deps packages apply to a specific extension version.

    Scans all version specs in deps, collects matches, and fails if more than
    one spec matches.

    Args:
        version: Extension version string (e.g. `"13.2.0"`).
        deps: Dict of `{spec_str: [packages]}`.
        arch: Architecture name (e.g. `"amd64"`), or `None` for arch-agnostic
            matching.
        _fail: Failure function (injectable for testing).

    Returns:
        A list of packages for this version, or `[]` if no spec matches.
    """
    matches = [
        (spec_str, packages)
        for spec_str, packages in deps.items()
        if spec_matches(spec_str, version, arch)
    ]

    if len(matches) > 1:
        msg = "Version %s matched multiple dep specs: %r"
        return _fail(msg % (version, [m[0] for m in matches]))

    return matches[0][1] if matches else []

testing = struct(
    _parse_spec = _parse_spec,
    _arch_matches = _arch_matches,
)
