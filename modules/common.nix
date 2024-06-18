{}:
{
  mkLibSodium = pkgs: pkgs.stdenv.mkDerivation {
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

  holochain = { lib, craneLib, holochain }:
    let
      # Crane filters out all non-cargo related files. Define include filter with files needed for build.
      nonCargoBuildFiles = path: _type: builtins.match ".*(json|sql|wasm.gz)$" path != null;
      includeFilesFilter = path: type:
        (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);
    in
    {
      crateInfo = crate: craneLib.crateNameFromCargoToml { cargoToml = holochain + "/crates/${crate}/Cargo.toml"; };

      src = lib.cleanSourceWith {
        src = holochain;
        filter = includeFilesFilter;
      };
    };

  lair-keystore = { lib, craneLib, lair-keystore }:
    let
      # Crane filters out all non-cargo related files. Define include filter with files needed for build.
      nonCargoBuildFiles = path: _type: builtins.match ".*(sql|md)$" path != null;
      includeFilesFilter = path: type:
        (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);
    in
    {
      crateInfo = craneLib.crateNameFromCargoToml { cargoToml = lair-keystore + "/crates/lair_keystore/Cargo.toml"; };

      src = lib.cleanSourceWith {
        src = lair-keystore;
        filter = includeFilesFilter;
      };
    };
}
