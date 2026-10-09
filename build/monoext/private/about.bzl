"""
What the catalog says about each entry for a reader rather than for the build.

monobot writes an `about.json` beside every `repo.json` (description, licence,
homepage, repository, and per version the ref and README). Nothing here builds
from it; it is read once in module extension context and handed to the
extensions hub, which re-exposes it from `all.bzl` so a consumer can label what
it ships without reading the catalog itself.
"""

def _read(ctx, label):
    # Watched even while absent, so an `about.json` added later re-evaluates
    # the extension; `ctx.path(...).exists` alone registers no dependency.
    ctx.watch(label)

    if not ctx.path(label).exists:
        return {}

    return json.decode(ctx.read(label))

def _contrib_controls(entry):
    """The control files a contrib entry installs, by name, sorted.

    A contrib entry is named after its directory and the extensions in it after
    their control files, and the two diverge: `spi` installs `autoinc`,
    `insert_username`, `moddatetime` and `refint`; `hstore_plpython` installs
    `hstore_plpython3u`.
    """
    controls = {}
    for files in entry.metadata.get("files", {}).values():
        for path in files:
            if path.startswith("share/extension/") and path.endswith(".control"):
                stem = path[len("share/extension/"):-len(".control")]
                controls[stem] = True

    return sorted(controls)

def read_about(ctx, base, catalog, extensions):
    """Reads the `about.json` of a flavor and of every extension it carries.

    Args:
        ctx: Module extension context.
        base: Label of the flavor's `repo.json`; its `about.json` is beside it.
        catalog: Label of the extensions catalog `index.json`, or `None`.
        extensions: `{name: ExtensionEntry}` from `create_ext_src`.

    Returns:
        A `struct(flavor, extensions, contrib)` of plain dicts:
          - `flavor`: the flavor's own document, less its `contrib` block.
          - `extensions`: `{name: about}` for the external extensions that
            have one.
          - `contrib`: `{name: about}` for the contrib entries, taken from the
            flavor's `contrib` block under the entry's own name, or else under
            the first control file it installs that the block describes.
    """
    flavor = dict(_read(ctx, base.relative(":about.json")))
    described = flavor.pop("contrib", {})

    external = {}
    contrib = {}

    for name in sorted(extensions):
        entry = extensions[name]

        if not entry.is_contrib:
            if catalog:
                about = _read(ctx, catalog.relative(":%s/about.json" % name))
                if about:
                    external[name] = about
            continue

        if name in described:
            contrib[name] = described[name]
            continue

        for control in _contrib_controls(entry):
            if control in described:
                contrib[name] = described[control]
                break

    return struct(flavor = flavor, extensions = external, contrib = contrib)
