#!/usr/bin/env bats

load test_helper

setup() {
  load_whisper_stream

  BACKEND="api"
  MODEL="gpt-4o-mini-transcribe"
  MODEL_PATH=""
  API_URL=""
  DIARIZE=false
  REGISTER_SPEAKERS=false
  TRANSLATE=""
  AUDIO_FILE=""
  CHUNKING_STRATEGY=""
  JSONL_MODE=false
}

# --- model whitelist ---------------------------------------------------------

@test "accepts gpt-4o-mini-transcribe silently" {
  MODEL="gpt-4o-mini-transcribe"
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" != *"Warning"* ]]
}

@test "accepts gpt-4o-transcribe silently" {
  MODEL="gpt-4o-transcribe"
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" != *"Warning"* ]]
}

@test "accepts gpt-4o-transcribe-diarize silently" {
  MODEL="gpt-4o-transcribe-diarize"
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" != *"Warning"* ]]
}

@test "accepts dated snapshot without warning" {
  MODEL="gpt-4o-mini-transcribe-2025-12-15"
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" != *"Warning"* ]]
}

@test "warns on unrecognized model but does not exit" {
  MODEL="some-future-model-v9"
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"Warning"* ]]
}

@test "rejects whisper-1 with a clear migration message" {
  MODEL="whisper-1"
  run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"whisper-1"* ]]
  [[ "$output" == *"retired"* ]] || [[ "$output" == *"no longer"* ]]
}

# --- diarization -------------------------------------------------------------

@test "rejects --diarize without diarize-capable model" {
  MODEL="gpt-4o-mini-transcribe"
  DIARIZE=true
  run validate_config
  [ "$status" -ne 0 ]
}

@test "accepts --diarize with diarize-capable model" {
  MODEL="gpt-4o-transcribe-diarize"
  DIARIZE=true
  run validate_config
  [ "$status" -eq 0 ]
}

@test "accepts --diarize with diarize snapshot model" {
  MODEL="gpt-4o-transcribe-diarize-2025-12-15"
  DIARIZE=true
  run validate_config
  [ "$status" -eq 0 ]
}

@test "sets chunking_strategy=auto when diarize enabled" {
  MODEL="gpt-4o-transcribe-diarize"
  DIARIZE=true
  validate_config
  [ "$CHUNKING_STRATEGY" = "auto" ]
}

# --- --translate (local backend only since v3.0) ----------------------------

@test "rejects --translate on api backend regardless of model" {
  BACKEND="api"
  MODEL="gpt-4o-mini-transcribe"
  TRANSLATE=true
  run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"--translate"* ]]
  [[ "$output" == *"local"* ]]
}

@test "rejects --translate on api backend with gpt-4o-transcribe" {
  BACKEND="api"
  MODEL="gpt-4o-transcribe"
  TRANSLATE=true
  run validate_config
  [ "$status" -ne 0 ]
}

# --- --api-url notes --------------------------------------------------------

@test "warns when --api-url is set with local backend" {
  BACKEND="local"
  # Provide a fake model so we get past the existence check.
  FAKE_MODEL="$BATS_TEST_TMPDIR/fake.bin"
  : > "$FAKE_MODEL"
  MODEL_PATH="$FAKE_MODEL"
  API_URL="http://localhost:2022/v1/audio/transcriptions"
  # whisper-cli must exist for validate_config to return 0; skip if absent.
  if ! command -v whisper-cli >/dev/null 2>&1; then
    skip "whisper-cli not installed"
  fi
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"--api-url is ignored"* ]]
}

# --- external dependency checks ----------------------------------------------
#
# validate_config must verify the external commands the chosen mode actually
# needs, and no more: jq always, curl for the api backend, rec/sox only for
# real-time recording (file mode must keep working on machines with no mic).

# Build a directory containing symlinks to only the named commands, so the
# dependency checks can be exercised with a controlled PATH.
make_dep_path() {
  local dir="$BATS_TEST_TMPDIR/depbin"
  mkdir -p "$dir"
  local c
  for c in "$@"; do
    ln -sf "$(command -v "$c")" "$dir/$c"
  done
  echo "$dir"
}

@test "validate_config errors when jq is missing" {
  local d
  d=$(make_dep_path curl rec sox)
  PATH="$d" run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"jq"* ]]
}

@test "validate_config errors when curl is missing for the api backend" {
  local d
  d=$(make_dep_path jq rec sox)
  PATH="$d" run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"curl"* ]]
}

@test "validate_config errors when rec/sox are missing in real-time mode" {
  local d
  d=$(make_dep_path jq curl)
  PATH="$d" run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"rec"* ]] || [[ "$output" == *"sox"* ]]
}

@test "file mode (-f) does not require rec/sox" {
  AUDIO_FILE="fake.mp3"
  local d
  d=$(make_dep_path jq curl)
  PATH="$d" run validate_config
  [ "$status" -eq 0 ]
}

# --- -p2 / --pipe-to combined with pipe-native output ------------------------

@test "validate_config warns when --pipe-to is combined with pipe-native output" {
  PIPE_TO_CMD="wc -c"
  STDOUT_MODE=true
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"pipe-to"* ]]
}
