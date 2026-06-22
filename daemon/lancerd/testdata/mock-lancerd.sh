#!/usr/bin/env bash
# mock-lancerd.sh — stub for lancerd used in shell integration tests.
# Prints all arguments to stdout and exits 0 so the hook script sees a success.
echo "ARGS: $*"
exit 0
