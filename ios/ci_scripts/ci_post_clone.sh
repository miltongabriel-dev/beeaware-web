#!/bin/bash
set -e

# Xcode Cloud runs this automatically right after cloning the repo, before
# xcodebuild starts. It clones onto a clean machine with no Flutter SDK and
# none of Flutter's generated build artifacts -- in particular
# ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage, which
# the Xcode project references as a local Swift Package dependency but which
# only gets created by running Flutter tooling. That folder is correctly
# gitignored (it's a build output, not source), so without this script
# xcodebuild fails immediately at package resolution because the folder was
# never generated on the build machine.

echo "Installing Flutter..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

flutter doctor
flutter precache --ios

cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

cd ios
pod install
