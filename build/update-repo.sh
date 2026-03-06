#!/bin/bash

cd "$(dirname "$0")/.."

rm -f build/extensions/all.bzl
cp build/extensions/all.template.bzl build/extensions/all.bzl

if ! grep -qxF '# extensions start' build/MODULE.bazel \
  || ! grep -qxF '# extensions end' build/MODULE.bazel
then
  >&2 echo "Missing '# extensions start' and '# extensions end' markers between 'PG_EXTENSIONS = []' variable"
  exit 1
fi
sed -z -i "s/\n# extensions start\n.*\n# extensions end\n/\n# extensions start\nPG_EXTENSIONS = [\n]\n# extensions end\n/" build/MODULE.bazel

for EXTENSION in $(test "$#" != 0 && echo "$*" || ls -1 build/extensions)
do
  if [ "$EXTENSION" = contrib ]; then
    continue
  fi
  if ! [ -d "build/extensions/$EXTENSION" ] \
    || ! [ -f "build/extensions/$EXTENSION/repo.json" ]; then
    continue
  fi
  if [ "$(jq 'has("version") and has("sources") and has("versions")' \
      "build/extensions/$EXTENSION/repo.json")" != true ] \
    || [ "$(jq '.versions|to_entries|all(.key|test("^([0-9]+[.-]?)+"))' \
      "build/extensions/$EXTENSION/repo.json")" != true ]; then
    echo "Skipping $EXTENSION"
    rm -f build/extensions/$EXTENSION/cfg.bzl
    rm -f build/extensions/$EXTENSION/BUILD.bazel
    sed -i "/ *load( *\"\/\/extensions\/${EXTENSION}:cfg\.bzl\"/d" build/extensions/all.bzl
    sed -i "/ \"${EXTENSION}\": *\[.*\] *, */d" build/extensions/all.bzl
    continue
  fi
  echo "Updating extension $EXTENSION"
  if [ "$(jq '.sources|to_entries|all((.value.type != null) or (.value.url|test("^.*/[^/.]+$")|not))' \
    "build/extensions/$EXTENSION/repo.json" 2>/dev/null)" != true ]; then
    rm -f "build/extensions/$EXTENSION/repo.json.tmp"
    jq '.sources = (.sources|to_entries|map(.value.type = "tar.gz")|from_entries)' \
      "build/extensions/$EXTENSION/repo.json" > "build/extensions/$EXTENSION/repo.json.tmp"
    mv -f "build/extensions/$EXTENSION/repo.json.tmp" "build/extensions/$EXTENSION/repo.json"
  fi
  if [ "$(jq '.metadata.buildtime_dependencies.debian13|type' -r \
    "build/extensions/$EXTENSION/repo.json" 2>/dev/null)" = array ]; then
    echo "Found $(jq '.metadata.buildtime_dependencies.debian13|length' -r \
      "build/extensions/$EXTENSION/repo.json") buildtime dependencies for extension $EXTENSION"
  fi
  if [ "$(jq '.metadata.runtime_dependencies.debian13|type' -r \
    "build/extensions/$EXTENSION/repo.json" 2>/dev/null)" = array ]; then
    echo "Found $(jq '.metadata.runtime_dependencies.debian13|length' -r \
      "build/extensions/$EXTENSION/repo.json") runtime dependencies for extension $EXTENSION"
  fi
  cat << EOF > build/extensions/$EXTENSION/cfg.bzl
"""
Extensions build configuration.
"""

load("@pgext_${EXTENSION}//:repo.bzl", "METADATA", "REPO_NAME", "VERSIONS")
load("//extensions:cfg.bzl", "cfg")
load("//postgres:cfg.bzl", PG_CFG = "CFG")

