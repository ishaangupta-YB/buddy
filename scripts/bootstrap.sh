#!/usr/bin/env bash
#
# Generates the Xcode project for the Buddy macOS app from project.yml using XcodeGen.
#
# The committed source of truth is project.yml — the .xcodeproj is generated, not checked in,
# so it never drifts. Run this once after cloning (and again whenever project.yml changes).
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with: brew install xcodegen"
  exit 1
fi

echo "Generating Buddy.xcodeproj from project.yml…"
xcodegen generate

echo "Done. Open the project with: open Buddy.xcodeproj"
echo "Then set your signing team and press Cmd+R to build and run."
