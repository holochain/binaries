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

  holochainCommon = common.holochain { inherit craneLib; lib = pkgs.lib; holochain = inputs.holochain; };

  # Crane doesn't know which version to select from a workspace, so we tell it where to look
  crateInfo = holochainCommon.crateInfo crate;

  libsodium = pkgs.stdenv.mkDerivation {
    name = "libsodium";
    src = builtins.fetchurl {
      url = "https://download.libsodium.org/libsodium/releases/libsodium-1.0.20-mingw.tar.gz";
      sha256 = "sha256:09npqqrialraf2v4m6cicvhnj52p8jaya349wnzlklp31b0q3yq1";
    };
    unpackPhase = "true";
    postInstall = ''
      tar -xvf $src
      mkdir -p $out
      cp -r libsodium-win64/* $out
    '';
  };

  commonArgs = {
    # Just used for building the workspace, will be replaced when building a specific crate
    pname = "default";
    version = "0.0.0";

    # Load source with a custom filter so we can include non-cargo files that get used during the build
    src = holochainCommon.src;

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
      go
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
  pname = package;
  version = crateInfo.version;

  inherit cargoArtifacts;

  cargoExtraArgs = "--package ${package}";
})
