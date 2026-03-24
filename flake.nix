{
  description = "download_archives development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # Bazel's test runner and build actions need these tools on PATH
          bazelDeps = with pkgs; [ bash coreutils gnused findutils gnugrep diffutils gawk gcc ];
          bazelPath = pkgs.lib.makeBinPath bazelDeps;

          bazel = pkgs.writeShellScriptBin "bazel" ''
            case "''${1:-}" in
              test)
                exec ${pkgs.bazelisk}/bin/bazelisk "$@" --test_env=PATH="${bazelPath}"
                ;;
              build|run)
                exec ${pkgs.bazelisk}/bin/bazelisk "$@" --action_env=PATH="${bazelPath}"
                ;;
              *)
                exec ${pkgs.bazelisk}/bin/bazelisk "$@"
                ;;
            esac
          '';
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              gnumake
              bazel
              bazelisk
              buildifier
              prek
              python314
              hadolint
              jsonnet
            ];

            env = {
              BAZEL_SH = "${pkgs.bash}/bin/bash";
            };

            shellHook = ''
              export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              prek install --prepare-hooks --quiet
            '';
          };
        }
      );
    };
}
