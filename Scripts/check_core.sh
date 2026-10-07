#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CHECK_DIR=$(mktemp -d /tmp/grtransfer-checks.XXXXXX)
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -parse GRTransfer/Core/*.swift GRTransfer/Services/*.swift GRTransfer/App/*.swift GRTransfer/Views/*.swift
swiftc -module-cache-path "$CHECK_DIR/modules" -o "$CHECK_DIR/checks" GRTransfer/Core/*.swift Tests/GRCoreTests/Scenarios.swift Tests/Support/CheckRunner.swift
python3 Scripts/http_checks.py "$CHECK_DIR/checks"
plutil -lint GRTransfer.xcodeproj/project.pbxproj GRTransfer/Resources/Info.plist GRTransfer/Resources/GRTransfer.entitlements GRTransfer/Resources/PrivacyInfo.xcprivacy
