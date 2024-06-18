{
  # Flake inputs
  inputs
  # The system that we are compiling on
, localSystem
  # The crate to build, from the Holochain workspace. Must match the path to the Cargo.toml file.
, crate
  # The name of the package to build, from the selected crate.
, package
}:
let
  inherit (inputs) nixpkgs crane rust-overlay;

  common = import ./common.nix { };

  pkgs = import nixpkgs {
    inherit localSystem;
    overlays = [ (import rust-overlay) ];
  };

  rustToolchain = pkgs.rust-bin.stable.latest.minimal.override {
    targets = [ "x86_64-unknown-linux-musl" ];
  };

  craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

  holochainCommon = common.holochain { inherit craneLib; lib = pkgs.lib; holochain = inputs.holochain; };

  # Crane doesn't know which version to select from a workspace, so we tell it where to look
  crateInfo = holochainCommon.crateInfo crate;

  commonArgs = {
    # Just used for building the workspace, will be replaced when building a specific crate
    pname = "default";
    version = "0.0.0";

    # Load source with a custom filter so we can include non-cargo files that get used during the build
    src = holochainCommon.src;

    # We don't want to run tests
    doCheck = false;

    strictDeps = true;

    nativeBuildInputs = with pkgs; [
      go
      perl
      musl
    ];

    CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";
    CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static";
    TARGET_CC = "${pkgs.musl}/bin/musl-gcc";
    CC = "${pkgs.musl}/bin/musl-gcc";
  };

  # Build *just* the Cargo dependencies (of the entire workspace),
  # so we can reuse all of that work (e.g. via cachix) when running in CI
  # It is *highly* recommended to use something like cargo-hakari to avoid
  # cache misses when building individual top-level-crates
  # cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (commonArgs // {
  pname = package;
  version = crateInfo.version;

  # inherit cargoArtifacts;

  cargoExtraArgs = "--package ${package}";
})
