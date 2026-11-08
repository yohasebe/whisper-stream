#!/usr/bin/env bats

# API key references: OPENAI_API_KEY or -t may hold op://... (1Password CLI)
# or keychain:<service> (macOS keychain) instead of the key. Every value here
# is synthetic; `op` and `security` are stand-in scripts.

load test_helper

SYNTHETIC="sk-test-SYNTHETIC-0000"

setup() {
  cd "$BATS_TEST_TMPDIR"
  printf 'x' > fake.mp3  # file mode rejects empty files
  install_curl_stub
  load_whisper_stream

  export OP_CALLS="$BATS_TEST_TMPDIR/op_calls"
  export OP_PID="$BATS_TEST_TMPDIR/op_pid"
  : > "$OP_CALLS"
  # A private TMPDIR, so leftover temp dirs can be counted reliably.
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  cat > "$BATS_TEST_TMPDIR/bin/op" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$OP_CALLS"
[ "$1" = read ] || exit 2
case "$2" in
  op://Test/Item/credential) echo "sk-test-SYNTHETIC-0000" ;;
  op://Test/Slow/credential) echo $$ > "$OP_PID"; exec sleep 30 ;;
  op://Test/Lingers/credential) echo "sk-test-SYNTHETIC-0000"; echo $$ > "$OP_PID"; exec sleep 30 ;;
  op://Test/Multi/credential) printf 'sk-one\nsk-two\n' ;;
  op://Test/BlankSecond/credential) printf 'sk-one\n\n' ;;
  op://Test/Empty/credential) echo "" ;;
  op://Test/CRLF/credential) printf 'sk-test-SYNTHETIC-0000\r\n' ;;
  op://Test/InnerCR/credential) printf 'sk-one\rsk-two\n' ;;
  op://Test/NoNewline/credential) printf 'sk-test-SYNTHETIC-0000' ;;
  op://Test/Tab/credential) printf 'sk-one\tsk-two\n' ;;
  op://Test/SignedOut/credential) echo "[ERROR] You are not currently signed in." >&2; exit 1 ;;
  op://Test/Dismissed/credential) echo "[ERROR] could not read secret '$2': error initializing client: authorization prompt dismissed, please try again" >&2; exit 1 ;;
  op://Test/Leaky/credential) echo "sk-test-SYNTHETIC-0000 rejected" >&2; exit 7 ;;
  *) echo "[ERROR] \"$2\" isn't an item." >&2; exit 1 ;;
esac
STUB
  cat > "$BATS_TEST_TMPDIR/bin/security" <<'STUB'
#!/usr/bin/env bash
[ "$1" = find-generic-password ] && [ "$3" = test-openai ] || exit 44
echo "sk-test-SYNTHETIC-0000"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/op" "$BATS_TEST_TMPDIR/bin/security"

  BACKEND="api"
  STDOUT_MODE=true
  SECURITY_CLI="$BATS_TEST_TMPDIR/bin/security"
  KEY_REFERENCE_TIMEOUT=2
}

# --- resolve_api_token --------------------------------------------------------

@test "a key that is not a reference is used as is, without calling op" {
  TOKEN="sk-plain-key"
  resolve_api_token
  [ "$TOKEN" = "sk-plain-key" ]
  [ ! -s "$OP_CALLS" ]
}

@test "an op:// reference is read with op read" {
  TOKEN="op://Test/Item/credential"
  resolve_api_token
  [ "$TOKEN" = "$SYNTHETIC" ]
  [ "$(cat "$OP_CALLS")" = "read op://Test/Item/credential" ]
}

@test "a keychain: reference is read with security find-generic-password" {
  TOKEN="keychain:test-openai"
  resolve_api_token
  [ "$TOKEN" = "$SYNTHETIC" ]
}

@test "an unreadable 1Password item names the reference and explains the CLI" {
  TOKEN="op://Test/Missing/credential"
  run resolve_api_token
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read the 1Password reference op://Test/Missing/credential"* ]]
  [[ "$output" == *"vault, item, and field exist"* ]]
}

@test "a signed-out 1Password CLI is reported as such" {
  TOKEN="op://Test/SignedOut/credential"
  run resolve_api_token
  [ "$status" -ne 0 ]
  [[ "$output" == *"not signed in"* ]]
  [[ "$output" == *"Integrate with 1Password CLI"* ]]
}

@test "a dismissed approval prompt is reported as such, not as signed out" {
  TOKEN="op://Test/Dismissed/credential"
  run resolve_api_token
  [ "$status" -ne 0 ]
  [[ "$output" == *"approval prompt was dismissed"* ]]
  [[ "$output" != *"not signed in"* ]]
}

@test "the command's own error output is never shown (it could hold the key)" {
  TOKEN="op://Test/Leaky/credential"
  run resolve_api_token
  [ "$status" -ne 0 ]
  [[ "$output" != *"$SYNTHETIC"* ]]
  [[ "$output" != *"rejected"* ]]
}

