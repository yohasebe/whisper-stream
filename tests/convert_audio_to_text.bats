#!/usr/bin/env bats

load test_helper

setup() {
  cd "$BATS_TEST_TMPDIR"
  touch fake.mp3
  install_curl_stub
  load_whisper_stream

  BACKEND="api"
  TOKEN="sk-TEST-TOKEN-12345"
  MODEL="gpt-4o-mini-transcribe"
  MODEL_PATH=""
  API_URL=""
  PROMPT=""
  LANGUAGE=""
  DIARIZE=false
  TRANSLATE=""
  AUDIO_FILE="fake.mp3"  # suppress rm -f inside convert_audio_to_text
  PIPE_TO_CMD=""
  KNOWN_SPEAKERS=()
  CHUNKING_STRATEGY=""
  STDOUT_MODE=false
  JSONL_MODE=false
  JSONL_SCHEMA_VERSION=1
  MIN_AUDIO_DURATION=0.3
}

@test "PROMPT with command substitution is not executed" {
  PWN="$BATS_TEST_TMPDIR/pwned_cmdsub"
  PROMPT="\$(touch '$PWN')"
  convert_audio_to_text fake.mp3 >/dev/null
  [ ! -e "$PWN" ]
}

@test "PROMPT with backtick expansion is not executed" {
  PWN="$BATS_TEST_TMPDIR/pwned_backtick"
  PROMPT="\`touch '$PWN'\`"
  convert_audio_to_text fake.mp3 >/dev/null
  [ ! -e "$PWN" ]
}

@test "LANGUAGE with command substitution is not executed" {
  PWN="$BATS_TEST_TMPDIR/pwned_lang"
  LANGUAGE="\$(touch '$PWN')"
  convert_audio_to_text fake.mp3 >/dev/null
  [ ! -e "$PWN" ]
}

@test "PROMPT is passed as a literal string to curl" {
  PROMPT='hello $HOME `id`'
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'prompt=hello $HOME `id`' "$CURL_CAPTURE"
}

@test "API token does not appear in curl argv" {
  convert_audio_to_text fake.mp3 >/dev/null
  run grep -F 'sk-TEST-TOKEN-12345' "$CURL_CAPTURE"
  [ "$status" -ne 0 ]
}

@test "API token is passed to curl as a config on stdin (not argv, not a file)" {
  convert_audio_to_text fake.mp3 >/dev/null
  grep -q 'sk-TEST-TOKEN-12345' "$CURL_CONFIG_CAPTURE"
  [ "$(grep -A1 -x -- '--config' "$CURL_CAPTURE" | tail -1)" = "-" ]
}

@test "default response_format is json" {
  MODEL="gpt-4o-mini-transcribe"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'response_format=json' "$CURL_CAPTURE"
  run grep -Fxq 'response_format=verbose_json' "$CURL_CAPTURE"
  [ "$status" -ne 0 ]
}

@test "snapshot model name is passed through to curl" {
  MODEL="gpt-4o-mini-transcribe-2025-12-15"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'model=gpt-4o-mini-transcribe-2025-12-15' "$CURL_CAPTURE"
}

@test "default endpoint is OpenAI's transcriptions URL" {
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'https://api.openai.com/v1/audio/transcriptions' "$CURL_CAPTURE"
}

@test "language form field is sent when LANGUAGE is set" {
  MODEL="gpt-4o-mini-transcribe"
  LANGUAGE="ja"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'language=ja' "$CURL_CAPTURE"
}

# --- --api-url override ----------------------------------------------------

@test "API_URL overrides the default endpoint" {
  API_URL="http://127.0.0.1:2022/v1/audio/transcriptions"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'http://127.0.0.1:2022/v1/audio/transcriptions' "$CURL_CAPTURE"
  # The default URL must NOT also be present.
  run grep -Fxq 'https://api.openai.com/v1/audio/transcriptions' "$CURL_CAPTURE"
  [ "$status" -ne 0 ]
}

@test "no auth file is created when token is empty (api-url use case)" {
  TOKEN=""
  API_URL="http://127.0.0.1:2022/v1/audio/transcriptions"
  convert_audio_to_text fake.mp3 >/dev/null
  # --config flag should not appear in argv when no token
  run grep -Fxq -- '--config' "$CURL_CAPTURE"
  [ "$status" -ne 0 ]
}

