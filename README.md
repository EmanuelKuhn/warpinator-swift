# Warpinator for macOS and iOS

Warpinator-swift is an unoffical implementation of [Warpinator](https://github.com/linuxmint/warpinator) for macOS and iOS devices. The UI is implemented in swiftUI so that almost all code can be shared between the macOS and iOS versions.

## How to run

There are two ways to run the app:
- Build & run with XCode (macOS and iOS)
- Download warpinator-project.app.zip from the [releases tab](https://github.com/EmanuelKuhn/warpinator-swift/releases) (macOS only)

### About the warpinator-project.app.zip release
  - The release is generated from the [circleci pipeline](https://app.circleci.com/pipelines/github/EmanuelKuhn/warpinator-swift/), and can also be downloaded directly from circleci artifacts tab.
    -  e.g. at [mac_build_only (43)](https://app.circleci.com/pipelines/github/EmanuelKuhn/warpinator-swift/36/workflows/5e301756-4640-4422-8e4b-0b653afeccd8/jobs/43/artifacts).
  - The app is not code signed, and running it will give a popup that the developer can not be verified.
    - Depending on macOS version, unsigned apps can still be run.


## What works:
- [X] Receiving files:
    - [X] Single file
    - [X] Single folder
    - [X] Multiple files/folders
- [ ] Sending files:
    - [X] Single file
    - [ ] Single folder
    - [ ] Multiple files/folders
- [ ] Show received file location
    - [X] on macOS
    - [ ] on iOS (they can be found in the files app)
- [ ] Settings view (currently macOS only)
    - [X] Set groupcode
