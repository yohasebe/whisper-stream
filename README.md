# Whisper Stream Speech-to-Text Transcriber

![whisper-stream](https://github.com/yohasebe/whisper-stream/assets/18207/7b419ba0-a621-40ac-82c6-9c498e038e0d)

**whisper-stream** is a single bash script for **real-time speech-to-text**. It records audio, detects silence between speech segments, and transcribes each segment using either the [OpenAI speech-to-text API](https://platform.openai.com/docs/guides/speech-to-text) or a local [whisper.cpp](https://github.com/ggml-org/whisper.cpp) binary.

The script works as a **pipe-native CLI primitive**: with `--stdout` or `--jsonl`, transcriptions flow to stdout with no side effects, so you can compose them with `jq`, shell loops, tmux panes, or any command-line AI coding agent. Without those flags, transcriptions are copied to the system clipboard and optionally saved as files.

Use cases range from one-off dictation to always-on local transcription for voice-driven shell workflows.

## Features

- **Pipe-native output**: `--stdout` for plain text and `--jsonl` for one JSON object per utterance, both suitable for composition with shell tools and AI agents
- **Two backends**: OpenAI's speech-to-text API for quality and language coverage, or local `whisper.cpp` for free, offline, private continuous dictation
- **Multiple output modes**: plain text, JSON Lines, clipboard copy, or saved files — pick the right one for your workflow
- **Multiple API models**: `gpt-4o-transcribe`, `gpt-4o-mini-transcribe` (default), `gpt-4o-transcribe-diarize`
- **Speaker diarization** with optional known-speaker registration (API backend, `gpt-4o-transcribe-diarize` only)
- **Real-time or file mode** with silence-based utterance segmentation

## Installation

### Homebrew (Recommended)

Run the following commands:

```
> brew tap yohasebe/whisper-stream
> brew install whisper-stream
```

That's it! The `whisper-stream` command should now be available in your terminal.

### Manual Installation

Dependencies: `curl`, `jq`, `sox` (plus `xclip` on Linux). Optional: `whisper-cpp` for `--backend local` — see [Local backend](#local-backend-whispercpp).

```bash
brew install curl jq sox                    # macOS
sudo apt-get install curl jq sox xclip      # Debian/Ubuntu
```

Then place `whisper-stream` somewhere in your `$PATH` and make it executable:

```bash
install -m 755 whisper-stream /usr/local/bin/
```

## Usage

You can start the script with the following command:

```bash
> whisper-stream [options]
```

The available options are:

**Recording Options:**
- `-v, --volume <value>`: Minimum volume threshold, as percent (`1%`) or dBFS (`-30d`). Default: `1%` (≈ -40 dBFS).
- `-s, --silence <value>`: Set the minimum silence length (default: 1.5)
- `-o, --oneshot`: Enable one-shot mode
- `-d, --duration <value>`: Set the recording duration in seconds (default: 0, continuous)
- `-f, --file <value>`: Set the audio file to be transcribed

**Backend Options:**
- `-b, --backend <value>`: Transcription backend: `api` (OpenAI or compatible, default) or `local` (whisper.cpp, runs on your machine). See [Local backend](#local-backend-whispercpp) below.
- `--model-path <file>`: Path to a ggml model file for the local backend. Falls back to `$WHISPER_STREAM_MODEL` and then `~/.whisper-stream/models/ggml-base.en.bin`.
- `--api-url <url>`: Override the API endpoint. Useful for self-hosted OpenAI-compatible servers such as whisper.cpp's `whisper-server`. When set, the token is optional.
- `--vad`: (local backend only) Use whisper.cpp's built-in Voice Activity Detection to filter non-speech regions inside each chunk. Reduces hallucinations and improves accuracy. Requires a VAD model.
- `--vad-model-path <file>`: Path to a ggml VAD model. Falls back to `$WHISPER_STREAM_VAD_MODEL` and then `~/.whisper-stream/models/ggml-silero-v5.1.2.bin`.

**API Options (backend=api):**
- `-t, --token <value>`: Set the API token (only required for the OpenAI endpoint)
- `-m, --model <value>`: Set the model. Any name is passed through to the API; unknown names only produce a warning so you can opt into dated snapshots such as `gpt-4o-mini-transcribe-2025-12-15`. Known values: `gpt-4o-transcribe`, `gpt-4o-mini-transcribe` (default), `gpt-4o-transcribe-diarize`.
- `-r, --prompt <value>`: Set the prompt (works on both backends)
- `-l, --language <value>`: Set the input language in ISO-639-1 format
- `-tr, --translate`: Translate the transcribed text to English (local backend only)

**Output Options:**
- `-p, --path <value>`: Set the output directory path to create the transcription file
- `-p2, --pipe-to <cmd>`: Pipe the transcribed text to the specified command (e.g., 'wc -w')
- `-q, --quiet`: Suppress the banner and settings
- `--stdout`: Print transcriptions to stdout only. Suppresses banner, clipboard, file output, and progress indicators. Intended for shell pipelines.
- `--jsonl`: Emit one JSON object per utterance: `{version, ts, model, duration, text}`. Implies `--stdout`. Not compatible with `--diarize`. In real-time mode with the API backend, lines may arrive out of speaking order — sort by `ts` or use `--oneshot` if strict order matters.

**Diarization Options (gpt-4o-transcribe-diarize only):**
- `--diarize`: Enable speaker diarization
- `--register-speakers`: Interactively register known speakers (file mode only)
- `--list-speakers`: List saved speaker samples
- `--delete-speaker <name>`: Delete a saved speaker sample
- `--speaker-dir <path>`: Custom directory for speaker samples (default: ~/.whisper-stream/speakers)

**Other Options:**
- `-V, --version`: Show the version number
- `-h, --help`: Display the help message

## Examples

```bash
# Default: continuous recording, copy to clipboard
whisper-stream

# Specify input language (ISO-639-1)
whisper-stream -l ja

# Translate to English (requires the local backend)
whisper-stream --backend local --translate

# One-shot recording with tighter thresholds, saved to a directory
whisper-stream -v -35d -s 2 -o -p ~/Desktop

# Transcribe an existing file
whisper-stream -f ~/Desktop/interview.mp3 -l en

# Meeting transcription with speaker diarization
whisper-stream -f meeting.mp3 -m gpt-4o-transcribe-diarize --diarize

# Pipe-native: stream transcriptions into any shell tool
whisper-stream --stdout | your-tool

# Structured JSONL output, one object per utterance
whisper-stream --jsonl | jq -r .text
```

## Local backend (whisper.cpp)

In addition to the OpenAI API, `whisper-stream` can drive a local
[`whisper.cpp`](https://github.com/ggml-org/whisper.cpp) binary. This makes
continuous dictation free, offline, and private — useful when you want to run
speech-to-text all day without API cost or when you need to work in
network-isolated environments.

### Setup

```bash
# Install whisper.cpp (provides the `whisper-cli` binary)
brew install whisper-cpp     # macOS
# or build from source: https://github.com/ggml-org/whisper.cpp

# Download a ggml model file
mkdir -p ~/.whisper-stream/models
curl -L -o ~/.whisper-stream/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

# Optional: VAD model for --vad
curl -L -o ~/.whisper-stream/models/ggml-silero-v5.1.2.bin \
  https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin
```

See the [whisper.cpp model list](https://huggingface.co/ggerganov/whisper.cpp/tree/main) for other sizes and languages.

### Usage

```bash
# Uses the default model path (~/.whisper-stream/models/ggml-base.en.bin)
whisper-stream --backend local

# Point at a specific model
whisper-stream --backend local --model-path ~/models/your-model.bin

# Or via the environment variable
WHISPER_STREAM_MODEL=~/models/your-model.bin whisper-stream -b local

# Combines with pipe-native modes
whisper-stream -b local --jsonl | jq -r '.text'
```

### Feature matrix (local vs API)

| Feature                            | `api` | `local` |
|------------------------------------|:-----:|:-------:|
| Basic transcription                |   ✓   |    ✓    |
| `--language`, `--prompt`           |   ✓   |    ✓    |
| `--translate` (to English)         |   –   |    ✓    |
| `--vad` (built-in VAD)             |   –   |    ✓    |
| `--stdout`, `--jsonl`              |   ✓   |    ✓    |
| `--diarize` / speaker registration |   ✓   |    –    |

### Real-time mode notes

- Per-utterance latency depends on the model size. `ggml-tiny.en` is roughly half a second on Apple Silicon; larger models scale up.
- The local backend serializes utterances to avoid GPU contention between concurrent `whisper-cli` processes.
- On `whisper-cli` errors the affected utterance is skipped with a warning on stderr.

### Self-hosted whisper.cpp server (`--api-url`)

If you run whisper.cpp's `whisper-server` (which exposes an OpenAI-compatible
HTTP endpoint), you can point whisper-stream at it without using the local
backend. This keeps the model resident in memory between utterances and
removes the per-call startup cost of `whisper-cli`:

```bash
# Run whisper-server in another terminal:
whisper-server --model ~/.whisper-stream/models/ggml-base.en.bin \
  --host 127.0.0.1 --port 2022 \
  --inference-path /v1/audio/transcriptions --convert

# Then in whisper-stream:
whisper-stream --api-url http://127.0.0.1:2022/v1/audio/transcriptions
```

No API key is required when `--api-url` is set.

> **Security note:** `--api-url` directs requests to whatever URL you specify, so audio and any token you provide are sent there. Only point it at endpoints you trust, and avoid combining a real OpenAI API key with a third-party URL.

## Model selection (API backend)

- `gpt-4o-mini-transcribe` (default) — everyday transcription, fastest and cheapest
- `gpt-4o-transcribe` — highest quality
- `gpt-4o-transcribe-diarize` — needed for `--diarize` (multi-speaker)

For translation to English, use `--backend local --translate` (whisper.cpp does this natively).

API limits: 25 MB per file; formats `mp3`, `mp4`, `mpeg`, `mpga`, `m4a`, `wav`, `webm`, `flac`, `ogg`, `opus` (case-insensitive; enforced for the API backend only). See the [OpenAI Speech to Text API](https://platform.openai.com/docs/guides/speech-to-text) for details.

## Author

Yoichiro Hasebe [<yohasebe@gmail.com>]

## License

This software is distributed under the [MIT License](http://www.opensource.org/licenses/mit-license.php).
