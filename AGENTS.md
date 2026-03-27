# AGENTS.md

## Development environment

NixOS project. `flake.nix` + `.envrc` (direnv) provide the dev shell.

<!-- markdownlint-capture -->
<!-- markdownlint-disable MD013 -->
- **Git**: always inside `nix develop`, hooks need nix tools
  `nix develop --command bash -c 'git commit ...'`
- **Bazel**: always inside Docker as `postgres`.
  `docker exec -u postgres sandbox_monogres_x86_64 bazel ...`
- **Docker**: start container (if not running)
  `nix develop --command bash -c 'make -C build/docker run-image USE_CACHE=true DETACHED=true'`
  Container: `sandbox_monogres_<arch>` (ask user if arch != x86_64)
<!-- markdownlint-restore -->

## Validation

Fast checks (1-4) first. Remind user to run full validation (step 5).

<!-- markdownlint-capture -->
<!-- markdownlint-disable MD013 -->
1. Pre-commit (seconds, in host):
   `nix develop --command bash -c 'prek run --all-files'`
     - Single hook: `prek run <hook> --all-files`.
2. Unit tests (seconds, in Docker):
   `docker exec -u postgres sandbox_monogres_x86_64 bazel test //tests/...`
     - Scope to what you changed: `//tests/monoext/private/pg/...`
     - `starlark_utils` is a separate module:
       `docker exec -u postgres -w /src/workspace/starlark_utils sandbox_monogres_x86_64 bazel test //...`
3. Integration tests (minutes, Docker):
   `docker exec -u postgres -w /src/workspace/examples sandbox_monogres_x86_64 bazel test //...`
     - Invariants only (faster): append `--test_size_filters=small,medium`
4. Full bazel tests (minutes, Docker):
   `nix develop --command bash -c 'prek run bazel-test-all'`
5. Full build (1h+, ask the user): Never build all targets. Remind user to run.
<!-- markdownlint-restore -->

## Starlark codegen

Use `starlark_utils`, not string templates. Read
`build/starlark_utils/docs/CODEGEN_GUIDE.md` first.
