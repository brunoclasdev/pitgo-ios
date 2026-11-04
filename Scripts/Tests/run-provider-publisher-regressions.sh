#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/pitgo-publisher.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc \
  pitgo/Core/Location/Model/DeviceLocationModels.swift \
  pitgo/Features/ProviderTracking/Model/ProviderTrackingModels.swift \
  pitgo/Features/ProviderTracking/Repository/ProviderPublisherLeaseStore.swift \
  pitgo/Features/MobileDispatch/ProviderDiscoveryTracker.swift \
  Scripts/Tests/ProviderPublisherRegression.swift -o "$test_dir/publisher"
"$test_dir/publisher"
