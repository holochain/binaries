{
  # Flake inputs
  inputs
  # The system that we are compiling on
, localSystem
}:
let
  inherit (inputs) nixpkgs crane fenix;

  common = import ./common.nix { };

  pkgs = nixpkgs.legacyPackages.${localSystem};

  toolchain = with fenix.packages.${localSystem};
    combine [
      minimal.rustc
      minimal.cargo
      targets.x86_64-pc-windows-gnu.latest.rust-std
    ];

  craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;

  lairKeystoreCommon = common.lair-keystore { inherit craneLib; lib = pkgs.lib; lair-keystore = inputs.lair-keystore; };

  libsodium = common.mkLibSodium pkgs;

  commonArgs = {
    # Just used for building the workspace, will be replaced when building a specific crate
    pname = "default";
    version = "0.0.0";

    # Load source with a custom filter so we can include non-cargo files that get used during the build
    src = lairKeystoreCommon.src;

    strictDeps = true;
    doCheck = false;

    CARGO_BUILD_TARGET = "x86_64-pc-windows-gnu";
    CARGO_PROFILE="release";

    # fixes issues related to libring
    TARGET_CC = "${pkgs.pkgsCross.mingwW64.stdenv.cc}/bin/${pkgs.pkgsCross.mingwW64.stdenv.cc.targetPrefix}cc";

    # Otherwise tx5-go-pion-sys picks up the host linker instead of the cross linker
    RUSTC_LINKER = "${pkgs.pkgsCross.mingwW64.stdenv.cc}/bin/${pkgs.pkgsCross.mingwW64.stdenv.cc.targetPrefix}cc";

    SODIUM_LIB_DIR = "${libsodium}/lib";

    nativeBuildInputs = with pkgs; [
      perl
    ];

    depsBuildBuild = with pkgs; [
      pkgsCross.mingwW64.stdenv.cc
      pkgsCross.mingwW64.windows.pthreads
    ];
  };

  # Build *just* the Cargo dependencies (of the entire workspace),
  # so we can reuse all of that work (e.g. via cachix) when running in CI
  # It is *highly* recommended to use something like cargo-hakari to avoid
  # cache misses when building individual top-level-crates
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (commonArgs // {
  pname = "lair_keystore";
  version = lairKeystoreCommon.crateInfo.version;

  inherit cargoArtifacts;

  cargoExtraArgs = "--package lair_keystore";
})
