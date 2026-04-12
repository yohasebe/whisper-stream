#!/usr/bin/env bats

load test_helper

# Install a stub `whisper-cli` that captures the arguments it receives and
# writes a canned JSON file matching whisper.cpp's -oj output shape.
install_whisper_cli_stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export WCLI_CAPTURE="$BATS_TEST_TMPDIR/wcli_args.txt"
  : > "$WCLI_CAPTURE"

  cat > "$BATS_TEST_TMPDIR/bin/whisper-cli" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$WCLI_CAPTURE"
done
# Parse -of <prefix> to know where to put the JSON file.
of_prefix=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-of" ]; then
    of_prefix="$arg"
  fi
  prev="$arg"
done
if [ -n "$of_prefix" ]; then
  cat > "${of_prefix}.json" <<JSON
{
  "systeminfo": "stub",
  "model": {"type": "tiny"},
  "params": {"language": "en"},
  "result": {"language": "en"},
  "transcription": [
    {"timestamps": {"from":"00:00:00,000","to":"00:00:03,000"},
     "offsets":{"from":0,"to":3000},
     "text": " fake local transcription"}
  ]
}
JSON
fi
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/whisper-cli"
  # prepend to PATH so the stub wins over any system install
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

setup() {
  cd "$BATS_TEST_TMPDIR"
  touch fake.mp3
  install_curl_stub
  install_whisper_cli_stub
  load_whisper_stream

  # Create a fake model file so validate_config is happy.
  FAKE_MODEL="$BATS_TEST_TMPDIR/ggml-fake.bin"
  : > "$FAKE_MODEL"

  BACKEND="local"
  MODEL_PATH="$FAKE_MODEL"
  MODEL="gpt-4o-mini-transcribe"
  PROMPT=""
  LANGUAGE=""
  GRANULARITIES="none"
  DIARIZE=false
  REGISTER_SPEAKERS=false
  TRANSLATE=""
  AUDIO_FILE="fake.mp3"
  PIPE_TO_CMD=""
  KNOWN_SPEAKERS=()
  CHUNKING_STRATEGY=""
  STDOUT_MODE=false
  JSONL_MODE=false
  JSONL_SCHEMA_VERSION=1
  TOKEN="sk-unused-in-local-mode"
}

# --- validate_config for local backend --------------------------------------

@test "validate_config accepts local backend with valid model path" {
  run validate_config
  [ "$status" -eq 0 ]
}

@test "validate_config rejects unknown backend value" {
  BACKEND="nonsense"
  run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid backend"* ]]
}

@test "validate_config rejects local + --diarize" {
  DIARIZE=true
  run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"--diarize"* ]]
}

@test "validate_config rejects local + --register-speakers" {
  REGISTER_SPEAKERS=true
  run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"--register-speakers"* ]]
}

@test "validate_config rejects local + -g granularities" {
  GRANULARITIES="segment"
  run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"granularities"* ]]
}

@test "validate_config errors when model path is missing" {
  MODEL_PATH="$BATS_TEST_TMPDIR/does-not-exist.bin"
  run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"model not found"* ]]
}

@test "validate_config falls back to \$WHISPER_STREAM_MODEL env var" {
  MODEL_PATH=""
  WHISPER_STREAM_MODEL="$FAKE_MODEL"
  run validate_config
  [ "$status" -eq 0 ]
}

# --- convert_audio_to_text: local branch -----------------------------------

@test "local backend produces plain-text transcription" {
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  [[ "$output" == *"fake local transcription"* ]]
}

@test "local backend passes --model-path to whisper-cli via -m" {
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq -- "$FAKE_MODEL" "$WCLI_CAPTURE"
  grep -Fxq -- "-m" "$WCLI_CAPTURE"
}

@test "local backend passes -oj -nt -np to whisper-cli" {
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq -- "-oj" "$WCLI_CAPTURE"
  grep -Fxq -- "-nt" "$WCLI_CAPTURE"
  grep -Fxq -- "-np" "$WCLI_CAPTURE"
}

@test "local backend passes language via -l" {
  LANGUAGE="ja"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq -- "-l" "$WCLI_CAPTURE"
  grep -Fxq -- "ja" "$WCLI_CAPTURE"
}

@test "local backend passes prompt via --prompt" {
  PROMPT="this is a technical discussion"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq -- "--prompt" "$WCLI_CAPTURE"
  grep -Fxq -- "this is a technical discussion" "$WCLI_CAPTURE"
}

@test "local backend passes -tr when --translate is set" {
  TRANSLATE=true
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq -- "-tr" "$WCLI_CAPTURE"
}

@test "local backend does NOT hit the curl stub (no API call)" {
  convert_audio_to_text fake.mp3 >/dev/null
  [ ! -s "$CURL_CAPTURE" ]
}

# --- local + JSONL ---------------------------------------------------------

@test "local backend + --jsonl emits valid JSON" {
  JSONL_MODE=true
  STDOUT_MODE=true
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  local json
  json=$(printf '%s\n' "$output" | grep '^{' | head -1)
  echo "$json" | jq -e . >/dev/null
  [ "$(echo "$json" | jq -r '.version')" = "1" ]
  [ "$(echo "$json" | jq -r '.text')" = "fake local transcription" ]
  # Model field should carry a local: prefix with the file basename
  [[ "$(echo "$json" | jq -r '.model')" == local:ggml-fake.bin ]]
}

# --- no leftover temp files ------------------------------------------------

@test "local backend does not leave whisper-stream-local tempfiles behind" {
  convert_audio_to_text fake.mp3 >/dev/null
  # Both the prefix file and the .json should be gone after the function.
  run find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'whisper-stream-local.*'
  [ -z "$output" ]
}

# --- error handling: failing whisper-cli ----------------------------------

@test "local backend failure does not emit error sentinel on stdout" {
  # Replace the stub with one that fails without writing JSON.
  cat > "$BATS_TEST_TMPDIR/bin/whisper-cli" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/whisper-cli"

  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  # Stdout should be empty (utterance skipped), stderr (merged by bats) carries a warning.
  [[ "$output" != *"[local backend error]"* ]]
  [[ "$output" == *"local backend failed"* ]]
}

@test "local backend failure in jsonl mode does not emit a json record" {
  cat > "$BATS_TEST_TMPDIR/bin/whisper-cli" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/whisper-cli"

  JSONL_MODE=true
  STDOUT_MODE=true
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  # Output must contain no JSON line — the utterance is silently skipped.
  run grep -c '^{' <(printf '%s\n' "$output")
  [ "$output" = "0" ]
}

# --- warnings on ignored backend-specific options ------------------------

@test "validate_config warns when -m is set for backend=local" {
  BACKEND="local"
  MODEL="gpt-4o-transcribe"
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"-m/--model is ignored"* ]]
}

@test "validate_config does NOT warn when -m is at default for backend=local" {
  BACKEND="local"
  MODEL="gpt-4o-mini-transcribe"
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" != *"-m/--model is ignored"* ]]
}

@test "validate_config warns when --model-path is set for backend=api" {
  BACKEND="api"
  MODEL_PATH="/tmp/some-model.bin"
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"--model-path is ignored"* ]]
}