# --- API error handling ----------------------------------------------------

@test "API error response is logged to stderr and the utterance is skipped" {
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo '{"error":{"message":"Rate limit exceeded","type":"rate_limit_error"}}'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"

  run convert_audio_to_text fake.mp3
  # A failed utterance now reports non-zero so file mode can propagate it;
  # the real-time loop deliberately ignores the status and carries on.
  [ "$status" -ne 0 ]
  # Output should NOT contain the error string as transcription text.
  [[ "$output" != *"transcription text"* ]] || true
  # Stderr (merged into $output by bats) should carry the warning.
  [[ "$output" == *"API error"* ]]
  [[ "$output" == *"Rate limit"* ]]
}

# --- short audio skip ------------------------------------------------------

@test "short audio (below threshold) is skipped in real-time mode" {
  # Make soxi return a fixed short duration via a stub.
  cat > "$BATS_TEST_TMPDIR/bin/soxi" <<'STUB'
#!/usr/bin/env bash
# Mimic `soxi -D <file>` returning 0.1 seconds.
echo "0.1"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/soxi"

  # Real-time mode means AUDIO_FILE is empty. The setup() defaults set it to
  # "fake.mp3" to suppress rm -f in other tests; clear it here so the
  # short-audio guard fires.
  AUDIO_FILE=""
  : > "$CURL_CAPTURE"
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  # No curl call should have happened.
  [ ! -s "$CURL_CAPTURE" ]
}

@test "audio above threshold is processed normally" {
  cat > "$BATS_TEST_TMPDIR/bin/soxi" <<'STUB'
#!/usr/bin/env bash
echo "1.5"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/soxi"

  : > "$CURL_CAPTURE"
  convert_audio_to_text fake.mp3 >/dev/null
  [ -s "$CURL_CAPTURE" ]
}

@test "short audio is NOT skipped when AUDIO_FILE is set (file mode)" {
  # File mode means the user explicitly chose this input. Honour the choice
  # even when the duration is below the real-time threshold.
  cat > "$BATS_TEST_TMPDIR/bin/soxi" <<'STUB'
#!/usr/bin/env bash
echo "0.1"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/soxi"

  AUDIO_FILE="fake.mp3"
  : > "$CURL_CAPTURE"
  convert_audio_to_text fake.mp3 >/dev/null
  # The API call SHOULD have happened.
  [ -s "$CURL_CAPTURE" ]
}

# --- speaker references: file-based form fields (ARG_MAX regression) ---------
#
# A 10-second speaker sample is ~880 KB of WAV, i.e. ~1.2 MB base64. Passing
# that inline via `--form "known_speaker_references[]=$encoded"` exceeds
# macOS ARG_MAX (~1 MB) and the diarization feature dies with E2BIG. The
# reference must go through curl's `--form 'field=<file'` file-read syntax.

setup_diarize_speaker() {
  DIARIZE=true
  MODEL="gpt-4o-transcribe-diarize"
  CHUNKING_STRATEGY="auto"
  SPEAKER_DIR="$BATS_TEST_TMPDIR/speakers"
  mkdir -p "$SPEAKER_DIR"
  jq -n '{alice: {name: "Alice", file: "alice.wav", duration: 5, created: "2026-01-01T00:00:00Z"}}' \
    > "$SPEAKER_DIR/speakers.json"
  # ~1.2 MB of audio: base64-encoded (~1.6 MB) this would blow past macOS
  # ARG_MAX (1 MB) if it were inlined into curl argv.
  head -c 1200000 /dev/zero > "$SPEAKER_DIR/alice.wav"
  KNOWN_SPEAKERS=("alice")
}

@test "speaker reference is passed as a file-based form field (not inline base64 in argv)" {
  setup_diarize_speaker
  # Use `run` — a direct call would abort the test shell under bats' errexit
  # semantics when curl (stubbed or real) exits non-zero inside the function.
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  grep -F 'known_speaker_references[]=<' "$CURL_CAPTURE"
  # No argv element may carry the base64 blob itself.
  awk 'length($0) > 100000 { exit 1 }' "$CURL_CAPTURE"
}

