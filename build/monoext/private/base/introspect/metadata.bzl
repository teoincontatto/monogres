"""
PG introspect manual metadata
"""

# NOTE:
# FEATURES_TO_DEB_PKGS maps the feature to the required Debian package(s). It
# was curated by hand from PG 16.0 contrib extensions. Hopefully / luckily,
# these should not change too often and will probably remain the same for a long
# time. But if not, then we will probably have to add some versioning
# mechanisms.
FEATURES_TO_DEB_PKGS = {
    "bonjour": "libavahi-compat-libdnssd-dev",
    "docs": [
        "libxml2-utils",
        "xsltproc",
    ],
    "docs_pdf": [
        "libxml2-utils",
        "xsltproc",
        "fop",
    ],
    "gssapi": "libkrb5-dev",
    "icu": "libicu-dev",
    "ldap": "libldap-dev",
    "libcurl": "libcurl4-openssl-dev",
    "libnuma": "libnuma-dev",
    "liburing": "liburing-dev",
    "libxml": "libxml2-dev",
    "libxslt": "libxslt1-dev",
    "llvm": [
        "llvm-dev",
        "clang",
    ],
    "lz4": "liblz4-dev",
    "nls": "gettext",
    "pam": "libpam0g-dev",
    "plperl": "libperl-dev",
    "plpython": "libpython3-dev",
    "pltcl": "tcl-dev",
    "readline": {
        "libedit": "libedit-dev",
        "libreadline": "libeditreadline-dev",
    },
    "selinux": "libselinux1-dev",
    "ssl": {
        "openssl": "libssl-dev",
    },
    "systemd": "libsystemd-dev",
    "uuid": {
        "e2fs": "uuid-dev",
        "ossp": "libossp-uuid-dev",
    },
    "zlib": "zlib1g-dev",
    "zstd": "libzstd-dev",
}

FEATURES_OVERRIDE = {
    # the .found() in basebackup_to_shell is only for testing and selecting
    # tools
    "basebackup_to_shell": None,
}

DEP_TO_FEATURE = {
    "perl_dep": "plperl",
    "python3_dep": "plpython",
}

# NOTE:
# We need to override some of the contrib installed paths when the meson.build
# files exist but, due to bugs or other issues, no contrib targets or install
# paths are properly generated. For example:
# https://github.com/postgres/postgres/commit/823eb3db1c50a6b8a89ebedc1db96b14de140183
# where the sepgsql contrib extension was not being installed, pre-17.0 NOTE:
# The paths use "lib/" instead of "lib/{cpu}-linux-gnu/" because the actual
# meson builds configure libdir = "lib" (in build_options.bzl) rather than
# Debian's default multiarch libdir.
# NOTE:
# The procedural languages a flavor's own tree builds under `src/pl/`, keyed by
# language and valued by the three artifact name sets one installs:
#
#   extensions: `share/extension/<name>.control` plus `<name>--*.sql`. A
#               language registers more than one when it has an untrusted
#               variant (plperl / plperlu).
#   modules:    `lib/<name>.so`, the loadable the call handler lives in. Not
#               derivable from the extension name: `plpython3u` is served by
#               `plpython3.so`.
#   catalogs:   `share/locale/*/LC_MESSAGES/<name>-<major>.mo`. Not derivable
#               either: plpython3's message catalogs are named `plpython`.
#
# Curated by hand rather than introspected because only the Meson JSONs carry a
# `src/pl/<language>/` build path to group by. The make-path JSONs are
# synthesized by walking the finished install tree
# (`tools/pg_build_make_introspect.py`), where a PL's files are
# indistinguishable from the backend's own. `build_introspect` checks the table
# against the data instead: a core extension it cannot attribute to a language
# here fails the introspect rather than being silently misfiled.
PL_LANGUAGES = {
    "plisql": struct(
        extensions = ["plisql"],
        modules = ["plisql"],
        catalogs = ["plisql"],
    ),
    "plperl": struct(
        extensions = ["plperl", "plperlu"],
        modules = ["plperl"],
        catalogs = ["plperl"],
    ),
    "plpgsql": struct(
        extensions = ["plpgsql"],
        modules = ["plpgsql"],
        catalogs = ["plpgsql"],
    ),
    "plpython": struct(
        extensions = ["plpython3u"],
        modules = ["plpython3"],
        catalogs = ["plpython"],
    ),
    "pltcl": struct(
        extensions = ["pltcl", "pltclu"],
        modules = ["pltcl"],
        catalogs = ["pltcl"],
    ),
}

CONTRIB_INSTALLED_PATHS_OVERRIDE = {
    "sepgsql": {
        "<16.7": [
            "lib/sepgsql.so",
            "share/extension/sepgsql.sql",
        ],
        # NOTE: the path changed in 16.7
        # https://github.com/postgres/postgres/commit/155d616
        ">=16.7,<17.0": [
            "lib/sepgsql.so",
            "share/contrib/sepgsql.sql",
        ],
    },
}
