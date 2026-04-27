#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="$(make -s -C "${SCRIPT_DIR}/../build/docker" container-name 2>/dev/null)" \
  || CONTAINER="sandbox_monogres_$(uname -m)"

if ! docker inspect --format='{{.State.Running}}' "${CONTAINER}" 2>/dev/null | grep -q true; then
  echo "Skipping bazel-test-all: container ${CONTAINER} is not running"
  exit 0
fi

docker exec -i -u postgres -w /src/workspace "${CONTAINER}" bash -s <<'EOF'
set -uo pipefail

MODULE=(
  .
  docs
  starlark_utils
  starlark_utils/examples
  starlark_utils/docs
  tests
  examples
  e2e
  e2e/smoke
)

MODULE_NAME="$(
  grep -A1 -E "module\(" MODULE.bazel | xargs |
  tr -d "," | awk '{print $NF}'
)"

FAILED=()

for module in ${MODULE[@]}; do
  [[ ! -f "${module}/MODULE.bazel" ]] && continue

  # NOTE:
  # Skipping docs for Bazel 8 because it adds 'load()' statements.
  [[ "${module}" == "docs" ]] && bazel --version | grep -q 'bazel 8.' && continue

  pushd "${module}" > /dev/null

  echo
  if [[ "${module}" == "." ]]; then
    echo "--- [${MODULE_NAME}] --------------------------------"
  else
    echo "--- [${MODULE_NAME}/${module}] --------------------------------"
  fi
  echo

  # NOTE:
  # "no test targets" error (exit code 4) is allowed.
  # See the Bazel wrapper in tools/bazel
  if ! bazel test //...; then
    FAILED+=("${module}")
  fi

  popd > /dev/null
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo
  echo "FAILED modules: ${FAILED[*]}"
  exit 1
fi
EOF
