{
  description = "Utility for producing Holochain binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    holochain = {
      url = "github:holochain/holochain/bump-influxive";
      flake = false;
    };

    lair-keystore = {
      url = "github:holochain/lair";
      flake = false;
    };

    holonix = {
      url = "github:holochain/holonix";
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
              "${package}_x86_64-apple" = import ./modules/holochain-cross.nix {
                inherit localSystem inputs crate package;
                crossSystem = "x86-64-darwin";
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
              lair_keystore_x86_64-apple = import ./modules/lair-keystore-cross.nix {
                inherit localSystem inputs;
                crossSystem = "x86_64-darwin";
                rustTargetTriple = "x86_64-apple-darwin";
              };
            } else { });

            extractHolochainBin = bin: pkgs.stdenv.mkDerivation {
              name = bin;
              unpackPhase = "true";
              installPhase = ''
                mkdir -p $out/bin
                cp ${inputs.holonix.packages.${localSystem}.holochain}/bin/${bin} $out/bin
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
            holonix_lair_keystore = inputs.holonix.packages.${localSystem}.lair-keystore;
          } else { })
        ;
      }) // {
      # Add dev helpers that are not required to be platform agnostic
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
    };
}
