#!/usr/bin/env bats

load test_helper

setup() {
  cd "$BATS_TEST_TMPDIR"
  touch fake.mp3
  install_curl_stub
  load_whisper_stream

  TOKEN="sk-TEST-TOKEN-12345"
  MODEL="gpt-4o-mini-transcribe"
  PROMPT=""
  LANGUAGE=""
  GRANULARITIES="none"
  DIARIZE=false
  TRANSLATE=""
  AUDIO_FILE="fake.mp3"  # suppress rm -f inside convert_audio_to_text
  PIPE_TO_CMD=""
  KNOWN_SPEAKERS=()
  CHUNKING_STRATEGY=""
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

@test "default response_format is json for gpt-4o-mini-transcribe" {
  MODEL="gpt-4o-mini-transcribe"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'response_format=json' "$CURL_CAPTURE"
  run grep -Fxq 'response_format=verbose_json' "$CURL_CAPTURE"
  [ "$status" -ne 0 ]
}

@test "response_format is verbose_json for whisper-1 with granularities" {
  MODEL="whisper-1"
  GRANULARITIES="segment"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'response_format=verbose_json' "$CURL_CAPTURE"
}

@test "response_format is json for whisper-1 without granularities" {
  MODEL="whisper-1"
  GRANULARITIES="none"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'response_format=json' "$CURL_CAPTURE"
}

@test "snapshot model name is passed through to curl" {
  MODEL="gpt-4o-mini-transcribe-2025-12-15"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'model=gpt-4o-mini-transcribe-2025-12-15' "$CURL_CAPTURE"
}

@test "translate mode uses translations endpoint" {
  MODEL="whisper-1"
  TRANSLATE=true
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'https://api.openai.com/v1/audio/translations' "$CURL_CAPTURE"
}

@test "transcribe mode uses transcriptions endpoint" {
  TRANSLATE=""
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'https://api.openai.com/v1/audio/transcriptions' "$CURL_CAPTURE"
}

@test "translate mode does NOT send language form field even when LANGUAGE is set" {
  MODEL="whisper-1"
  TRANSLATE=true
  LANGUAGE="ja"
  convert_audio_to_text fake.mp3 >/dev/null
  # The /audio/translations endpoint rejects any language value other
  # than 'en'. We drop the field entirely so whisper auto-detects.
  run grep -F 'language=' "$CURL_CAPTURE"
  [ "$status" -ne 0 ]
}

@test "transcribe mode DOES send language form field when LANGUAGE is set" {
  MODEL="gpt-4o-mini-transcribe"
  TRANSLATE=""
  LANGUAGE="ja"
  convert_audio_to_text fake.mp3 >/dev/null
  grep -Fxq 'language=ja' "$CURL_CAPTURE"
}
