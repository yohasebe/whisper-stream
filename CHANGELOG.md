# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project tries to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
loosely — additive features are minor bumps, breaking user-facing behavior is
a major bump.

This file is updated when substantive changes happen; small refactors,
comment tweaks, and cosmetic fixes are not recorded here.

## [2.0.0] — 2026-04-12

Version 2.0.0 bundles both the model/diarization work that preceded the
release cycle and the maintenance pass that hardened the script for
pipe-native shell workflows and introduced the local `whisper.cpp` backend.

### ⚠️ Breaking

- **Default model changed** from `whisper-1` to `gpt-4o-mini-transcribe`
  for better transcription quality. Pass `-m whisper-1` explicitly to
  keep the old behavior. Timestamp granularities still require whisper-1.

### Added

- **Local `whisper.cpp` backend** (`--backend local`). Runs transcription
  on your own machine via the `whisper-cli` binary from
  [`whisper-cpp`](https://github.com/ggml-org/whisper.cpp). Supports
  `--language`, `--prompt`, `--translate`, and pipe-native modes. Model
  file resolved from `--model-path`, `$WHISPER_STREAM_MODEL`, or
  `~/.whisper-stream/models/ggml-base.en.bin`. Enables continuous
  dictation that is free, offline, and private.
- **Pipe-native `--stdout` mode**. Transcriptions are emitted to stdout
  only; banner, clipboard copy, file saving, spinner, and retry
  indicators are all suppressed. Designed for shell pipelines such as
  `whisper-stream --stdout | your-tool`.
- **`--jsonl` output mode**. Emits one JSON object per utterance with
  schema `{version, ts, model, duration, text}`. Implies `--stdout`.
  Enables programmatic routing, logging, and AI-agent integration. Not
  compatible with `--diarize` (schema v1).
- **dBFS threshold notation** for `-v`/`--volume`. Accepts both percent
  (`1%`, `2`) and dBFS (`-30d`, `-40.5d`). Percent remains the default
  for backwards compatibility.
- **Multiple API models** via `-m`: `gpt-4o-transcribe`,
  `gpt-4o-mini-transcribe` (default), `gpt-4o-transcribe-diarize`,
  in addition to the original `whisper-1`.
- **Speaker diarization** (`--diarize`) and interactive known-speaker
  registration (`--register-speakers`, `--list-speakers`,
  `--delete-speaker`, `--speaker-dir`) for
  `gpt-4o-transcribe-diarize`.
- TTY auto-detection: spinner and retry indicators are suppressed
  automatically when stdout/stderr is not a terminal, even without
  `--stdout`.
- Unit test suite (`tests/`, 80+ bats-core tests) that sources the
  script in library mode and exercises individual functions against
  `curl` and `whisper-cli` stubs. No real audio or network calls.

### Changed

- **Model validation is now a warning, not a hard error** for unknown
  model names. This allows dated API snapshots such as
  `gpt-4o-mini-transcribe-2025-12-15` to pass through without waiting
  for a script update.
- **`whisper-1` default response format** is now `json` instead of
  `verbose_json`. Saved transcription files are `.txt` when no `-g` is
  given, aligning with the documented behavior. Pass `-g segment` or
  `-g word` to opt back into JSON output with timestamps.
- **`PIPE_TO_CMD` (`-p2`) invocation** is now explicit: the user-supplied
  command runs through `bash -c` rather than via unquoted expansion.
  Behavior is unchanged for typical shell pipelines (`'wc -w'`).
- In real-time mode with `--backend local`, `convert_audio_to_text` is
  called synchronously instead of in the background, to avoid multiple
  `whisper-cli` processes contending for GPU resources.
- Non-default backend-specific options now emit a stderr warning when
  ignored (`-m` with `--backend local`, `--model-path` with
  `--backend api`).
- `display_settings` now reports the backend and, for the local
  backend, the ggml model basename instead of the stale API model name.

### Fixed

- `-v` parser no longer rejects dBFS values that start with `-`
  (previously the guard treated `-30d` as a missing value).
- `record_speaker_sample` no longer guards `soxi` with a redundant
  `command -v` check — SoX is already a hard dependency.
- Local backend failures no longer emit the literal string
  `[local backend error]` to stdout / clipboard / JSONL. The affected
  utterance is skipped and a warning is logged to stderr.
- `handle_exit` no longer emits `\r\e[K\n` to stdout in pipe-native
  mode, which previously polluted downstream consumers like `jq`
  (`parse error: Invalid numeric literal`).
- `--translate` (`-tr`) with a non-`whisper-1` model is now rejected
  at startup with a clear error message pointing the user to
  `-m whisper-1 -tr`. Previously the request reached the OpenAI
  `/audio/translations` endpoint and came back with an opaque
  `Invalid URL` error that was stored as the transcription text.
- `--translate` combined with `--language` (`-l`) no longer sends the
  user-specified language to the API. The OpenAI translations endpoint
  rejects any `language` value other than `"en"`, and Whisper
  auto-detects the source language anyway. A warning is printed when
  `-l` is ignored so the user knows.

### Security

- **OpenAI bearer token is no longer visible in `ps`.** Previously the
  `Authorization: Bearer …` header was passed as a curl argument and
  appeared in the process argument list. It is now written to a private
  `mktemp` config file (mode 0600), passed via `curl --config`, and
  cleaned up on normal return and on signal termination (`EXIT` trap).
- **`eval $curl_command` removed.** User-controlled strings
  (`--prompt`, `--language`, audio file paths) were previously
  interpolated into a shell command string and passed through `eval`,
  which allowed command substitution like `$(...)` and `` `...` `` to
  execute. curl is now invoked with a bash array of arguments.
- **jq queries over speaker metadata use `--arg` / `--argjson`** instead
  of string interpolation. Speaker names containing `"`, `]`, or other
  metacharacters no longer break queries or enable injection.
- `mktemp` now uses a portable template
  (`"${TMPDIR:-/tmp}/whisper-stream.XXXXXX"`) instead of the
  non-portable `-t` flag, which behaves differently on GNU coreutils
  vs BSD.
