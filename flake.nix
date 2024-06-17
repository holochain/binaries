{
  description = "Utility for producing Holochain binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    holochain = {
      url = "github:holochain/holochain/bump-influxive";
      flake = false;
    };
  };

  outputs = inputs @ { nixpkgs, crane, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem
      (localSystem:
        let
          # The target we are cross-compiling for.
          crossSystem = "aarch64-linux";

          pkgs = import nixpkgs {
            inherit crossSystem localSystem;
            overlays = [ (import rust-overlay) ];
          };

          rustToolchain = pkgs.pkgsBuildHost.rust-bin.stable.latest.default.override {
            targets = [ "aarch64-unknown-linux-gnu" ];
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
            { openssl
            , libiconv
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
              crateInfo = craneLib.crateNameFromCargoToml { cargoToml = inputs.holochain + "/crates/holochain/Cargo.toml"; };
            in
            craneLib.buildPackage {
              pname = "holochain";
              version = crateInfo.version;
              src = pkgs.lib.cleanSourceWith {
                src = inputs.holochain;
                filter = includeFilesFilter;
              };

              strictDeps = true;
              doCheck = false;

              # Build-time tools which are target agnostic. build = host = target = your-machine.
              # Emulators should essentially also go `nativeBuildInputs`. But with some packaging issue,
              # currently it would cause some rebuild.
              # We put them here just for a workaround.
              # See: https://github.com/NixOS/nixpkgs/pull/146583
              depsBuildBuild = [
                qemu
              ];

              # Dependencies which need to be build for the current platform
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
                openssl
              ];

              # Tell cargo about the linker and an optional emulater. So they can be used in `cargo build`
              # and `cargo run`.
              # Environment variables are in format `CARGO_TARGET_<UPPERCASE_UNDERSCORE_RUST_TRIPLE>_LINKER`.
              # They are also be set in `.cargo/config.toml` instead.
              # See: https://doc.rust-lang.org/cargo/reference/config.html#target
              CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = "${stdenv.cc.targetPrefix}cc";
              CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUNNER = "qemu-aarch64";

              # Tell cargo which target we want to build (so it doesn't default to the build system).
              # We can either set a cargo flag explicitly with a flag or with an environment variable.
              cargoExtraArgs = "--target aarch64-unknown-linux-gnu";
              # CARGO_BUILD_TARGET = "aarch64-unknown-linux-gnu";

              # These environment variables may be necessary if any of your dependencies use a
              # build-script which invokes the `cc` crate to build some other code. The `cc` crate
              # should automatically pick up on our target-specific linker above, but this may be
              # necessary if the build script needs to compile and run some extra code on the build
              # system.
              HOST_CC = "${stdenv.cc.nativePrefix}cc";
              TARGET_CC = "${stdenv.cc.targetPrefix}cc";
            };

          # Assuming the above expression was in a file called myCrate.nix
          # this would be defined as:
          # my-crate = pkgs.callPackage ./myCrate.nix { };
          my-crate = pkgs.callPackage crateExpression { };
        in
        {
          checks = {
            inherit my-crate;
          };

          packages.default = my-crate;

          apps.default = flake-utils.lib.mkApp {
            drv = pkgs.writeScriptBin "my-app" ''
              ${pkgs.pkgsBuildBuild.qemu}/bin/qemu-aarch64 ${my-crate}/bin/cross-rust-overlay
            '';
          };
        }) // {
      # Add dev helpers that are not required to be platform agnostic
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
    };
}