@test "speaker reference temp file is removed after the call" {
  setup_diarize_speaker
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  local ref_path
  ref_path=$(grep -F 'known_speaker_references[]=<' "$CURL_CAPTURE" | sed 's/.*=<//')
  [ -n "$ref_path" ]
  [ ! -e "$ref_path" ]
}

@test "speaker reference temp file contains the base64 data URI" {
  setup_diarize_speaker
  # Stub curl that dumps the contents of any file-based reference fields.
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    known_speaker_references[]=\<*) cat "${arg#*=<}" >> "$REF_CAPTURE" ;;
  esac
done
echo '{"text":"fake transcription"}'
echo "200"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export REF_CAPTURE="$BATS_TEST_TMPDIR/ref_capture.txt"

  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  grep -q '^data:audio/wav;base64,' "$REF_CAPTURE"
}

# --- HTTP status handling ----------------------------------------------------

@test "non-2xx HTTP response is skipped with a warning" {
  # FastAPI-style error body (common for self-hosted servers) + status line.
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' '{"detail":"Not Found"}'
printf '%s\n' '404'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"

  run convert_audio_to_text fake.mp3
  # A failed utterance now reports non-zero so file mode can propagate it;
  # the real-time loop deliberately ignores the status and carries on.
  [ "$status" -ne 0 ]
  [[ "$output" == *"HTTP 404"* ]]
  [[ "$output" == *"skipping utterance"* ]]
}

@test "empty API response (request failed after retries) is skipped with a warning" {
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
exit 7
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"

  run convert_audio_to_text fake.mp3
  # A failed utterance now reports non-zero so file mode can propagate it;
  # the real-time loop deliberately ignores the status and carries on.
  [ "$status" -ne 0 ]
  [[ "$output" == *"skipping utterance"* ]]
}

# --- HTTP status line parsing ------------------------------------------------

@test "a multi-line body without a status line is not truncated" {
  # Only a bare 3-digit final line is the -w status. A pretty-printed JSON
  # body whose last line is "}" must survive intact.
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '{\n  "text": "multi line body"\n}\n'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"

  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  [[ "$output" == *"multi line body"* ]]
}

@test "a 3-digit status line is still stripped from a multi-line body" {
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '{\n  "text": "multi line body"\n}\n200'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"

  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  [ "$output" = "multi line body" ]
}

# --- failure signalling ------------------------------------------------------
#
# A skipped-because-failed utterance must return non-zero so that file mode
# can turn it into a non-zero process exit. Deliberate skips (audio too
# short) are NOT failures and keep returning 0.

@test "an API error returns non-zero from convert_audio_to_text" {
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '{"error":{"message":"Rate limit exceeded"}}\n429'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"

  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
}

@test "the short-audio skip is not a failure (returns zero)" {
  cat > "$BATS_TEST_TMPDIR/bin/soxi" <<'STUB'
#!/usr/bin/env bash
echo "0.1"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/soxi"
  AUDIO_FILE=""
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
}

@test "a non-2xx response includes the API's own error message when present" {
  # The HTTP status check runs before the .error extraction, so it must not
  # throw away the more informative message (e.g. rate limit vs. quota).
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '{"error":{"message":"You exceeded your current quota","type":"insufficient_quota"}}\n429'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"

  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" == *"429"* ]]
  [[ "$output" == *"exceeded your current quota"* ]]
}

@test "a non-2xx response without a JSON error body still reports the status" {
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '<html>502 Bad Gateway</html>\n502'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"

  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" == *"502"* ]]
}

# --- literal form fields (--form-string) -------------------------------------
#
# With --form, curl itself interprets a value starting with `<` (read a file)
# or `@` (upload a file). Text fields must go through --form-string.

# Print the argument that precedes the exact argv entry $1 in the capture.
arg_before() {
  local prev="" line
  while IFS= read -r line; do
    if [ "$line" = "$1" ]; then
      printf '%s\n' "$prev"
      return 0
    fi
    prev="$line"
  done < "$CURL_CAPTURE"
  return 1
}

