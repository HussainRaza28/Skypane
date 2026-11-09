#!/bin/bash
# Measures Skypane's CPU, WindowServer's CPU, and Skypane's memory for each scene, using a
# Release build and the hidden benchmark launch arguments. Close other heavy apps and leave
# the Mac untouched while it runs; Skypane's window piles depend on the windows on screen.
#
# Usage: scripts/benchmark.sh [seconds per scene] [scene ...]
#   Scenes: clear lightSnow heavySnow rain thunderstorm fog leaves fireflies, or "custom:<description>"
#   Set BENCHMARK_BUILD=1 to rebuild the Release app first.
# Not using -e: closed pipes in the parsing below return harmless non-zero codes.
set -uo pipefail
cd "$(dirname "$0")/.."

measure_seconds=${1:-30}
shift || true
if [ "$#" -gt 0 ]; then
    scenes=("$@")
else
    scenes=(clear lightSnow heavySnow thunderstorm fog leaves "custom:falling pizza with green confetti")
fi
warmup_seconds=20
app_path="build/release/Build/Products/Release/Skypane.app"

if [ "${BENCHMARK_BUILD:-0}" = "1" ] || [ ! -d "$app_path" ]; then
    mkdir -p build
    if ! xcodebuild -project Skypane.xcodeproj -scheme Skypane -configuration Release \
        -destination "generic/platform=macOS" -derivedDataPath build/release build \
        > build/benchmark-build.log 2>&1; then
        cat build/benchmark-build.log >&2
        exit 1
    fi
    grep -E "error:|BUILD (SUCCEEDED|FAILED)" build/benchmark-build.log || true
fi

window_server_pid=$(pgrep -x WindowServer)
sample_count=$((measure_seconds / 2 + 1))

# Averages a process's %CPU from top's output, skipping top's first (always zero) sample.
average_cpu() {
    awk -v pid="$1" '$1 == pid { if (seen[pid]++) { total += $2; count++ } } END { if (count) printf "%.1f", total / count; else print "n/a" }'
}

printf "%-40s %10s %14s %12s %12s\n" "Scene" "Skypane %" "WindowServer %" "Memory" "Graphics"

# WindowServer's load with Skypane closed, to compare against.
pkill -x Skypane 2>/dev/null || true
sleep "$warmup_seconds"
if ! idle_output=$(top -l "$sample_count" -s 2 -pid "$window_server_pid" -stats pid,cpu); then
    echo "CPU measurement failed; no benchmark results are valid." >&2
    exit 1
fi
printf "%-40s %10s %14s %12s %12s\n" "(Skypane not running)" "-" "$(echo "$idle_output" | average_cpu "$window_server_pid")" "-" "-"

for scene in "${scenes[@]}"; do
    pkill -x Skypane 2>/dev/null || true
    while pgrep -x Skypane >/dev/null; do sleep 0.5; done
    sleep 1
    # Launch, retrying once if the previous copy was still shutting down.
    for attempt in 1 2; do
        if [[ "$scene" == custom:* ]]; then
            open -n "$app_path" --args -SkypaneBenchmarkCustom "${scene#custom:}"
        else
            open -n "$app_path" --args -SkypaneBenchmarkScene "$scene"
        fi
        sleep 4
        pgrep -x Skypane >/dev/null && break
    done
    sleep "$warmup_seconds"

    skypane_pid=$(pgrep -nx Skypane || true)
    if [ -z "$skypane_pid" ]; then
        printf "%-40s %s\n" "$scene" "Skypane didn't start"
        continue
    fi

    if ! top_output=$(top -l "$sample_count" -s 2 -pid "$skypane_pid" -pid "$window_server_pid" -stats pid,cpu); then
        echo "CPU measurement failed for $scene; stopping benchmark." >&2
        pkill -x Skypane 2>/dev/null || true
        exit 1
    fi
    skypane_cpu=$(echo "$top_output" | average_cpu "$skypane_pid")
    window_server_cpu=$(echo "$top_output" | average_cpu "$window_server_pid")
    footprint_output=$(footprint "$skypane_pid" 2>/dev/null)
    memory=$(echo "$footprint_output" | sed -nE 's/.*Footprint: ([0-9.]+ [KMG]B).*/\1/p' | head -1)
    graphics=$(echo "$footprint_output" | awk '/\(graphics\)/ { print $1, $2; exit }')

    printf "%-40s %10s %14s %12s %12s\n" "$scene" "$skypane_cpu" "$window_server_cpu" "${memory:-n/a}" "${graphics:-n/a}"
done
pkill -x Skypane 2>/dev/null || true
