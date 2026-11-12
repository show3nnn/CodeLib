#!/bin/bash
source "$(dirname "$0")/toolchain.sh"
export CODEPATH_TEST_ROOT="$PWD/.build/test-data"
swift_package test "$@"