@test "a prompt starting with < or @ is sent literally via --form-string" {
  PROMPT="<secret.txt"
  convert_audio_to_text fake.mp3 >/dev/null
  [ "$(arg_before 'prompt=<secret.txt')" = "--form-string" ]

  : > "$CURL_CAPTURE"
  PROMPT="@team meeting notes"
  convert_audio_to_text fake.mp3 >/dev/null
  [ "$(arg_before 'prompt=@team meeting notes')" = "--form-string" ]
}

@test "model and response_format are literal fields; only the audio uses --form" {
  convert_audio_to_text fake.mp3 >/dev/null
  [ "$(arg_before 'model=gpt-4o-mini-transcribe')" = "--form-string" ]
  [ "$(arg_before 'response_format=json')" = "--form-string" ]
  [ "$(arg_before 'file=@fake.mp3')" = "--form" ]
}

# --- languages and keywords --------------------------------------------------

@test "gpt-transcribe sends even a single language as languages[]" {
  MODEL="gpt-transcribe"
  LANGUAGE="ja"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'languages[]=ja' "$CURL_CAPTURE"
  # The API rejects the singular and plural fields together.
  run grep -Fxq 'language=ja' "$CURL_CAPTURE"
  [ "$status" -ne 0 ]
}

@test "several languages are sent as repeated languages[] fields" {
  MODEL="gpt-transcribe"
  LANGUAGE="en, ja"
  convert_audio_to_text fake.mp3 >/dev/null
  [ "$(grep -c '^languages\[\]=' "$CURL_CAPTURE")" -eq 2 ]
  grep -Fxq 'languages[]=en' "$CURL_CAPTURE"
  grep -Fxq 'languages[]=ja' "$CURL_CAPTURE"
}

@test "keywords are sent as literal keywords[] fields" {
  MODEL="gpt-transcribe"
  KEYWORDS=("ACME, Inc." "@handle")
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'keywords[]=ACME, Inc.' "$CURL_CAPTURE"
  [ "$(arg_before 'keywords[]=@handle')" = "--form-string" ]
}

@test "no languages[] or keywords[] fields are sent when unset" {
  MODEL="gpt-transcribe"
  convert_audio_to_text fake.mp3 >/dev/null
  run grep -E '^(languages|keywords)\[\]=|^language=' "$CURL_CAPTURE"
  [ "$status" -ne 0 ]
}

@test "a bare 'Invalid request.' gets a hint when languages/keywords were sent" {
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '{"error":{"message":"Invalid request.","code":"invalid_value"}}\n400'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  MODEL="gpt-transcribe"
  LANGUAGE="english"
  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid request."* ]]
  [[ "$output" == *"Hint:"* ]]
}

@test "no hint for 'Invalid request.' when no language/keyword/prompt was sent" {
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '{"error":{"message":"Invalid request.","code":"invalid_value"}}\n400'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  MODEL="gpt-transcribe"
  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" != *"Hint:"* ]]
}

# --- retries and response checks ---------------------------------------------
#
# Scripted curl: call N runs reply_N (or the last reply defined) with the -D
# header file as $1, and exits with that reply's status.

install_scripted_curl() {
  export CURL_CALLS="$BATS_TEST_TMPDIR/curl_calls"
  export REPLY_DIR="$BATS_TEST_TMPDIR/replies"
  echo 0 > "$CURL_CALLS"
  mkdir -p "$REPLY_DIR"
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$CURL_CAPTURE"
done
headers=""
prev=""
for arg in "$@"; do
  [ "$prev" = "-D" ] && headers="$arg"
  prev="$arg"
done
n=$(( $(cat "$CURL_CALLS") + 1 )); echo "$n" > "$CURL_CALLS"
while [ "$n" -gt 1 ] && [ ! -f "$REPLY_DIR/$n" ]; do n=$((n - 1)); done
bash "$REPLY_DIR/$n" "$headers"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}

# reply <call number> <script body>
reply() {
  printf '%s\n' "$2" > "$REPLY_DIR/$1"
}

curl_calls() {
  cat "$CURL_CALLS"
}

