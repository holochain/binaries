# binaries
Holochain binaries for supported platforms

## Maintainer guide

Looking after the binaries build is reasonably simple, until something breaks. The main things to look for are:
- The `versions.json` that lists a tag for each of Holochain, Kitsune2 and Lair. It is the maintainer's responsibility
  to check that the listed tags are compatible with each other.
- The `holochain` tag listed in `versions.json` is used to decide what Holochain release to publish binaries to.
- The `build.yaml` that is a multipurpose build workflow. It is used to check PRs but if run manually with `publish=true`, it 
  will also publish binaries to the `holochain` repository.
- The `check.yaml` workflow that can be run against a Holochain release. It pulls all the binaries and tries to run 
  them on the supported platforms. It prints a report at the end to let you know whether each one ran successfully.

### Publishing new binaries

This project is branched for each Holochain release. The `main` branch is for the upcoming release, the `main-*` 
branches are for released versions. Doing a bump on any branch follows the same process:
- Update the tags in `versions.json` to the desired versions.
- Create a PR and check that the `build.yaml` workflow passes.
- Merge the PR and then manually run the `build.yaml` workflow with `publish=true` to publish the binaries.
- Optionally, run the `check.yaml` workflow against the new release to verify the binaries.

Binaries are published to the corresponding [github release at `holochain/holochain`](https://github.com/holochain/holochain/releases).