CFG = cfg.new(
    name = "${EXTENSION}",
    versions = VERSIONS,
    pg_targets = PG_CFG.targets,
    repo_name = REPO_NAME,
    metadata = METADATA,
$(
    if [ "$(jq '.metadata.buildtime_dependencies.debian13|type' -r \
      "build/extensions/$EXTENSION/repo.json" 2>/dev/null)" = array ]; then
      cat << INNER_EOF
    buildtime_dependencies = [
$(jq --arg extension "$EXTENSION" \
  '.metadata.buildtime_dependencies.debian13 + [] | .[]
    | "\"@pgext_" + $extension + "_deps_debian13//" + . + "\","' \
  -r \
  "build/extensions/$EXTENSION/repo.json" \
    | sed 's/^/        /')
    ],
INNER_EOF
    fi
    if [ "$(jq '.metadata.runtime_dependencies.debian13|type' -r \
      "build/extensions/$EXTENSION/repo.json" 2>/dev/null)" = array ]; then
      cat << INNER_EOF
    runtime_dependencies = [
$(jq --arg extension "$EXTENSION" \
  '.metadata.runtime_dependencies.debian13 + [] | .[]
    | "\"@pgext_" + $extension + "_deps_debian13//" + . + "\","' \
  -r \
  "build/extensions/$EXTENSION/repo.json" \
    | sed 's/^/        /')
    ],
INNER_EOF
    fi
)
)
EOF
  cat << EOF > build/extensions/$EXTENSION/BUILD.bazel
load("//extensions:pgxs_build.bzl", "pgxs_build_all")
load(":cfg.bzl", "CFG")

pgxs_build_all(
    name = CFG.name,
    cfg = CFG,
)
EOF
  sed -i "/ *load( *\"\/\/extensions\/${EXTENSION}:cfg\.bzl\"/d" build/extensions/all.bzl
  LAST_EXTENSION_LOAD_LINE="$(grep -n 'load(' build/extensions/all.bzl | tail -n 1 | cut -d : -f 1)"
  if [ -z "$LAST_EXTENSION_LOAD_LINE" ]; then
    LAST_EXTENSION_LOAD_LINE=4
  fi
  sed -i "${LAST_EXTENSION_LOAD_LINE}a load(\"//extensions/${EXTENSION}:cfg.bzl\", CFG_${EXTENSION^^} = \"CFG\")" build/extensions/all.bzl
  sed -i "/ \"${EXTENSION}\": *\[.*\] *, */d" build/extensions/all.bzl
  LAST_EXTENSION_CFG_ALL_LINE="$(grep -n " \"[^\"]\+\": *\[.*\] *, *" build/extensions/all.bzl | tail -n 1 | cut -d : -f 1)"
  if [ -z "$LAST_EXTENSION_CFG_ALL_LINE" ]; then
    LAST_EXTENSION_CFG_ALL_LINE="$((LAST_EXTENSION_LOAD_LINE + 3))"
  fi
  sed -i "${LAST_EXTENSION_CFG_ALL_LINE}a \ \ \ \ \"${EXTENSION}\": [CFG_${EXTENSION^^}]," build/extensions/all.bzl
  LAST_PG_EXTENSIONS_LINE="$(grep -nF 'PG_EXTENSIONS = [' build/MODULE.bazel | tail -n 1 | cut -d : -f 1)"
  LAST_PG_EXTENSIONS_CLOSE_LINE="$(tail -n+"$LAST_PG_EXTENSIONS_LINE" build/MODULE.bazel | grep -nF ']' | head -n 1 | cut -d : -f 1)"
  if [ "$LAST_PG_EXTENSIONS_CLOSE_LINE" != 2 ]
  then
    LAST_PG_EXTENSIONS_LAST_ENTRY_LINE="$((LAST_PG_EXTENSIONS_LINE + LAST_PG_EXTENSIONS_CLOSE_LINE - 1))"
  else
    LAST_PG_EXTENSIONS_LAST_ENTRY_LINE="$((LAST_PG_EXTENSIONS_LINE + LAST_PG_EXTENSIONS_CLOSE_LINE - 2))"
  fi
  if [ -z "$LAST_PG_EXTENSIONS_LINE" ] || [ -z "$LAST_PG_EXTENSIONS_LAST_ENTRY_LINE" ]; then
    >&2 echo "Missing 'PG_EXTENSIONS = []' variable"
    exit 1
  fi
  PG_EXTENSION_ENTRY="$(
    cat << EOF | sed -z -e 's/ /\\ /g' -e 's/\n$//' -e 's/\n/\\n/g'
    [
        "${EXTENSION}",
$(
  cat << INNER_EOF
        {
INNER_EOF
  jq '({} + .metadata.patches)|to_entries[]|.key + " " + .value' -r \
    "build/extensions/$EXTENSION/repo.json" \
    | while read KEY VALUE
      do
        cat << INNER_EOF
          "//extensions/$EXTENSION/patches:$KEY": "$VALUE",
INNER_EOF
      done
  cat << INNER_EOF
        },
INNER_EOF
)
    ],
EOF
    )"
  sed -i "$((LAST_PG_EXTENSIONS_LAST_ENTRY_LINE))a $PG_EXTENSION_ENTRY" build/MODULE.bazel
done

echo "Updated $(grep -c " \"[^\"]\+\": *\[.*\] *, *" build/extensions/all.bzl) extensions"