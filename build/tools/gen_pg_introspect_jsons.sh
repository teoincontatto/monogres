#!/bin/bash

set -euo pipefail

_make_comparable() {
    local json="$1"; shift

    local pg_version pg_version_re
    pg_version="$(echo "${json}" | cut -d~ -f2)"
    # Escape regex metacharacters in pg_version (dots in particular) so
    # "18.3" doesn't also match unrelated tokens like "gb18030".
    pg_version_re="${pg_version//./\\.}"

    sed -E "
        s;/[a-z]+/.cache/bazel/_bazel_[a-z]+/[a-f0-9]+;<BAZEL_CACHE>;g
        s;<BAZEL_CACHE>/sandbox/[a-z]+-sandbox/[0-9]+/execroot/_main;<BAZEL_CACHE>/<SANDBOX>/<BAZEL-BUILD>;g
        s;<BAZEL_CACHE>/execroot/_main;<BAZEL_CACHE>/<BAZEL-BUILD>;g
        s;${pg_version_re};<PG_VERSION>;g
        s;postgres(-contrib)?~<PG_VERSION>~[a-z]+;<PG_TARGET>;g
        s;aarch64;{arch};g
        s;x86_64;{arch};g
        s;amd64;{arch};g
        s;k8;{arch};g
    " "${json}"
}
export -f _make_comparable

_make_comparable_all() {
    local json_dir="postgres/introspect/json"

    rm -rf "${json_dir}"/postgres~*.json

    # Source JSONs from the postgres-contrib variants so the recorded install
    # plan includes contrib extensions (needed by @pg_introspect to enumerate
    # them). Rename the outputs to drop the "-contrib" prefix since downstream
    # (repo.json metadata, INTROSPECTIONS key) uses the non-contrib filename.
    bazel query 'filter("postgres-contrib~.*--introspect$", //postgres/...)' 2>/dev/null \
      | xargs -n 1 bazel build 2>&1 \
      | grep '^ \+/postgres/' \
      | tr -d ' ' \
      | xargs -I@ /bin/bash -c '
            out_name="$(basename @ | sed "s/^postgres-contrib~/postgres~/")"
            _make_comparable "@" >| "'"${json_dir}"'/$out_name"
        '
    chmod 444 "${json_dir}"/*.json
}

_make_comparable_all
