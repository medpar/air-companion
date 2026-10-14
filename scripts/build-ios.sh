#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Set AIR_DEVELOPMENT_TEAM to your own Xcode Personal Team identifier.
# No account, phone identifier, or device key is stored in this script.
: "${AIR_DEVELOPMENT_TEAM:?Set AIR_DEVELOPMENT_TEAM to your Xcode team identifier}"
cmake_bin="${CMAKE_BIN:-cmake}"
"$cmake_bin" -S App -B .private/ios-project -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    "-DAIR_DEVELOPMENT_TEAM=$AIR_DEVELOPMENT_TEAM"
xcodebuild -project .private/ios-project/AirCompanion.xcodeproj \
    -scheme AirCompanion -configuration Debug -sdk iphoneos \
    -destination 'generic/platform=iOS' -allowProvisioningUpdates build
