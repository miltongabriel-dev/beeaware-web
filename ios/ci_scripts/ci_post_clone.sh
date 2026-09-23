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
# Pinned to this project's own .metadata revision, not a floating
# `-b stable` HEAD. A previous "Module 'sign_in_with_apple' not found"
# Archive failure (2026-09-14) was root-caused and fixed as a wrong
# relative path in ios/Flutter/{Debug,Release}.xcconfig (see git blame on
# those files) — but the same error recurred later with that fix still
# intact on disk, and `stable` is a moving target: every fresh Xcode
# Cloud run could silently pick up a newer Flutter SDK than whatever
# last built successfully, with no way to tell from the build log alone
# that the toolchain itself changed. Checking out the exact revision
# `flutter create`/`flutter upgrade` last wrote to .metadata makes local
# builds and Xcode Cloud builds use the identical SDK deterministically.
# Still a single-commit shallow fetch (same network/disk cost as the old
# `-b stable --depth 1` clone) — `git fetch --depth 1 origin <sha>` then
# checking out FETCH_HEAD gets exactly the pinned commit without needing
# flutter/flutter's full history, which a plain `git clone` + `checkout
# <sha>` would require.
FLUTTER_PINNED_REVISION="$(grep 'revision:' "$CI_PRIMARY_REPOSITORY_PATH/.metadata" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
if [ -z "$FLUTTER_PINNED_REVISION" ]; then
  echo "ERROR: could not read a Flutter revision out of $CI_PRIMARY_REPOSITORY_PATH/.metadata" >&2
  exit 1
fi
echo "Pinning Flutter SDK to revision $FLUTTER_PINNED_REVISION"

# rm -rf first: Xcode Cloud can carry $HOME over between builds via its
# own dependency caching, so $HOME/flutter may already exist (and already
# have an `origin` remote) from a previous run -- `git init` alone is a
# harmless no-op on an existing repo, but the `remote add` right after it
# is NOT idempotent and errors out ("remote origin already exists") on a
# second run, which is exactly the kind of failure `set -e` turns into an
# opaque "ci_post_clone.sh exited with code 1" with no line number shown
# in Xcode Cloud's own summary. Wiping first guarantees a clean git init
# every time regardless of what the runner carried over.
rm -rf "$HOME/flutter"
git init -q "$HOME/flutter"
git -C "$HOME/flutter" remote add origin https://github.com/flutter/flutter.git
git -C "$HOME/flutter" fetch --depth 1 origin "$FLUTTER_PINNED_REVISION"
git -C "$HOME/flutter" checkout FETCH_HEAD
export PATH="$PATH:$HOME/flutter/bin"

flutter doctor
flutter precache --ios

cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

cd ios
pod install
