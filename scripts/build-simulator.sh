#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
"${CMAKE_BIN:-cmake}" -S App -B .private/simulator-project -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
xcodebuild -project .private/simulator-project/AirCompanion.xcodeproj \
    -scheme AirCompanion -configuration Debug -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
