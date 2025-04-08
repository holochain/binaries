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

  bootstrapSrvCommon = common.bootstrapSrv { inherit craneLib; lib = pkgs.lib; kitsune2 = inputs.kitsune2; };

  commonArgs = {
    # Just used for building the workspace, will be replaced when building a specific crate
    pname = "default";
    version = "0.0.0";

    # Load source with a custom filter so we can include non-cargo files that get used during the build
    src = bootstrapSrvCommon.src;

    strictDeps = true;
    doCheck = false;

    CARGO_BUILD_TARGET = "x86_64-pc-windows-gnu";
    CARGO_PROFILE = "release";

    cargoExtraArgs = "--package kitsune2_bootstrap_srv";

    TARGET_CC = "${pkgs.pkgsCross.mingwW64.stdenv.cc}/bin/${pkgs.pkgsCross.mingwW64.stdenv.cc.targetPrefix}cc";

    # Otherwise the build picks up the host linker instead of the cross linker
    RUSTC_LINKER = "${pkgs.pkgsCross.mingwW64.stdenv.cc}/bin/${pkgs.pkgsCross.mingwW64.stdenv.cc.targetPrefix}cc";

    nativeBuildInputs = with pkgs; [
      perl
      nasm
      cmake
    ];

    depsBuildBuild = with pkgs; [
      pkgsCross.mingwW64.stdenv.cc
      pkgsCross.mingwW64.windows.mingw_w64_pthreads
    ];
  };

  # Build *just* the Cargo dependencies (of the entire workspace),
  # so we can reuse all of that work (e.g. via cachix) when running in CI
  # It is *highly* recommended to use something like cargo-hakari to avoid
  # cache misses when building individual top-level-crates
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (commonArgs // {
  pname = "bootstrap-srv";
  version = bootstrapSrvCommon.crateInfo.version;

  inherit cargoArtifacts;

  cargoExtraArgs = "--package kitsune2_bootstrap_srv";
})
