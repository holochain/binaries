# binaries
Holochain binaries for supported platforms

## Maintainer guide

Looking after the binaries build is reasonably simple, until something breaks. The main things to look for are:
- The `flake.nix` that defines builds of `holochain`, `hc`, `hc_run_local_services`, `hcterm` and `lair-keystore` for 
  Windows, macOS (Intel and Apple Silicon) and Linux.
- The `flake.nix` also defines Nix bundles for each of these binaries, which depend on Holonix.
- The `build.yaml` that is a multi-purpose build workflow. It is used to check PRs but if run manually with a tag, it 
  will also publish binaries to the `holochain` repository.
- The `check.yaml` workflow that can be run against a Holochain release. It pulls all the binaries and tries to run 
  them on the supported platforms. It prints a report at the end to let you know whether each one ran successfully.

### Publishing new binaries

This project is branched for each Holochain release. The `main` branch is for the upcoming release, the `main-*` 
branches are for released versions. Doing a bump on any branch follows the same process:
- Update Holonix first. This repository takes Holonix as an input to build bundles so that must be done first.
- Update the `flake.nix` to point to the new Holochain version by tag, and update Lair if necessary.
- Run `nix flake update` to update the lock file with the new Holochain, Lair and Holonix versions.
- Create a branch, commit and push the changes.
- Open a PR to the appropriate base branch. This will use `build.yaml` to verify that everything builds. This takes a 
  while but the results are cached!
- If everything looks good, merge the PR and go to the Actions tab in GitHub. Find the `Build` workflow and run it 
  manually with the tag of the new Holochain version. This will build the binaries and publish them to the associated
  release on the`holochain` repository.
- Once the binaries are published, you can run the `check` workflow against the same version tag to make sure everything 
  works as expected. This is not absolutely necessary and it should probably be automated at some point, but it's a good
  idea to check at least on release branches.