@test "a missing keychain item explains how to add it" {
  TOKEN="keychain:no-such-item"
  run resolve_api_token
  [ "$status" -ne 0 ]
  [[ "$output" == *'keychain item "no-such-item"'* ]]
  [[ "$output" == *"security add-generic-password -s no-such-item"* ]]
}

@test "a reference that holds more than one line, or nothing, is rejected" {
  local ref
  for ref in op://Test/Multi/credential op://Test/BlankSecond/credential \
             op://Test/Empty/credential op://Test/InnerCR/credential; do
    TOKEN="$ref"
    run resolve_api_token
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not hold a single-line API key"* ]]
    [[ "$output" != *"sk-one"* ]]
  done
}

@test "a CRLF line ending and a missing final newline are accepted" {
  local ref
  for ref in op://Test/CRLF/credential op://Test/NoNewline/credential; do
    TOKEN="$ref"
    resolve_api_token
    [ "$TOKEN" = "$SYNTHETIC" ]
  done
}

@test "a 1Password read that does not answer times out, with a hint over SSH" {
  TOKEN="op://Test/Slow/credential"
  SSH_CONNECTION="192.0.2.1 50000 192.0.2.2 22"
  run resolve_api_token
  [ "$status" -ne 0 ]
  [[ "$output" == *"no answer within 2s"* ]]
  [[ "$output" == *"Over SSH"* ]]
  ! kill -0 "$(cat "$OP_PID")" 2>/dev/null || false
}

@test "a command that prints the key but does not exit is also timed out" {
  TOKEN="op://Test/Lingers/credential"
  local started=$SECONDS
  run resolve_api_token
  [ "$status" -ne 0 ]
  [[ "$output" == *"no answer within 2s"* ]]
  [ $((SECONDS - started)) -le 4 ]
  ! kill -0 "$(cat "$OP_PID")" 2>/dev/null || false
}

@test "without the 1Password CLI, an op:// reference says how to install it" {
  TOKEN="op://Test/Item/credential"
  OP_CLI_FALLBACKS=()
  PATH="/usr/bin:/bin" run resolve_api_token
  [ "$status" -ne 0 ]
  [[ "$output" == *"1Password CLI (op) was not found"* ]]
}

@test "keychain: without a name is rejected" {
  TOKEN="keychain:"
  run resolve_api_token
  [ "$status" -ne 0 ]
  [[ "$output" == *"without a name"* ]]
}

@test "errors never show the key" {
  TOKEN="op://Test/Multi/credential"
  run resolve_api_token
  [[ "$output" != *"$SYNTHETIC"* ]]
  [[ "$output" != *"sk-two"* ]]
}

@test "read_secret_command leaves no temp directory behind" {
  read_secret_command 2 "$BATS_TEST_TMPDIR/bin/op" read op://Test/Item/credential > /dev/null
  run read_secret_command 2 "$BATS_TEST_TMPDIR/bin/op" read op://Test/Missing/credential
  run read_secret_command 2 "$BATS_TEST_TMPDIR/bin/op" read op://Test/Lingers/credential
  [ -z "$(ls "$TMPDIR")" ]
}

@test "Ctrl-C while the key is being read stops the command and cleans up" {
  cat > "$BATS_TEST_TMPDIR/interrupt.sh" <<SCRIPT
WHISPER_STREAM_LIB=1 source "$SCRIPT_PATH"
read_secret_command 30 "$BATS_TEST_TMPDIR/bin/op" read op://Test/Slow/credential
SCRIPT
  bash "$BATS_TEST_TMPDIR/interrupt.sh" &
  local shell=$!
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$OP_PID" ] && break
    sleep 0.2
  done
  kill -INT "$shell"
  wait "$shell" || true
  sleep 0.3
  ! kill -0 "$(cat "$OP_PID")" 2>/dev/null || false
  [ -z "$(ls "$TMPDIR")" ]
}

# --- the whole script ------------------------------------------------------------

@test "OPENAI_API_KEY as an op:// reference: the key reaches curl's config, not argv" {
  run env OPENAI_API_KEY=op://Test/Item/credential "$SCRIPT_PATH" --stdout -f fake.mp3
  [ "$status" -eq 0 ]
  grep -qF "Bearer $SYNTHETIC" "$CURL_CONFIG_CAPTURE"
  ! grep -qF "$SYNTHETIC" "$CURL_CAPTURE" || false
}

@test "-t accepts a reference too" {
  run env -u OPENAI_API_KEY "$SCRIPT_PATH" --stdout -f fake.mp3 -t op://Test/Item/credential
  [ "$status" -eq 0 ]
  grep -qF "Bearer $SYNTHETIC" "$CURL_CONFIG_CAPTURE"
}

@test "a plain OPENAI_API_KEY still works and never calls op" {
  run env OPENAI_API_KEY=sk-plain-key "$SCRIPT_PATH" --stdout -f fake.mp3
  [ "$status" -eq 0 ]
  grep -qF "Bearer sk-plain-key" "$CURL_CONFIG_CAPTURE"
  [ ! -s "$OP_CALLS" ]
}

