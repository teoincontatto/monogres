"""
Reading the catalog's versioned `about.json`.

monobot writes every version of what an entry says about itself once: the
newest in full under `latest`, which names it in `version`, and each older one
under `versions`, newest first, as a JSON Merge Patch (RFC 7386) over the
version after it. Objects merge field by field, anything else replaces, and
`null` removes what the newer version had.

```json
{
  "latest": {"version": "5.4", "description": "...", "ref": "BABEL_5_4_0__PG_17_7"},
  "versions": {"5.3": {"ref": "BABEL_5_3_0__PG_17_6"}}
}
```

`about_versions` turns one into a document per version, which is what a
consumer labelling the image of one version wants. It is public so that a
module keeping a catalog of its own in the same format reads it the same way.
"""

# Starlark has no recursion, so a merge walks a work list. No document nests
# anywhere near this deep; the bound only exists because a loop needs one.
_MAX_MERGES = 1000000

def apply_patch(target, patch):
    """`patch` merged over `target`, per RFC 7386.

    Args:
        target: The document patched; not modified.
        patch: The merge patch.

    Returns:
        A new document. What it shares with `target` is only what the patch
        left alone, and nothing here writes to it.
    """
    if type(patch) != "dict":
        return patch

    merged = dict(target) if type(target) == "dict" else {}
    work = [(merged, patch)]
    for _ in range(_MAX_MERGES):
        if not work:
            break
        into, layer = work.pop()
        for key, value in layer.items():
            if value == None:
                into.pop(key, None)
            elif type(value) == "dict":
                child = into.get(key)
                child = dict(child) if type(child) == "dict" else {}
                into[key] = child
                work.append((child, value))
            else:
                into[key] = value

    return merged

def about_versions(document):
    """Every version a versioned `about.json` describes, each in full.

    Args:
        document: The decoded `about.json`.

    Returns:
        `{version: document}`, newest first. Empty for a document that holds
        no `latest`, which is what an entry nothing describes has.
    """
    latest = document.get("latest")
    if not latest:
        return {}

    current = {key: value for key, value in latest.items() if key != "version"}
    resolved = {latest["version"]: current}
    for version, patch in document.get("versions", {}).items():
        current = apply_patch(current, patch)
        resolved[version] = current

    return resolved
