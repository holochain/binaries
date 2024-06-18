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
  };

  outputs = inputs @ { nixpkgs, crane, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem
      (localSystem: {
        packages =
          let
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
            } else { });
          in
          (defineHolochainPackages { crate = "holochain"; package = "holochain"; }) //
          (defineHolochainPackages { crate = "hc"; package = "holochain_cli"; }) //
          (defineHolochainPackages { crate = "hc_run_local_services"; package = "holochain_cli_run_local_services"; }) //
          (defineHolochainPackages { crate = "holochain_terminal"; package = "hcterm"; })
        ;
      }) // {
      # Add dev helpers that are not required to be platform agnostic
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
    };
}
