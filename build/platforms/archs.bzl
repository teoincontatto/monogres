"""
Single source of truth for supported architectures.

Every file that needs to iterate, select, or reference architectures loads from
here. No other file in the workspace should define its own ARCHS list.
"""

ARCH_CPU = {
    "amd64": "x86_64",
    "arm64": "aarch64",
}

ARCHS = ARCH_CPU.keys()

def arch_select(values, default = None):
    """Build a platform-aware `select()` from `{arch_name: value}`.

    Args:
        values: Dict mapping Debian arch names to values.
        default: Optional fallback for `//conditions:default`.

    Returns:
        A `select()` keyed by `@platforms//cpu:*` constraint values.
    """
    select_ = {
        "@platforms//cpu:%s" % ARCH_CPU[arch]: v
        for arch, v in values.items()
    }

    if default != None:
        select_["//conditions:default"] = default

    return select(select_)
