{ inputs, localSystem, crate, package }:
let
  inherit (inputs) nixpkgs crane fenix;

  pkgs = nixpkgs.legacyPackages.${localSystem};

  toolchain = with fenix.packages.${localSystem};
    combine [
      minimal.rustc
      minimal.cargo
      targets.x86_64-pc-windows-gnu.latest.rust-std
    ];

  craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;

  # Crane filters out all non-cargo related files. Define include filter with files needed for build.
  nonCargoBuildFiles = path: _type: builtins.match ".*(json|sql|wasm.gz)$" path != null;
  includeFilesFilter = path: type:
    (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);

  # Crane doesn't know which version to select from a workspace, so we tell it where to look
  crateInfo = craneLib.crateNameFromCargoToml { cargoToml = inputs.holochain + "/crates/${crate}/Cargo.toml"; };

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
in
craneLib.buildPackage {
  pname = package;
  version = crateInfo.version;
  src = pkgs.lib.cleanSourceWith {
    src = inputs.holochain;
    filter = includeFilesFilter;
  };

  strictDeps = true;
  doCheck = false;

  CARGO_BUILD_TARGET = "x86_64-pc-windows-gnu";

  # fixes issues related to libring
  TARGET_CC = "${pkgs.pkgsCross.mingwW64.stdenv.cc}/bin/${pkgs.pkgsCross.mingwW64.stdenv.cc.targetPrefix}cc";

  # Otherwise tx5-go-pion-sys picks up the host linker instead of the cross linker
  RUSTC_LINKER = "${pkgs.pkgsCross.mingwW64.stdenv.cc}/bin/${pkgs.pkgsCross.mingwW64.stdenv.cc.targetPrefix}cc";

  SODIUM_LIB_DIR = "${libsodium}/lib";

  # OPENSSL_NO_VENDOR = "1";

  nativeBuildInputs = with pkgs; [
    go
    perl
  ];

  depsBuildBuild = with pkgs; [
    pkgsCross.mingwW64.stdenv.cc
    pkgsCross.mingwW64.windows.pthreads
  ];

  cargoExtraArgs = "--package ${package}";
}

