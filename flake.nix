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
        packages = {
          holochain_aarch64-linux = import ./modules/holochain-cross.nix {
            inherit localSystem inputs;
            crate = "holochain";
            package = "holochain";
            crossSystem = "aarch64-linux";
            rustTargetTriple = "aarch64-unknown-linux-gnu";
          };
          holochain_x86_64-linux = import ./modules/holochain-cross.nix {
            inherit localSystem inputs;
            crate = "holochain";
            package = "holochain";
            crossSystem = "x86_64-linux";
            rustTargetTriple = "x86_64-unknown-linux-gnu";
          };
          holochain_x86_64-windows = import ./modules/holochain-windows.nix {
            inherit localSystem inputs;
            crate = "holochain";
            package = "holochain";
          };
        } // (if localSystem == "aarch64-darwin" then {
          holochain_aarch64-apple = import ./modules/holochain-cross.nix {
            inherit localSystem inputs;
            crate = "holochain";
            package = "holochain";
            crossSystem = "aarch64-darwin";
            rustTargetTriple = "aarch64-apple-darwin";
          };
        } else { });
      }) // {
      # Add dev helpers that are not required to be platform agnostic
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
    };
}
