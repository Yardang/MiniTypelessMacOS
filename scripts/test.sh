#!/bin/bash
# Offline tests only: injected microphone/network, synthetic credentials, temporary logs.
set -euo pipefail
cd "$(dirname "$0")/.."
output_dir="$(mktemp -d /tmp/minitypeless-tests.XXXXXX)"
echo "Test artifacts: $output_dir"
for suite in InputFocusRegression ServiceDiagnosticRegression NoSpeechRegression WorkflowRegression LayoutRegression HUDRegression StabilityRegression SleepRecoveryRegression; do
    echo "Running $suite"
    xcrun swiftc -D DEBUG -D LAYOUT_TEST \
        -module-cache-path "$output_dir/module-cache" \
        MiniTypelessSecure/*.swift "Tests/$suite.swift" -o "$output_dir/$suite" \
        > "$output_dir/$suite.build.log" 2>&1 || { cat "$output_dir/$suite.build.log"; exit 1; }
    "$output_dir/$suite" 2>&1 | tee "$output_dir/$suite.log"
done
echo "PASS: all eight offline regression suites"
