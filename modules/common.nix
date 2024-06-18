{}:
{
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
}
