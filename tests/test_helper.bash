#!/usr/bin/env bash
# Shared helpers for whisper-stream bats tests.

SCRIPT_PATH="${BATS_TEST_DIRNAME}/../whisper-stream"

# Source the script in library mode so its functions are available
# without running the main execution block. Note: do NOT export
# WHISPER_STREAM_LIB — we don't want it to leak into subprocesses spawned
# by `run ./whisper-stream ...` in tests that exercise the full CLI.
load_whisper_stream() {
  WHISPER_STREAM_LIB=1
  # shellcheck disable=SC1090
  source "$SCRIPT_PATH"
  unset WHISPER_STREAM_LIB
}

# Install a fake `curl` in a tmpdir-prefixed PATH so that tests can inspect
# exactly which arguments and (via --config) which credentials the script
# tried to pass to the real curl.
install_curl_stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export CURL_CAPTURE="$BATS_TEST_TMPDIR/curl_args.txt"
  export CURL_CONFIG_CAPTURE="$BATS_TEST_TMPDIR/curl_config.txt"
  : > "$CURL_CAPTURE"
  : > "$CURL_CONFIG_CAPTURE"

  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$CURL_CAPTURE"
done
prev=""
for arg in "$@"; do
  if [ "$prev" = "--config" ] && [ -f "$arg" ]; then
    cat "$arg" >> "$CURL_CONFIG_CAPTURE"
  fi
  prev="$arg"
done
echo '{"text":"fake transcription"}'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}
