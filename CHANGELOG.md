# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project tries to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
loosely — additive features are minor bumps, breaking user-facing behavior is
a major bump.

This file is updated when substantive changes happen; small refactors,
comment tweaks, and cosmetic fixes are not recorded here.

## [3.1.0] — 2026-05-11

### Added

- **`--vad` option** (local backend only). Enables whisper.cpp's built-in
  Voice Activity Detection, which filters non-speech regions inside each
  chunk before transcription. This improves accuracy and reduces common
  hallucinations such as repeated "Thank you for watching" on silence.
  Requires a ggml-formatted VAD model. Falls back to
  `$WHISPER_STREAM_VAD_MODEL` and then
  `~/.whisper-stream/models/ggml-silero-v5.1.2.bin`. A download URL is
  printed when the file is missing.
- **`--vad-model-path`** option to override the VAD model location.

### Notes

- `--vad` is **not** a replacement for the SoX silence detection in the
  recording loop. It only refines what whisper.cpp does with each chunk
  the recording loop produces. SoX false positives are unaffected — for
  those, see the longer-term ffmpeg migration discussion in CLAUDE.md.
- `--vad` is rejected on the API backend (`/v1/audio/transcriptions`
  has no equivalent flag).

## [3.0.0] — 2026-04-12

This release prunes features that depend on the `whisper-1` model — which
OpenAI is retiring on 2026-06-01 along with the original `gpt-4o-transcribe`
and `gpt-4o-mini-transcribe` snapshots — and adds support for self-hosted
OpenAI-compatible endpoints (most notably whisper.cpp's `whisper-server`).
The model slugs that this script uses now auto-track newer snapshots, so
no version pinning is required from end users.

### ⚠️ Breaking

- **`whisper-1` is no longer accepted** as a model name. The OpenAI API
  retires it on 2026-06-01. Selecting it now produces a clear error at
  startup pointing at `gpt-4o-mini-transcribe` (default) or
  `gpt-4o-transcribe`. For translation, the message points at the local
  backend.
- **`-g` / `--granularities` removed.** Timestamp granularities only
  worked with `whisper-1`. There is no equivalent on the surviving
  models.
- **`--translate` (`-tr`) is now local-only.** The OpenAI
  `/audio/translations` endpoint is whisper-1-specific and goes away in
  June 2026. `whisper-cli` (the local backend) still supports
  translation natively, so `--backend local --translate` continues to
  work. Using `--translate` with the API backend now exits with a clear
  migration message.

### Added

- **`--api-url` option** to override the API endpoint. Lets you point
  whisper-stream at a self-hosted OpenAI-compatible server such as
  whisper.cpp's `whisper-server`. When `--api-url` is set, the API token
  is optional, so you can run end-to-end without an OpenAI key. Note
  that audio and any token you supply are sent to whatever URL you
  specify, so only use this with endpoints you trust.
- **API error responses are now skipped, not displayed.** When the API
  returns a structured `{"error": ...}` payload (rate limit, bad key,
  invalid parameter, etc.), the affected utterance is dropped with a
  warning on stderr instead of being treated as a transcription. The
  `[api error message]` no longer ends up on the clipboard or in JSONL.
- **Short-utterance skip** (`MIN_AUDIO_DURATION`, default 0.3s).
  Recordings shorter than the threshold — typically false positives
  from SoX silence detection — are dropped before reaching the
  backend, which saves API calls on always-on setups.
- **`display_settings` now reports the backend and API URL** when set,
  and shows the local model basename instead of the unused API model
  slug under `--backend local`.

### Removed

- The `/audio/translations` URL branch (no longer reachable).
- The `verbose_json` response format and all `timestamp_granularities`
  form-field handling.
- All `whisper-1` model special-casing.
- The deprecated warning that fired when `--language` was combined with
  `--translate`; the new validation makes the warning unnecessary.

### Notes

- Default model is still the `gpt-4o-mini-transcribe` slug. OpenAI has
  historically rolled slugs forward to newer snapshots (e.g. the
  `gpt-realtime-mini` slug was rolled forward to the 2025-12-15 snapshot
  on 2026-01-13), so this should keep working without script changes.
  If you want a pinned snapshot, pass it explicitly:
  `-m gpt-4o-mini-transcribe-2025-12-15`.

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
