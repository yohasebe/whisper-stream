#!/usr/bin/env bats

load test_helper

setup() {
  load_whisper_stream

  BACKEND="api"
  MODEL="gpt-4o-mini-transcribe"
  MODEL_PATH=""
  GRANULARITIES="none"
  DIARIZE=false
  REGISTER_SPEAKERS=false
  TRANSLATE=""
  AUDIO_FILE=""
  CHUNKING_STRATEGY=""
  JSONL_MODE=false
}

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

@test "accepts whisper-1 silently" {
  MODEL="whisper-1"
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

@test "accepts snapshot name without warning (gpt-4o-mini-transcribe-2025-12-15)" {
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

@test "rejects granularities on gpt-4o-mini-transcribe" {
  MODEL="gpt-4o-mini-transcribe"
  GRANULARITIES="segment"
  run validate_config
  [ "$status" -ne 0 ]
}

@test "accepts granularities on whisper-1" {
  MODEL="whisper-1"
  GRANULARITIES="segment"
  run validate_config
  [ "$status" -eq 0 ]
}

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

# --- --translate (API backend) must be whisper-1 ---------------------------

@test "accepts --translate with whisper-1 on api backend" {
  MODEL="whisper-1"
  TRANSLATE=true
  run validate_config
  [ "$status" -eq 0 ]
}

@test "rejects --translate with gpt-4o-mini-transcribe on api backend" {
  MODEL="gpt-4o-mini-transcribe"
  TRANSLATE=true
  run validate_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"--translate"* ]]
  [[ "$output" == *"whisper-1"* ]]
}

@test "rejects --translate with gpt-4o-transcribe on api backend" {
  MODEL="gpt-4o-transcribe"
  TRANSLATE=true
  run validate_config
  [ "$status" -ne 0 ]
}

@test "rejects --translate with gpt-4o-transcribe-diarize on api backend" {
  MODEL="gpt-4o-transcribe-diarize"
  TRANSLATE=true
  DIARIZE=false
  run validate_config
  [ "$status" -ne 0 ]
}

@test "warns when --language is combined with --translate" {
  MODEL="whisper-1"
  TRANSLATE=true
  LANGUAGE="ja"
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignored with --translate"* ]]
}

@test "does not warn when --translate is used without --language" {
  MODEL="whisper-1"
  TRANSLATE=true
  LANGUAGE=""
  run validate_config
  [ "$status" -eq 0 ]
  [[ "$output" != *"ignored with --translate"* ]]
}
