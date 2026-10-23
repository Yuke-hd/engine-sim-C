#!/bin/bash
# Host-only diagnostic. Physical thresholds require the signed iOS benchmark app.
set -euo pipefail
cd "$(dirname "$0")/../../.."
output=${1:?Usage: bash swift/Benchmarks/PhysicsCost/run.sh OUTPUT_PREFIX [--timing-only]}
probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT
swift build -c release --scratch-path "$probe_dir/build"
bin_path=$(swift build -c release --show-bin-path --scratch-path "$probe_dir/build")
objects=()
while IFS= read -r -d '' object; do objects+=("$object"); done < <(
    find "$bin_path/EngineSimCore.build" -name '*.o' -print0
)
clang++ -std=c++17 -O3 -I swift/include swift/Benchmarks/PhysicsCost/main.cpp \
    "${objects[@]}" -o "$probe_dir/physics_cost"
"$probe_dir/physics_cost" "$output" "${@:2}"
