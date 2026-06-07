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

### ios test

```sh
[bundle exec] fastlane ios test
```

Run tests on iPhone 17 simulator

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight (local archive fallback; CI uses Xcode Cloud)

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Generate App Store screenshots via snapshot

### ios rollback

```sh
[bundle exec] fastlane ios rollback
```

Roll back the public TestFlight group to a prior processed build (VOL-178)

### ios release

```sh
[bundle exec] fastlane ios release
```

Submit to App Store review

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
