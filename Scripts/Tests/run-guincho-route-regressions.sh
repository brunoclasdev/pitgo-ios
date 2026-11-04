#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/pitgo-route.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc \
  pitgo/Core/Location/Model/DeviceLocationModels.swift \
  pitgo/Features/Guincho/Model/GuinchoRouteModels.swift \
  pitgo/Features/Guincho/ViewModel/GuinchoRouteViewModel.swift \
  Scripts/Tests/GuinchoRouteRegression.swift -o "$test_dir/routes"
"$test_dir/routes"