@test "an inherited exported TOKEN does not carry the resolved key to child processes" {
  run env TOKEN=parent-value OPENAI_API_KEY=op://Test/Item/credential "$SCRIPT_PATH" --stdout -f fake.mp3 \
        -p2 'printenv TOKEN || echo no-token'
  [ "$status" -eq 0 ]
  [[ "$output" != *"$SYNTHETIC"* ]]
}

@test "the resolved key is not passed to --pipe-to commands" {
  run env OPENAI_API_KEY=op://Test/Item/credential "$SCRIPT_PATH" --stdout -f fake.mp3 \
        -p2 'printenv OPENAI_API_KEY'
  [ "$status" -eq 0 ]
  [[ "$output" == *"op://Test/Item/credential"* ]]
  [[ "$output" != *"$SYNTHETIC"* ]]
}

@test "an unreadable reference stops the script before any request" {
  run env OPENAI_API_KEY=op://Test/Missing/credential "$SCRIPT_PATH" --stdout -f fake.mp3
  [ "$status" -eq 1 ]
  [ ! -s "$CURL_CAPTURE" ]
}

@test "secret-holding locals do not inherit an exported variable's attribute" {
  cat > "$BATS_TEST_TMPDIR/inherit.sh" <<SCRIPT
WHISPER_STREAM_LIB=1 source "$SCRIPT_PATH"
# Every external command run after the read shows its environment.
rm() { /usr/bin/env >> "$BATS_TEST_TMPDIR/child_env"; /bin/rm "\$@"; }
STDOUT_MODE=true
TOKEN=op://Test/Item/credential
resolve_api_token
SCRIPT
  run env value=parent extra=parent key=parent PATH="$PATH" bash "$BATS_TEST_TMPDIR/inherit.sh"
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/child_env" ]
  ! grep -qF "$SYNTHETIC" "$BATS_TEST_TMPDIR/child_env" || false
}

@test "a process left behind holding stderr neither delays the read nor survives it" {
  export LEFT="$BATS_TEST_TMPDIR/left_pid"
  local started=$SECONDS
  run read_secret_command 2 bash -c 'sleep 30 > /dev/null & echo $! > "$LEFT"; echo "You are not currently signed in" >&2; exit 1'
  [ -s "$LEFT" ]          # the command really ran and left a process
  [ "$status" -eq 1 ]     # its own status: the filter never saw the end of stderr
  [ $((SECONDS - started)) -le 4 ]
  ! kill -0 "$(cat "$LEFT")" 2>/dev/null || false
}

@test "a process left behind after a successful read is stopped too" {
  export LEFT="$BATS_TEST_TMPDIR/left_pid"
  run read_secret_command 3 bash -c 'echo sk-ok; sleep 30 > /dev/null 2>&1 & echo $! > "$LEFT"'
  [ "$status" -eq 0 ]
  [ "$output" = "sk-ok" ]
  [ -s "$LEFT" ]
  ! kill -0 "$(cat "$LEFT")" 2>/dev/null || false
}

@test "a lot of stderr before the key does not block the command" {
  run read_secret_command 3 bash -c 'head -c 1048576 /dev/zero | tr "\0" x >&2; echo sk-after-noise'
  [ "$status" -eq 0 ]
  [ "$output" = "sk-after-noise" ]
}

# --- the key in curl's config line ---------------------------------------------

@test "a backslash or double quote in the key is escaped in curl's config" {
  TOKEN='sk-a"b\c'
  AUDIO_FILE=fake.mp3
  MODEL=gpt-transcribe
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  [ "$(cat "$CURL_CONFIG_CAPTURE")" = 'header = "Authorization: Bearer sk-a\"b\\c"' ]
}

@test "a key with a line break is rejected before any request" {
  run env OPENAI_API_KEY=$'sk-one\nverbose' "$SCRIPT_PATH" --stdout -f fake.mp3
  [ "$status" -eq 1 ]
  [[ "$output" == *"contains a control character"* ]]
  [[ "$output" != *"sk-one"* ]]
  [ ! -s "$CURL_CAPTURE" ]
}

@test "a reference that resolves to a key with a control character is rejected" {
  run env OPENAI_API_KEY=op://Test/Tab/credential "$SCRIPT_PATH" --stdout -f fake.mp3
  [ "$status" -eq 1 ]
  [[ "$output" == *"contains a control character"* ]]
  [ ! -s "$CURL_CAPTURE" ]
}

@test "a token without control characters from a self-hosted server passes unchanged" {
  run env OPENAI_API_KEY='abc+/=.def' "$SCRIPT_PATH" --stdout -f fake.mp3 --api-url http://127.0.0.1:9/v1/audio/transcriptions
  [ "$status" -eq 0 ]
  grep -qxF 'header = "Authorization: Bearer abc+/=.def"' "$CURL_CONFIG_CAPTURE"
}