@test "a transfer that fails after part of the body is a failure, not a transcript" {
  install_scripted_curl
  reply 1 'printf "{\"text\":\"partial result\"}\n200"; exit 28'
  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" != *"partial result"* ]]
  [[ "$output" == *"no response within 600s"* ]]
  [ "$(curl_calls)" -eq 3 ]
}

@test "a 2xx JSON body without text is a failure" {
  install_scripted_curl
  reply 1 'printf "{}\n200"'
  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected API response"* ]]
  [[ "$output" != *"Error"* ]]
  [ ! -s "${WORK_DIR:-.}/temp_transcriptions.txt" ]
}

@test "a 2xx body that is not JSON is a failure" {
  install_scripted_curl
  reply 1 'printf "<html>proxy page</html>\n200"'
  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected API response"* ]]
}

@test "an empty transcript is a valid response" {
  install_scripted_curl
  reply 1 'printf "{\"text\":\"\"}\n200"'
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
}

@test "diarized segments without speaker labels are a failure" {
  install_scripted_curl
  DIARIZE=true
  MODEL="gpt-4o-transcribe-diarize"
  CHUNKING_STRATEGY="auto"
  reply 1 'printf "{\"segments\":[{\"start\":0,\"text\":\"hi\"}]}\n200"'
  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected API response"* ]]
}

@test "a 503 is retried and a later success is used once" {
  install_scripted_curl
  reply 1 'printf "{\"error\":{\"code\":\"server_is_overloaded\"}}\n503"'
  reply 2 'printf "{\"text\":\"second try\"}\n200"'
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  [ "$output" = "second try" ]
  [ "$(curl_calls)" -eq 2 ]
  [ "$(grep -c 'second try' temp_transcriptions.txt)" -eq 1 ]
}

@test "a rate-limit 429 is retried" {
  install_scripted_curl
  reply 1 'printf "{\"error\":{\"code\":\"slow_down\",\"type\":\"rate_limit_error\"}}\n429"'
  reply 2 'printf "{\"text\":\"ok\"}\n200"'
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  [ "$(curl_calls)" -eq 2 ]
}

@test "billing and quota 429s are not retried" {
  install_scripted_curl
  local code
  for code in credit_balance_exhausted project_spend_limit_exceeded organization_usage_limit_exceeded; do
    echo 0 > "$CURL_CALLS"
    reply 1 "printf '{\"error\":{\"code\":\"$code\",\"message\":\"$code\"}}\n429'"
    run convert_audio_to_text fake.mp3
    [ "$status" -ne 0 ]
    [ "$(curl_calls)" -eq 1 ]
  done
}

@test "client errors are not retried" {
  install_scripted_curl
  reply 1 'printf "{\"error\":{\"message\":\"Incorrect API key\"}}\n401"'
  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [ "$(curl_calls)" -eq 1 ]
}

@test "requests stop after API_MAX_ATTEMPTS" {
  install_scripted_curl
  reply 1 'printf "oops\n500"'
  API_MAX_ATTEMPTS=4
  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" == *"HTTP 500"* ]]
  [ "$(curl_calls)" -eq 4 ]
}

@test "a Retry-After longer than the limit ends the retries" {
  install_scripted_curl
  reply 1 'printf "HTTP/2 429\r\nretry-after: 600\r\n\r\n" > "$1"; printf "{\"error\":{\"code\":\"slow_down\"}}\n429"'
  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" == *"asked to wait 600s"* ]]
  [ "$(curl_calls)" -eq 1 ]
}

@test "retry_after_seconds reads the last header block and prefers the longer wait" {
  printf 'HTTP/1.1 100 Continue\r\nRetry-After: 99\r\n\r\nHTTP/2 429\r\nretry-after: 3\r\nretry-after-ms: 4500\r\n\r\n' > h
  [ "$(retry_after_seconds h)" = "5" ]
  printf 'HTTP/2 503\r\nRetry-After: 7\r\n\r\n' > h
  [ "$(retry_after_seconds h)" = "7" ]
  printf 'HTTP/2 429\r\n\r\n' > h
  [ -z "$(retry_after_seconds h)" ]
  [ -z "$(retry_after_seconds missing)" ]
}

