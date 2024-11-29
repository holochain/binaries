{
  # Flake inputs
  inputs
  # The system that we are compiling on
, localSystem
  # The target system that we are cross-compiling for
, crossSystem
  # The target that Rust should be configured to use
, rustTargetTriple
, ...
}:
let
  inherit (inputs) nixpkgs crane rust-overlay;

  common = import ./common.nix { };

  pkgs = import nixpkgs {
    inherit crossSystem localSystem;
    overlays = [ (import rust-overlay) ];
  };

  craneLib = (crane.mkLib pkgs).overrideToolchain (pkgs: pkgs.rust-bin.stable.${common.rustVersion}.minimal.override {
    targets = [ rustTargetTriple ];
  });

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
    { lib
    , pkg-config
    , go
    , perl
    , stdenv
    }:
    let
      lairKeystoreCommon = common.lair-keystore { inherit lib craneLib; lair-keystore = inputs.lair-keystore; };

      commonArgs = {
        # Just used for building the workspace, will be replaced when building a specific crate
        pname = "default";
        version = "0.0.0";

        # Load source with a custom filter so we can include non-cargo files that get used during the build
        src = lairKeystoreCommon.src;

        # We don't want to run tests
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
          perl
        ];

        buildInputs = [ ] ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [
          # additional packages needed for darwin platforms
          pkgs.darwin.apple_sdk.frameworks.Security
          pkgs.darwin.libobjc
        ]);

        # Tell cargo about the linker and an optional emulater. So they can be used in `cargo build`
        # and `cargo run`.
        # Environment variables are in format `CARGO_TARGET_<UPPERCASE_UNDERSCORE_RUST_TRIPLE>_LINKER`.
        # They are also be set in `.cargo/config.toml` instead.
        # See: https://doc.rust-lang.org/cargo/reference/config.html#target
        CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = "${stdenv.cc.targetPrefix}cc";
        CARGO_TARGET_AARCH64_UNKNOWN_APPLE_LINKER = "${stdenv.cc.targetPrefix}cc";
        CARGO_PROFILE = "release";

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

      cargoExtraArgs = "${commonArgs.cargoExtraArgs} --package lair_keystore";
    });
in
# Dispatch the crate expression to run the cross compile
pkgs.callPackage crateExpression { }
