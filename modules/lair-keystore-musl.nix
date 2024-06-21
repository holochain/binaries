{
  # Flake inputs
  inputs
  # The system that we are compiling on
, localSystem
}:
let
  inherit (inputs) nixpkgs crane rust-overlay;

  common = import ./common.nix { };

  pkgs = import nixpkgs {
    system = localSystem;
    overlays = [ (import rust-overlay) ];
  };

  rustToolchain = pkgs.rust-bin.stable.latest.minimal.override {
    targets = [ "x86_64-unknown-linux-musl" ];
  };

  craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

  lairKeystoreCommon = common.lair-keystore { inherit craneLib; lib = pkgs.lib; lair-keystore = inputs.lair-keystore; };

  commonArgs = {
    # Just used for building the workspace, will be replaced when building a specific crate
    pname = "default";
    version = "0.0.0";

    # Load source with a custom filter so we can include non-cargo files that get used during the build
    src = lairKeystoreCommon.src;

    # We don't want to run tests
    doCheck = false;

    strictDeps = true;

    nativeBuildInputs = with pkgs; [
      go
      perl
      musl
      which
    ];

    CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";
    RUSTFLAGS = "-Ctarget-feature=+crt-static -Crelocation-model=static -Cstrip=symbols";

    # Ends up requesting to link against multiple copies of musl... Not sure why that's the case
    # and should dig deeper, but this works for now
    preConfigurePhases = [ "clear" ];
    clear = ''
      unset NIX_CC_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu
      unset NIX_LDFLAGS_FOR_BUILD
    '';
  };

  # Build *just* the Cargo dependencies (of the entire workspace),
  # so we can reuse all of that work (e.g. via cachix) when running in CI
  # It is *highly* recommended to use something like cargo-hakari to avoid
  # cache misses when building individual top-level-crates
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (commonArgs // {
  pname = "lair-keystore";
  version = lairKeystoreCommon.crateInfo.version;

  inherit cargoArtifacts;

  cargoExtraArgs = "--package lair_keystore";
})
