{
  description = "Utility for producing Holochain binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=24.05";

    crane = {
      url = "github:ipetkov/crane";
    };

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    holochain = {
      url = "github:holochain/holochain/?ref=holochain-0.4.0-rc.1";
      flake = false;
    };

    lair-keystore = {
      url = "github:holochain/lair/lair_keystore-v0.5.2";
      flake = false;
    };

    holonix = {
      url = "github:holochain/holonix?ref=main-0.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.crane.follows = "crane";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.holochain.follows = "holochain";
      inputs.lair-keystore.follows = "lair-keystore";
    };
  };

  outputs = inputs @ { nixpkgs, crane, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem
      (localSystem: {
        formatter = nixpkgs.legacyPackages.${localSystem}.nixpkgs-fmt;

        packages =
          let
            pkgs = nixpkgs.legacyPackages.${localSystem};

            defineHolochainPackages = { crate, package }: {
              "${package}_aarch64-linux" = import ./modules/holochain-cross.nix {
                inherit localSystem inputs crate package;
                crossSystem = "aarch64-linux";
                rustTargetTriple = "aarch64-unknown-linux-gnu";
              };
              "${package}_x86_64-linux" = import ./modules/holochain-cross.nix {
                inherit localSystem inputs crate package;
                crossSystem = "x86_64-linux";
                rustTargetTriple = "x86_64-unknown-linux-gnu";
              };
              "${package}_x86_64-windows" = import ./modules/holochain-windows.nix {
                inherit localSystem inputs crate package;
              };
            } // (if localSystem == "aarch64-darwin" then {
              # Only define darwin builds if we're on a darwin host because Apple don't like people cross compiling
              # from other systems.
              "${package}_aarch64-apple" = import ./modules/holochain-cross.nix {
                inherit localSystem inputs crate package;
                crossSystem = "aarch64-darwin";
                rustTargetTriple = "aarch64-apple-darwin";
              };
            } else if localSystem == "x86_64-darwin" then {
              "${package}_x86_64-apple" = import ./modules/holochain-cross.nix {
                inherit localSystem inputs crate package;
                crossSystem = "x86_64-darwin";
                rustTargetTriple = "x86_64-apple-darwin";
              };
            } else { });

            defineLairKeystorePackages = {}: {
              lair_keystore_aarch64-linux = import ./modules/lair-keystore-cross.nix {
                inherit localSystem inputs;
                crossSystem = "aarch64-linux";
                rustTargetTriple = "aarch64-unknown-linux-gnu";
              };
              lair_keystore_x86_64-linux = import ./modules/lair-keystore-cross.nix {
                inherit localSystem inputs;
                crossSystem = "x86_64-linux";
                rustTargetTriple = "x86_64-unknown-linux-gnu";
              };
              lair_keystore_x86_64-windows = import ./modules/lair-keystore-windows.nix {
                inherit localSystem inputs;
              };
            } // (if localSystem == "aarch64-darwin" then {
              # Only define darwin builds if we're on a darwin host because Apple don't like people cross compiling
              # from other systems.
              lair_keystore_aarch64-apple = import ./modules/lair-keystore-cross.nix {
                inherit localSystem inputs;
                crossSystem = "aarch64-darwin";
                rustTargetTriple = "aarch64-apple-darwin";
              };

            } else if localSystem == "x86_64-darwin" then {
              lair_keystore_x86_64-apple = import ./modules/lair-keystore-cross.nix {
                inherit localSystem inputs;
                crossSystem = "x86_64-darwin";
                rustTargetTriple = "x86_64-apple-darwin";
              };
            } else { });

            extractHolochainBin = bin: pkgs.stdenv.mkDerivation {
              pname = bin;
              version = inputs.holonix.packages.${localSystem}.holochain.version;
              meta = {
                mainProgram = bin;
              };
              unpackPhase = "true";
              installPhase = ''
                mkdir -p $out/bin
                cp ${inputs.holonix.packages.${localSystem}.holochain}/bin/${bin} $out/bin
              '';
            };

            lairKeystoreDrv = pkgs.stdenv.mkDerivation {
              pname = "lair-keystore";
              version = inputs.holonix.packages.${localSystem}.lair-keystore.version;
              meta = {
                mainProgram = "lair-keystore";
              };
              unpackPhase = "true";
              installPhase = ''
                mkdir -p $out/bin
                cp ${inputs.holonix.packages.${localSystem}.lair-keystore}/bin/lair-keystore $out/bin/
              '';
            };
          in
          (defineHolochainPackages { crate = "holochain"; package = "holochain"; }) //
          (defineHolochainPackages { crate = "hc"; package = "holochain_cli"; }) //
          (defineHolochainPackages { crate = "hc_run_local_services"; package = "holochain_cli_run_local_services"; }) //
          (defineHolochainPackages { crate = "holochain_terminal"; package = "hcterm"; }) //
          (defineLairKeystorePackages { }) // (if localSystem == "x86_64-linux" then {
            holonix_holochain = extractHolochainBin "holochain";
            holonix_hc = extractHolochainBin "hc";
            holonix_hc_run_local_services = extractHolochainBin "hc-run-local-services";
            holonix_hcterm = extractHolochainBin "hcterm";
            holonix_lair_keystore = lairKeystoreDrv;
          } else { })
        ;

        devShells.default =
          let
            pkgs = nixpkgs.legacyPackages.${localSystem};
          in
          pkgs.mkShell {
            packages = (with pkgs; [
              patchelf
            ]);
          };
      });
}
