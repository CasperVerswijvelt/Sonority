fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios certificates

```sh
[bundle exec] fastlane ios certificates
```

Create/refresh the shared iOS signing assets in the match repo

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload an iOS build to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and submit the iOS app for App Store review

----


## Mac

### mac certificates

```sh
[bundle exec] fastlane mac certificates
```

Create/refresh the shared macOS signing assets in the match repo

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Build and upload a macOS build to TestFlight

### mac release

```sh
[bundle exec] fastlane mac release
```

Build and submit the macOS app for App Store review

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
