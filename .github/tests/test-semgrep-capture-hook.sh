#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")/../.." && pwd)
RUN_SH="$SCRIPT_DIR/global/scripts/tools/semgrep/run.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

assert_contains() {
  needle=$1; shift
  grep -F -e "$needle" "$@" >/dev/null || { echo "missing: $needle" >&2; exit 1; }
}

# The hook must be opt-in and invoke the script with fixed, inspectable args.
# These patterns intentionally contain shell syntax as data.
# shellcheck disable=SC2016
assert_contains 'if [ -n "${SAST_CAPTURE_SCRIPT:-}" ]; then' "$RUN_SH"
# shellcheck disable=SC2016
assert_contains 'python3 "$SAST_CAPTURE_SCRIPT" --reports "$REPORT_PATH/captured"' "$RUN_SH"
# shellcheck disable=SC2016
assert_contains '--log-opts "${SAST_LOG_OPTS:-HEAD}"' "$RUN_SH"
assert_contains '|| EXIT_CODE=$?' "$RUN_SH"

# A fake scanner and capture script exercise the real shell control flow.
mkdir -p "$TMP/bin" "$TMP/reports"
cat > "$TMP/bin/semgrep" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat > "$TMP/bin/python3" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" > "$SAST_TEST_ARGS"
exit "${SAST_TEST_EXIT:-0}"
EOF
chmod +x "$TMP/bin/semgrep" "$TMP/bin/python3"
cat > "$TMP/capture.py" <<'EOF'
#!/usr/bin/env python3
EOF
chmod 600 "$TMP/capture.py"

(
  cd "$TMP"
  PATH="$TMP/bin:/usr/bin:/bin" SCRIPTS_DIR="$SCRIPT_DIR" REPORT_PATH="$TMP/reports" \
    SAST_CAPTURE_SCRIPT="$TMP/capture.py" SAST_TEST_ARGS="$TMP/args" \
    SEMGREP_LANGUAGE=none "$RUN_SH" none
)
assert_contains "$TMP/capture.py --reports $TMP/reports/semgrep/captured --log-opts HEAD" "$TMP/args"

if (
  cd "$TMP"
  PATH="$TMP/bin:/usr/bin:/bin" SCRIPTS_DIR="$SCRIPT_DIR" REPORT_PATH="$TMP/reports/fail" \
    SAST_CAPTURE_SCRIPT="$TMP/capture.py" SAST_TEST_ARGS="$TMP/fail-args" SAST_TEST_EXIT=7 \
    SEMGREP_LANGUAGE=none "$RUN_SH" none
); then
  echo "capture failure was swallowed" >&2
  exit 1
fi

echo "semgrep capture hook tests passed"
