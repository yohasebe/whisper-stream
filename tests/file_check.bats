#!/usr/bin/env bats

# Tests for check_audio_file() — the -f input validation.
# The 25 MB size limit and the extension whitelist are OpenAI API
# constraints; the local backend (whisper-cli) must not be bound by them.

load test_helper

setup() {
  cd "$BATS_TEST_TMPDIR"
  load_whisper_stream
  BACKEND="api"
}

@test "accepts flac, ogg, and opus for the api backend" {
  local ext
  for ext in flac ogg opus; do
    printf 'x' > "sample.$ext"
    run check_audio_file "sample.$ext"
    [ "$status" -eq 0 ]
  done
}

@test "accepts uppercase extensions" {
  printf 'x' > SAMPLE.MP3
  run check_audio_file SAMPLE.MP3
  [ "$status" -eq 0 ]
}

@test "rejects unacceptable formats for the api backend" {
  printf 'x' > sample.exe
  run check_audio_file sample.exe
  [ "$status" -ne 0 ]
}

@test "local backend skips format and size checks" {
  BACKEND="local"
  printf 'x' > sample.exe
  run check_audio_file sample.exe
  [ "$status" -eq 0 ]
}

@test "local backend still requires an existing non-empty file" {
  BACKEND="local"
  run check_audio_file does-not-exist.wav
  [ "$status" -ne 0 ]
  : > empty.wav
  run check_audio_file empty.wav
  [ "$status" -ne 0 ]
}
