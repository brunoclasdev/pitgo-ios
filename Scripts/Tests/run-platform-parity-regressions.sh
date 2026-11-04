#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/pitgo-parity.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc \
  pitgo/Features/ProviderTracking/Data/ProviderLocationDTOs.swift \
  pitgo/Features/Store/StorePrice.swift \
  pitgo/Features/Payment/Model/PaymentModels.swift \
  pitgo/Features/Payment/Model/PaymentHistoryRecord.swift \
  Scripts/Tests/PlatformParityRegression.swift -o "$test_dir/contracts"
"$test_dir/contracts"
xcrun swiftc \
  pitgo/Features/Payment/Model/PaymentModels.swift \
  pitgo/Features/Payment/Data/PaymentDTOs.swift \
  pitgo/Features/PaymentMethods/Model/SavedCardModels.swift \
  pitgo/Features/Payment/ViewModel/PaymentCheckoutViewModel.swift \
  Scripts/Tests/PaymentCheckoutRegression.swift -o "$test_dir/checkout"
"$test_dir/checkout"
xcrun swiftc \
  pitgo/Features/ProviderTracking/Data/ProviderLocationDTOs.swift \
  pitgo/Features/AppointmentTracking/Model/AppointmentTrackingModels.swift \
  pitgo/Features/AppointmentTracking/ViewModel/AppointmentTrackingViewModel.swift \
  Scripts/Tests/AppointmentTrackingParityRegression.swift -o "$test_dir/tracking"
"$test_dir/tracking"
xcrun swiftc \
  pitgo/Features/Guincho/Model/GuinchoModels.swift \
  pitgo/Features/Guincho/Model/GuinchoDTOs.swift \
  pitgo/Features/Guincho/Model/GuinchoSearchResume.swift \
  pitgo/Features/MobileDispatch/Model/MobileDispatchModels.swift \
  pitgo/Features/MobileDispatch/Data/MobileDispatchDTOs.swift \
  pitgo/Features/Guincho/Model/GuinchoInspectionModels.swift \
  pitgo/Features/Ratings/Model/ServiceRatingModels.swift \
  pitgo/Features/Payment/Model/PaymentModels.swift \
  pitgo/Features/MobileDispatch/ViewModel/ClientMobileDispatchViewModel.swift \
  Scripts/Tests/ClientDispatchRefreshRegression.swift -o "$test_dir/dispatch"
"$test_dir/dispatch"
xcrun swiftc \
  pitgo/Features/Guincho/Model/GuinchoModels.swift \
  pitgo/Features/Guincho/Model/GuinchoDTOs.swift \
  pitgo/Features/Guincho/Model/GuinchoSearchResume.swift \
  pitgo/Features/MobileDispatch/Model/MobileDispatchModels.swift \
  pitgo/Features/MobileDispatch/Data/MobileDispatchDTOs.swift \
  pitgo/Features/Guincho/Model/GuinchoInspectionModels.swift \
  pitgo/Features/Ratings/Model/ServiceRatingModels.swift \
  pitgo/Features/MobileDispatch/ViewModel/ProviderIncomingRequestViewModel.swift \
  Scripts/Tests/ProviderStartTransportRegression.swift -o "$test_dir/provider-start"
"$test_dir/provider-start"
