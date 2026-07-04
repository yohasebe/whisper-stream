#!/usr/bin/env bats

# Tests for record_utterance() — the seam between whisper-stream and the
# audio-capture tool (currently SoX). A future migration (ffmpeg, pw-record,
# etc.) should only need to change this one function, and these tests pin
# down the contract it must honour.

load test_helper

# Install fake `rec` and `sox` binaries that capture their arguments and
# emulate the pipeline: rec emits fake PCM on stdout; sox reads stdin and
# writes it to the output file (its last argument).
install_recorder_stubs() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export REC_CAPTURE="$BATS_TEST_TMPDIR/rec_args.txt"
  export SOX_CAPTURE="$BATS_TEST_TMPDIR/sox_args.txt"
  : > "$REC_CAPTURE"
  : > "$SOX_CAPTURE"

  cat > "$BATS_TEST_TMPDIR/bin/rec" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$REC_CAPTURE"
done
printf 'FAKEPCM'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/rec"

  cat > "$BATS_TEST_TMPDIR/bin/sox" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$SOX_CAPTURE"
done
out="${@: -1}"
cat > "$out"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/sox"

  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

setup() {
  cd "$BATS_TEST_TMPDIR"
  install_recorder_stubs
  load_whisper_stream

  MIN_VOLUME="1%"
  SILENCE_LENGTH="1.5"
  DURATION=0
}

# --- function contract -------------------------------------------------------

@test "record_utterance function exists" {
  type record_utterance
}

@test "record_utterance passes silence-detection parameters to the recorder" {
  MIN_VOLUME="2%"
  SILENCE_LENGTH="2"
  record_utterance out.mp3
  grep -Fxq -- "silence" "$REC_CAPTURE"
  grep -Fxq -- "2%" "$REC_CAPTURE"
  grep -Fxq -- "2" "$REC_CAPTURE"
}

@test "record_utterance passes dBFS threshold verbatim" {
  MIN_VOLUME="-30d"
  record_utterance out.mp3
  grep -Fxq -- "-30d" "$REC_CAPTURE"
}

@test "record_utterance adds a duration limit when DURATION > 0" {
  DURATION=60
  record_utterance out.mp3
  grep -Fxq -- "trim" "$REC_CAPTURE"
  grep -Fxq -- "60" "$REC_CAPTURE"
}

@test "record_utterance omits the duration limit when DURATION is 0" {
  DURATION=0
  record_utterance out.mp3
  run grep -Fxq -- "trim" "$REC_CAPTURE"
  [ "$status" -ne 0 ]
}

@test "record_utterance writes the captured audio to the target file" {
  record_utterance out.mp3
  [ -s out.mp3 ]
  grep -q 'FAKEPCM' out.mp3
}

@test "record_utterance encodes to the file path it was given (not a global)" {
  record_utterance custom_name.mp3
  grep -Fxq -- "custom_name.mp3" "$SOX_CAPTURE"
  [ -s custom_name.mp3 ]
}

# --- seam integrity (source-level) -------------------------------------------

@test "utterance-recording pipeline exists in exactly one place" {
  # The silence-detection recording pipeline must live only inside
  # record_utterance. If this count grows, someone bypassed the seam.
  local count
  count=$(grep -c 'silence 1 0.1' "$BATS_TEST_DIRNAME/../whisper-stream")
  [ "$count" -eq 1 ]
}

@test "main loop records via record_utterance" {
  grep -q 'record_utterance "\$OUTPUT_FILE"' "$BATS_TEST_DIRNAME/../whisper-stream"
}
