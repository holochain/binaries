{
  # Flake inputs
  inputs

, # The system that we are compiling on
  localSystem

  # The crate to build, from the Holochain workspace. Must match the path to the Cargo.toml file.
, crate

  # The name of the package to build, from the selected crate.
, package

, #
  # The remaining arguments are for configuring the cross-compile.
  #

  # The target system that we are cross-compiling for
  crossSystem
, # The target that Rust should be configured to use
  rustTargetTriple
, ...
}:
let
  inherit (inputs) nixpkgs crane rust-overlay;

  pkgs = import nixpkgs {
    inherit crossSystem localSystem;
    overlays = [ (import rust-overlay) ];
  };

  rustToolchain = pkgs.pkgsBuildHost.rust-bin.stable.latest.default.override {
    targets = [ rustTargetTriple ];
  };

  craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

  # Note: we have to use the `callPackage` approach here so that Nix
  # can "splice" the packages in such a way that dependencies are
  # compiled for the appropriate targets. If we did not do this, we
  # would have to manually specify things like
  # `nativeBuildInputs = with pkgs.pkgsBuildHost; [ someDep ];` or
  # `buildInputs = with pkgs.pkgsHostHost; [ anotherDep ];`.
  #
  # Normally you can stick this function into its own file and pass
  # its path to `callPackage`.
  crateExpression =
    { libiconv
    , lib
    , pkg-config
    , go
    , perl
    , qemu
    , stdenv
    }:
    let
      # Crane filters out all non-cargo related files. Define include filter with files needed for build.
      nonCargoBuildFiles = path: _type: builtins.match ".*(json|sql|wasm.gz)$" path != null;
      includeFilesFilter = path: type:
        (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);

      # Crane doesn't know which version to select from a workspace, so we tell it where to look
      crateInfo = craneLib.crateNameFromCargoToml { cargoToml = inputs.holochain + "/crates/${crate}/Cargo.toml"; };

      commonArgs =
        let
          # Crane filters out all non-cargo related files. Define include filter with files needed for build.
          nonCargoBuildFiles = path: _type: builtins.match ".*(json|sql|wasm.gz)$" path != null;
          includeFilesFilter = path: type:
            (craneLib.filterCargoSources path type) || (nonCargoBuildFiles path type);
        in
        {
          # Just used for building the workspace, will be replaced when building a specific crate
          pname = "default";
          version = "0.0.0";

          src = pkgs.lib.cleanSourceWith {
            src = inputs.holochain;
            filter = includeFilesFilter;
          };
          doCheck = false;
          strictDeps = true;

          # Dependencies which need to be built for the current platform
          # on which we are doing the cross compilation. In this case,
          # pkg-config needs to run on the build platform so that the build
          # script can find the location of openssl. Note that we don't
          # need to specify the rustToolchain here since it was already
          # overridden above.
          nativeBuildInputs = [
            pkg-config
            stdenv.cc
            go
            perl
          ] ++ lib.optionals stdenv.buildPlatform.isDarwin [
            libiconv
          ];

          # Dependencies which need to be built for the platform on which
          # the binary will run. In this case, we need to compile openssl
          # so that it can be linked with our executable.
          buildInputs = [
            # Add additional build inputs here
          ];

          # Tell cargo about the linker and an optional emulater. So they can be used in `cargo build`
          # and `cargo run`.
          # Environment variables are in format `CARGO_TARGET_<UPPERCASE_UNDERSCORE_RUST_TRIPLE>_LINKER`.
          # They are also be set in `.cargo/config.toml` instead.
          # See: https://doc.rust-lang.org/cargo/reference/config.html#target
          CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = "${stdenv.cc.targetPrefix}cc";
          CARGO_TARGET_x86_64_UNKNOWN_LINUX_GNU_LINKER = "${stdenv.cc.targetPrefix}cc";
          CARGO_TARGET_AARCH64_UNKNOWN_APPLE_LINKER = "${stdenv.cc.targetPrefix}cc";

          # Tell cargo which target we want to build (so it doesn't default to the build system).
          cargoExtraArgs = "--target ${rustTargetTriple}";

          # These environment variables may be necessary if any of your dependencies use a
          # build-script which invokes the `cc` crate to build some other code. The `cc` crate
          # should automatically pick up on our target-specific linker above, but this may be
          # necessary if the build script needs to compile and run some extra code on the build
          # system.
          HOST_CC = "${stdenv.cc.nativePrefix}cc";
          TARGET_CC = "${stdenv.cc.targetPrefix}cc";
        };

      # Build *just* the cargo dependencies (of the entire workspace),
      # so we can reuse all of that work (e.g. via cachix) when running in CI
      # It is *highly* recommended to use something like cargo-hakari to avoid
      # cache misses when building individual top-level-crates
      cargoArtifacts = craneLib.buildDepsOnly commonArgs;
    in
    craneLib.buildPackage (commonArgs // {
      pname = package;
      version = crateInfo.version;

      inherit cargoArtifacts;

      cargoExtraArgs = "${commonArgs.cargoExtraArgs} --package ${package}";
    });
in
# Assuming the above expression was in a file called myCrate.nix
  # this would be defined as:
  # my-crate = pkgs.callPackage ./myCrate.nix { };
pkgs.callPackage crateExpression { }
