#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/pitgo-guincho.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sources=(
  pitgo/Features/Guincho/Model/GuinchoModels.swift
  pitgo/Features/Guincho/Model/GuinchoDTOs.swift
  pitgo/Features/Guincho/Model/GuinchoSearchResume.swift
  pitgo/Features/MobileDispatch/Model/MobileDispatchModels.swift
  pitgo/Features/MobileDispatch/Data/MobileDispatchDTOs.swift
  pitgo/Features/Guincho/Model/GuinchoInspectionModels.swift
  pitgo/Features/Ratings/Model/ServiceRatingModels.swift
)
for regression in GuinchoQuoteRegression GuinchoReservationRegression GuinchoSearchResumeRegression; do
  xcrun swiftc "${sources[@]}" "Scripts/Tests/$regression.swift" -o "$test_dir/$regression"
  "$test_dir/$regression"
done
