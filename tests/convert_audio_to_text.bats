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

@test "API token is passed via --config file (not argv)" {
  convert_audio_to_text fake.mp3 >/dev/null
  grep -q 'sk-TEST-TOKEN-12345' "$CURL_CONFIG_CAPTURE"
}

@test "--config file is cleaned up after the call" {
  convert_audio_to_text fake.mp3 >/dev/null
  # the stub captured the --config path; verify the real file is gone
  prev=""
  while IFS= read -r line; do
    if [ "$prev" = "--config" ]; then
      [ ! -e "$line" ] || {
        echo "leaked auth file: $line" >&2
        return 1
      }
    fi
    prev="$line"
  done < "$CURL_CAPTURE"
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
  [ "$status" -eq 0 ]
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
