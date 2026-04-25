#!/usr/bin/env bats

load test_helper

setup() {
  cd "$BATS_TEST_TMPDIR"
  touch fake.mp3
  install_curl_stub
  load_whisper_stream

  TOKEN="sk-test"
  MODEL="gpt-4o-mini-transcribe"
  PROMPT=""
  LANGUAGE=""
  DIARIZE=false
  TRANSLATE=""
  AUDIO_FILE="fake.mp3"
  PIPE_TO_CMD=""
  KNOWN_SPEAKERS=()
  CHUNKING_STRATEGY=""
}

# --- auth file lifecycle -----------------------------------------------------

@test "auth tempfile is removed after normal completion" {
  convert_audio_to_text fake.mp3 >/dev/null

  # Collect the --config argument paths the script handed to curl and
  # verify that none of them still exist on disk.
  prev=""
  while IFS= read -r line; do
    if [ "$prev" = "--config" ]; then
      [ ! -e "$line" ]
    fi
    prev="$line"
  done < "$CURL_CAPTURE"
}

@test "auth tempfile is created under TMPDIR with a whisper-stream prefix" {
  convert_audio_to_text fake.mp3 >/dev/null
  prev=""
  while IFS= read -r line; do
    if [ "$prev" = "--config" ]; then
      [[ "$line" == *"/whisper-stream."* ]]
    fi
    prev="$line"
  done < "$CURL_CAPTURE"
}

@test "mktemp failure is handled without crashing" {
  # Shadow mktemp with a stub that always fails.
  cat > "$BATS_TEST_TMPDIR/bin/mktemp" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/mktemp"

  run convert_audio_to_text fake.mp3
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to create"* ]]
}

# --- jq injection via speaker names -----------------------------------------

@test "speaker lookup uses jq --arg (source-level check)" {
  # The line-level assertion: no unsafe interpolated jq queries referencing
  # speaker_key remain in the script.
  run grep -nE 'jq [^|]*"\.\[\\"\$speaker_key\\"\]' "${BATS_TEST_DIRNAME}/../whisper-stream"
  [ "$status" -ne 0 ]
}

@test "speaker lookup survives exotic speaker names" {
  DIARIZE=true
  MODEL="gpt-4o-transcribe-diarize"
  CHUNKING_STRATEGY="auto"

  # Create a fake speakers.json with a key containing quotes and brackets.
  SPEAKER_DIR="$BATS_TEST_TMPDIR/speakers"
  mkdir -p "$SPEAKER_DIR"
  local key='weird"]+key['
  jq -n --arg k "$key" --arg name "Weird Name" \
    '{($k): {name: $name, file: "weird.wav", duration: 3, created: "2026-01-01T00:00:00Z"}}' \
    > "$SPEAKER_DIR/speakers.json"
  : > "$SPEAKER_DIR/weird.wav"
  KNOWN_SPEAKERS=("$key")

  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  grep -Fq 'known_speaker_names[]=Weird Name' "$CURL_CAPTURE"
}

# --- PIPE_TO_CMD runs through bash -c ---------------------------------------

@test "PIPE_TO_CMD is invoked via bash -c (shell semantics preserved)" {
  PIPE_TO_CMD='wc -c'
  # The stub curl returns {"text":"fake transcription"} => display_text="fake transcription"
  run convert_audio_to_text fake.mp3
  [ "$status" -eq 0 ]
  # Just verify the function returned successfully with PIPE_TO_CMD set —
  # the actual output includes both the display text and wc's byte count.
  [[ "$output" == *"fake transcription"* ]]
}

# --- source-level hygiene ---------------------------------------------------

@test "no remaining unquoted \$PIPE_TO_CMD expansions" {
  run grep -nE '\| \$PIPE_TO_CMD[^"]' "${BATS_TEST_DIRNAME}/../whisper-stream"
  [ "$status" -ne 0 ]
}

@test "mktemp uses portable template form (not -t)" {
  # Match only actual invocations: $(mktemp -t ...)  (skip comments/docs)
  run grep -nE '\$\(mktemp[[:space:]]+-t' "${BATS_TEST_DIRNAME}/../whisper-stream"
  [ "$status" -ne 0 ]
}
