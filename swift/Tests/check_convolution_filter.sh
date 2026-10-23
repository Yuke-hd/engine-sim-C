#!/bin/bash
# Checks the vectorized ConvolutionFilter::f against a scalar reference.
# On Apple silicon this also builds an x86_64 binary to cover the scalar path.
set -euo pipefail
cd "$(dirname "$0")/../.."
out_dir=$(mktemp -d)
trap 'rm -rf "$out_dir"' EXIT
build_and_run() {
    clang++ -std=c++17 -O2 -Wno-inconsistent-missing-override -I include "$@" swift/Tests/ConvolutionFilter/main.cpp \
        src/convolution_filter.cpp src/filter.cpp -o "$out_dir/convolution_filter_test"
    "$out_dir/convolution_filter_test"
}
build_and_run
if [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] && arch -x86_64 /usr/bin/true 2>/dev/null; then
    echo "-- x86_64 (scalar fallback)"
    build_and_run -arch x86_64
fi