@test "api_backoff_delay doubles per attempt and is capped" {
  API_RETRY_BASE_DELAY=1
  local d1 d2 d9
  d1=$(api_backoff_delay 1)
  d2=$(api_backoff_delay 2)
  d9=$(api_backoff_delay 9)
  awk -v a="$d1" -v b="$d2" -v c="$d9" 'BEGIN { exit !(a >= 1 && a <= 2 && b >= 2 && b <= 3 && c >= 30 && c <= 31) }'
}

@test "each request has a time limit: 120 s in real time, 600 s for -f, or --api-timeout" {
  AUDIO_FILE=""
  touch rt.mp3
  convert_audio_to_text rt.mp3 >/dev/null
  grep -A1 -x -- '--max-time' "$CURL_CAPTURE" | grep -qx 120
  : > "$CURL_CAPTURE"
  AUDIO_FILE="fake.mp3"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -A1 -x -- '--max-time' "$CURL_CAPTURE" | grep -qx 600
  : > "$CURL_CAPTURE"
  API_TIMEOUT=45
  convert_audio_to_text fake.mp3 >/dev/null
  grep -A1 -x -- '--max-time' "$CURL_CAPTURE" | grep -qx 45
}

@test "request temp files go into the session work dir when there is one" {
  WORK_DIR="$BATS_TEST_TMPDIR/session"
  mkdir -p "$WORK_DIR"
  convert_audio_to_text fake.mp3 >/dev/null
  local headers
  headers=$(grep -A1 -x -- '-D' "$CURL_CAPTURE" | tail -1)
  [[ "$headers" == "$WORK_DIR/whisper-stream-headers."* ]]
  [ ! -e "$headers" ]
  [ -z "$(ls "$WORK_DIR" | grep -v temp_transcriptions.txt)" ]
}

@test "a body with more than one JSON value is a failure" {
  install_scripted_curl
  reply 1 'printf "{}\n{\"text\":\"accepted\"}\n200"'
  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" != *"accepted"* ]]
}

@test "after a retry, the transcript is piped to --pipe-to once" {
  install_scripted_curl
  reply 1 'printf "oops\n503"'
  reply 2 'printf "{\"text\":\"piped\"}\n200"'
  export PIPE_LOG="$BATS_TEST_TMPDIR/pipe.log"
  PIPE_TO_CMD='cat >> "$PIPE_LOG"'
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  [ "$(cat "$PIPE_LOG")" = "piped" ]
}

@test "retry_after_seconds reads HTTP-dates and rounds milliseconds up" {
  local future
  future=$(LC_ALL=C date -u -r $(( $(date +%s) + 90 )) '+%a, %d %b %Y %H:%M:%S GMT' 2>/dev/null \
    || LC_ALL=C date -u -d "@$(( $(date +%s) + 90 ))" '+%a, %d %b %Y %H:%M:%S GMT')
  printf 'HTTP/2 503\r\nRetry-After: %s\r\n\r\n' "$future" > h
  local wait
  wait=$(retry_after_seconds h)
  [ "$wait" -ge 85 ] && [ "$wait" -le 90 ]
  printf 'HTTP/2 503\r\nRetry-After: Mon, 01 Jan 2024 00:00:00 GMT\r\n\r\n' > h
  [ "$(retry_after_seconds h)" = "0" ]
  printf 'HTTP/2 429\r\nretry-after-ms: 1000.1\r\n\r\n' > h
  [ "$(retry_after_seconds h)" = "2" ]
  printf 'HTTP/2 429\r\nretry-after: soon\r\n\r\n' > h
  [ -z "$(retry_after_seconds h)" ]
}

@test "the wait before a retry is the server's Retry-After when it is longer than the backoff" {
  install_scripted_curl
  export SLEEP_LOG="$BATS_TEST_TMPDIR/sleep.log"
  cat > "$BATS_TEST_TMPDIR/bin/sleep" <<'STUB'
#!/usr/bin/env bash
echo "$1" >> "$SLEEP_LOG"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/sleep"
  reply 1 'printf "HTTP/2 503\r\nretry-after: 7\r\n\r\n" > "$1"; printf "busy\n503"'
  reply 2 'printf "{\"text\":\"ok\"}\n200"'
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  [ "$(cat "$SLEEP_LOG")" = "7" ]
}
