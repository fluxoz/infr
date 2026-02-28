{
  description = "Linode infrastructure provisioning flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

      build-base-image = pkgs.writeShellApplication {
        name = "nix-build-base-image";
        runtimeInputs = with pkgs; [ 
          bash
        ];
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          echo "Building Linode image..."
          # nixos-rebuild build-image --flake ${self}#baseconfig --image-variant linode
          nix build .#linodeImage
          echo "✓ Image built"
          ls -lh result/
        '';
      };

      uploader = pkgs.writeShellApplication {
        name = "nix-run-upload";
        runtimeInputs = with pkgs; [
          jq
          sops
          bash
        ];
        text = ''
          set -euo pipefail
          shopt -s nullglob
          echo "[INFO]: Initiating image upload"
          files=(result/nixos*.img.gz)
          if [ ''${#files[@]} -gt 0 ]; then
            IMAGE_PATH="$(pwd)/''${files[0]}"
            echo "Uploading image: $IMAGE_PATH"
            sops exec-env "${self}/secrets/linode.env" "${self}/scripts/upload-image.sh -i $IMAGE_PATH $*"
          else
            echo "Existing: No image found at result/nixos.img.gz"
              echo "Running 'nix run .#build-image' first"
              nix run .#build-image
              sops exec-env "${self}/secrets/linode.env" "${self}/scripts/upload-image.sh -i $IMAGE_PATH $*"
          fi
        '';
      };

      provisioner = pkgs.writeShellApplication {
        name = "nix-run-provision";
        runtimeInputs = with pkgs; [
          jq
          openssl
          sops
        ];
        text = ''
          set -euo pipefail
          files=(result/nixos*.img.gz)
          if [ ''${#files[@]} -gt 0 ]; then
            IMAGE_PATH="$(pwd)/''${files[0]}"
            sops exec-env "${self}/secrets/linode.env" "${self}/scripts/provision.sh -i $IMAGE_PATH $*"
          else
            echo "Existing: No image found at result/nixos.img.gz"
            echo "Running 'nix run .#build-image' and .#upload first"
            nix run .#build-image
            sops exec-env "${self}/secrets/linode.env" "${self}/scripts/upload-image.sh -i $IMAGE_PATH $*"
            sops exec-env "${self}/secrets/linode.env" "${self}/scripts/provision.sh -i $IMAGE_PATH $*"
          fi
        '';
      };

      domainer = pkgs.writeShellApplication {
        name = "nix-run-domain";
        runtimeInputs = with pkgs; [
          jq 
          openssl
          sops
        ];
        text = ''
          set -euo pipefail
          sops exec-env "${self}/secrets/linode.env" "${self}/scripts/domain-setup.sh $*"
        '';
      };

      purger = pkgs.writeShellApplication {
        name = "nix-run-purge";
        runtimeInputs = with pkgs; [
          jq
          openssl
          sops
        ];
        text = ''
          set -euo pipefail
          sops exec-env "${self}/secrets/linode.env" "${self}/scripts/purge.sh $*"
        '';
      };

      nixosConfigurations.baseconfig = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./images/base/default.nix ];
      };

  in {

        nixosModules.base = import ./images/base/default.nix;

        packages.${system} = {
          linodeImage = nixosConfigurations.baseconfig.config.system.build.linodeImage;
          default = self.packages.${system}.linodeImage;
        };
    
        # ===== development environment ====
          devShells.${system}.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              jq
              openssl
              sops
              nixos-rebuild
            ];
            shellHook = ''
              export SOPS_EDITOR=nvim
              echo ""
              echo "🚀 Linode NixOS Image Builder"
              echo "=============================="
              echo "nix run .#build      - Build Linode image"
              echo "nix run .#upload     - Upload to Linode"
              echo "nix run .#provision  - Provision infrastructure"
              echo "nix run .#purge      - Purge a linode"
              echo ""
            '';
          };

        # ===== flake apps =====
          apps.${system} = {
            build-base-image = { type = "app"; program = "${build-base-image}/bin/nix-build-base-image"; };
            upload = { type = "app"; program = "${uploader}/bin/nix-run-upload"; };
            provision = { type = "app"; program = "${provisioner}/bin/nix-run-provision"; };
            domain = { type = "app"; program = "${domainer}/bin/nix-run-domain"; };
            purge = { type = "app"; program = "${purger}/bin/nix-run-purge"; };
            default = self.apps.${system}.build-base-image;
          };

          inherit nixosConfigurations;
        };
      }
