#!/usr/bin/env bats

# Source-level assertions that are easier to express as grep than as behavior.

SCRIPT="${BATS_TEST_DIRNAME}/../whisper-stream"

@test "bash syntax is valid" {
  bash -n "$SCRIPT"
}

@test "help text mentions gpt-4o-mini-transcribe" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"gpt-4o-mini-transcribe"* ]]
}

@test "version flag works" {
  run "$SCRIPT" -V
  [ "$status" -eq 0 ]
  [[ "$output" == *"version"* ]]
}

@test "script does not invoke curl via eval" {
  run grep -nE 'eval[[:space:]]+\$?curl' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "script does not contain redundant soxi existence check" {
  run grep -n 'command -v soxi' "$SCRIPT"
  [ "$status" -ne 0 ]
}

# --- -v / --volume accepts percent, bare number, and dBFS -------------------

@test "volume option accepts percent notation (-v 1%)" {
  run "$SCRIPT" -v 1% -V
  [ "$status" -eq 0 ]
  [[ "$output" == *"version"* ]]
}

@test "volume option accepts bare number (-v 2)" {
  run "$SCRIPT" -v 2 -V
  [ "$status" -eq 0 ]
  [[ "$output" == *"version"* ]]
}

@test "volume option accepts dBFS notation (-v -30d)" {
  run "$SCRIPT" -v -30d -V
  [ "$status" -eq 0 ]
  [[ "$output" == *"version"* ]]
}

@test "volume option accepts fractional dBFS (-v -40.5d)" {
  run "$SCRIPT" -v -40.5d -V
  [ "$status" -eq 0 ]
  [[ "$output" == *"version"* ]]
}

@test "volume option rejects a following short flag as missing value" {
  run "$SCRIPT" -v -s
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing value"* ]]
}

@test "help text documents both percent and dBFS forms" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"dBFS"* ]] || [[ "$output" == *"-30d"* ]]
}

@test "version is 3.1.1" {
  run "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"3.1.1"* ]]
}

@test "help text mentions --api-url" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--api-url"* ]]
}

@test "help text no longer mentions -g/--granularities" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"--granularities"* ]]
  # Match the option-table form "-g, " specifically; allow other -g* tokens.
  [[ "$output" != *"-g, "* ]]
}

@test "main loop serializes convert_audio_to_text when backend is local" {
  # The local branch must NOT use background execution (&) because multiple
  # whisper-cli processes would contend for GPU resources. A future refactor
  # that accidentally reverts the split should fail this regression test.
  run awk '/if \[ "\$BACKEND" = "local" \]; then/,/else/' "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'convert_audio_to_text "$OUTPUT_FILE"'* ]]
  # Inside the local branch the call must not be backgrounded.
  ! echo "$output" | grep -E 'convert_audio_to_text "\$OUTPUT_FILE" &'
}
