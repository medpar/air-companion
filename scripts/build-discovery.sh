#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .private/bin
xcrun swiftc -O Tools/AirDiscovery/main.swift -o .private/bin/air-discovery \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
  -Xlinker Tools/AirDiscovery/Info.plist
codesign --sign - --force .private/bin/air-discovery
