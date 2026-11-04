#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/pitgo-inspection.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
model=pitgo/Features/Guincho/Model/GuinchoInspectionModels.swift
xcrun swiftc "$model" pitgo/Features/Guincho/Model/GuinchoInspectionCapturePipeline.swift \
  Scripts/Tests/GuinchoInspectionCaptureRegression.swift -o "$test_dir/pipeline"
"$test_dir/pipeline"
xcrun swiftc "$model" Scripts/Tests/GuinchoInspectionReadRegression.swift -o "$test_dir/read"
"$test_dir/read"
simulator_id=${1:-booted}
simulator_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
simulator_arch=$(uname -m)
xcrun swiftc -sdk "$simulator_sdk" -target "$simulator_arch-apple-ios16.0-simulator" \
  "$model" pitgo/Features/Guincho/Model/GuinchoInspectionImageEncoder.swift \
  pitgo/Features/Guincho/Data/GuinchoInspectionCaptureStore.swift \
  Scripts/Tests/GuinchoInspectionImageRegression.swift -o "$test_dir/images"
xcrun simctl spawn "$simulator_id" "$test_dir/images"
