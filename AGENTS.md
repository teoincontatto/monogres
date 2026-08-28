# AGENTS.md

## Development environment

NixOS project. `flake.nix` + `.envrc` (direnv) provide the dev shell.

<!-- markdownlint-capture -->
<!-- markdownlint-disable MD013 -->
- **Git**: always inside `nix develop`, hooks need nix tools
  `nix develop --command bash -c 'git commit ...'`
- **Bazel**: always inside Docker as `postgres`.
  `docker exec -u postgres bzlsndbx-monogres_x86_64 bazel ...`
- **Hermetic by default**: `.bazelrc` defaults `build` (inherited by `test`/`run`)
  to `--config=hermetic-linux-<arch>` (e.g. `hermetic-linux-amd64`), so every Bazel
  command runs in the empty-chroot hermetic sandbox with no extra flags. Keep runs
  hermetic; never disable the sandbox. Cross-arch/RBE override with their own
  `--config=` (e.g. `--config=remote-buildbarn --config=linux-arm64-buildbarn`).
- **Unprivileged userns**: the hermetic sandbox needs an unprivileged user
  namespace. Ubuntu 24.04+ ships `kernel.apparmor_restrict_unprivileged_userns=1`,
  which denies one to `postgres`, and Bazel then *silently* degrades to
  `processwrapper-sandbox` rather than failing. What that breaks: make-path
  versions (PG <= 15.x) die in `set_up_sysroots` with `ln: failed to create
  symbolic link '/usr/bin/perl': Permission denied` (only the empty chroot has a
  writable `/usr/bin`), and every test-lane `sh_test` dies with `ERROR: runner not
  executable:` (`--nobuild_runfile_links` means the runfiles tree materializes
  only inside the chroot, so the harness cannot find `pg_regress`). Confirm with
  `bazel build --spawn_strategy=linux-sandbox //...`: "no strategy with that
  identifier was registered" means it is off. Fix on the *host*, not in the
  container: `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`
  (persist under `/etc/sysctl.d/`), then `bazel shutdown` -- sandbox support is
  probed once per server start, so a server started before the change keeps the
  fallback. Neither workaround works: `docker exec --privileged` leaves a non-root
  uid with an empty permitted capability set, and running Bazel as `root` gets the
  sandbox but not the tests, since `initdb` refuses to run as root.
- **Docker**: start container (if not running)
  `nix develop --command bash -c 'make -C build/docker run-image USE_CACHE=true DETACHED=true'`
  Container: `bzlsndbx-<project>_<arch>` (ask user if arch != x86_64)
- **Download proxy**: opt-in, Docker only. Copy `.bazel_downloader.cfg.user.tmpl` to
  `.bazel_downloader.cfg.user` and uncomment `--downloader_config` in `.bazelrc.user`.
  Every workspace that opts in needs its own copy, or Bazel refuses to parse the config.
  The container reaches the proxy at `host.docker.internal`, which does not resolve on
  the host, so wiring it there breaks host-side `bazel query`/`mod`.
<!-- markdownlint-restore -->

## Validation

Fast checks first. Remind user to run the full build (last step).

<!-- markdownlint-capture -->
<!-- markdownlint-disable MD013 -->
1. Pre-commit (seconds, in host):
   `nix develop --command bash -c 'prek run --all-files'`
     - Single hook: `prek run <hook> --all-files`.
2. Unit tests (seconds, in Docker):
   `docker exec -u postgres bzlsndbx-monogres_x86_64 bazel test //tests/...`
     - Scope to what you changed: `//tests/monoext/private/base/...`
     - `starlark_utils` is a separate module:
       `docker exec -u postgres -w /src/workspace/starlark_utils bzlsndbx-monogres_x86_64 bazel test //...`
3. Integration tests (minutes, Docker):
   `docker exec -u postgres -w /src/workspace/examples bzlsndbx-monogres_x86_64 bazel test //...`
     - Invariants only (faster): append `--test_size_filters=small,medium`
4. Full bazel tests (minutes, Docker):
   `nix develop --command bash -c 'prek run bazel-test-all'`
5. Full build (1h+, ask the user): Never build all targets. Remind user to run.
<!-- markdownlint-restore -->

## Starlark codegen

Use `starlark_utils`, not string templates. Read
`build/starlark_utils/docs/CODEGEN_GUIDE.md` first.
