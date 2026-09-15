"""
Lockfile schema for `monoext`'s apt package resolution.

Provides encode/decode/validate helpers for the `.lock` JSON file that caches
resolved Debian package state, eliminating network downloads on cold
module-extension evaluations.
"""

load("//monoext/private/apt:snapshot.bzl", _SNAPSHOT = "SNAPSHOT")

LOCK_VERSION = 1
SNAPSHOT = _SNAPSHOT

def _lock_new(snapshot, archs, packages, package_name_map, requested):
    """Constructs an `AptLock` struct.

    Args:
        snapshot: The Debian snapshot timestamp used during resolution.
        archs: List of architecture strings resolved.
        packages: List of package dicts from `lockf.packages()`.
        package_name_map: `{requested: resolved}` virtual package substitutions.
        requested: The package constraints the resolver was asked for, i.e. the
            roots. Only a root carries its dependency closure in `packages`, so
            this is what tells a lock apart from one generated for a different
            request. See `requested_mismatch`.

    Returns:
        An `AptLock` struct.
    """
    return struct(
        version = LOCK_VERSION,
        snapshot = snapshot,
        archs = sorted(archs),
        packages = packages,
        package_name_map = package_name_map,
        requested = sorted(requested),
    )

def _lock_encode(lock):
    """Serializes an `AptLock` struct to a JSON string.

    Args:
        lock: A lock data struct from `lock_new`.

    Returns:
        A JSON string.
    """
    return json.encode_indent({
        "archs": lock.archs,
        "package_name_map": lock.package_name_map,
        "packages": lock.packages,
        "requested": lock.requested,
        "snapshot": lock.snapshot,
        "version": lock.version,
    }, indent = "  ")

def _lock_decode(lock_json):
    """Deserializes a JSON string into an `AptLock` struct.

    Args:
        lock_json: A JSON string produced by `lock_encode`.

    Returns:
        An `AptLock` struct.
    """
    d = json.decode(lock_json)

    version = d.get("version", 0)
    if version != LOCK_VERSION:
        msg = "AptLock version %d, expected %d. "
        msg += "Regenerate with: bazel run @<pkgs>//deb/lock:update"
        fail(msg % (version, LOCK_VERSION))

    return _lock_new(
        snapshot = d["snapshot"],
        archs = d["archs"],
        packages = d["packages"],
        package_name_map = d.get("package_name_map", {}),
        # A lock written before `requested` existed records no roots at all, so
        # it reads as generated for an empty request and `requested_mismatch`
        # sends it back through live resolution -- which is what regenerates it.
        requested = d.get("requested", []),
    )

def _lock_validate(lock, snapshot, archs):
    """Validates an `AptLock` struct against what it was resolved against.

    Returns an error string describing the mismatch, or `None` if valid.

    What it was resolved *for* is a separate question, answered by
    `requested_mismatch`.

    Args:
        lock: An `AptLock` struct.
        snapshot: Expected Debian snapshot timestamp.
        archs: Expected architecture list.

    Returns:
        An error string, or `None` if the lockfile is valid.
    """
    if lock.snapshot != snapshot:
        return "snapshot mismatch: lock has %s, expected %s" % (
            lock.snapshot,
            snapshot,
        )

    if sorted(archs) != lock.archs:
        return "archs mismatch: lock has %s, expected %s" % (
            lock.archs,
            sorted(archs),
        )

    return None

def _lock_requested_mismatch(lock, requested):
    """Reports whether a lock was generated for a different set of roots.

    `validate`'s membership test is not enough on its own: only a root carries
    its dependency closure, and a package can be in the lock without ever having
    been one. pgrouting's `libboost-dev` was exactly that -- present, because
    postgis's `libgdal-dev` reaches it, but with no edges of its own, so the
    closure walker handed pgrouting a sysroot holding the empty metapackage and
    nothing else and cmake reported `Could NOT find Boost`. Nothing failed; the
    lock simply predated the catalog entry.

    Args:
        lock: An `AptLock` struct.
        requested: The package constraints resolution is being asked for now.

    Returns:
        An error string naming what changed, or `None` if the sets agree.
    """
    locked = {pkg: True for pkg in lock.requested}
    wanted = {pkg: True for pkg in requested}

    added = sorted([pkg for pkg in wanted if pkg not in locked])
    dropped = sorted([pkg for pkg in locked if pkg not in wanted])

    if not added and not dropped:
        return None

    parts = []
    if added:
        parts.append("requested but not resolved as roots: %s" % ", ".join(added))
    if dropped:
        parts.append("resolved as roots but no longer requested: %s" % ", ".join(dropped))
    return "; ".join(parts)

apt_lock = struct(
    LOCK_VERSION = LOCK_VERSION,
    new = _lock_new,
    encode = _lock_encode,
    decode = _lock_decode,
    validate = _lock_validate,
    requested_mismatch = _lock_requested_mismatch,
)
