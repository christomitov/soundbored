#!/bin/sh
# Runs the test suite with coverage and enforces the same minimum the CI
# workflow enforces, so coverage failures surface locally in `mix ci`.
MINIMUM=80.0

OUTPUT=$(mix coveralls 2>&1)
STATUS=$?
echo "$OUTPUT" | grep -vE "^\[logs\]" | tail -n +1

COVERAGE=$(echo "$OUTPUT" | grep "\[TOTAL\]" | awk '{print $2}' | sed 's/%//')

if [ -z "$COVERAGE" ]; then
  echo "coverage check: could not parse total coverage" >&2
  exit 1
fi

if [ "$STATUS" -ne 0 ]; then
  exit "$STATUS"
fi

if (echo "$COVERAGE < $MINIMUM" | bc -l | grep -q 1); then
  echo "Test coverage is below minimum: $COVERAGE% < $MINIMUM%"
  exit 1
fi

echo "Coverage is $COVERAGE%, which meets the minimum requirement of $MINIMUM%"
