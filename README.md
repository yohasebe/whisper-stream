# Whisper Stream Speech-to-Text Transcriber

![whisper-stream](https://github.com/yohasebe/whisper-stream/assets/18207/7b419ba0-a621-40ac-82c6-9c498e038e0d)

**whisper-stream** is a single bash script for **real-time speech-to-text**. It records audio, detects silence between speech segments, and transcribes each segment using either the [OpenAI speech-to-text API](https://platform.openai.com/docs/guides/speech-to-text) or a local [whisper.cpp](https://github.com/ggml-org/whisper.cpp) binary.

The script works as a **pipe-native CLI primitive**: with `--stdout` or `--jsonl`, transcriptions flow to stdout with no side effects, so you can compose them with `jq`, shell loops, tmux panes, or any command-line AI coding agent. Without those flags, transcriptions are copied to the system clipboard and optionally saved as files.

Use cases range from one-off dictation to always-on local transcription for voice-driven shell workflows.

## Features

- **Pipe-native output**: `--stdout` for plain text and `--jsonl` for one JSON object per utterance, both suitable for composition with shell tools and AI agents
- **Two backends**: OpenAI's speech-to-text API for quality and language coverage, or local `whisper.cpp` for free, offline, private continuous dictation
- **Multiple output modes**: plain text, JSON Lines, clipboard copy, or saved files — pick the right one for your workflow
- **Context hints for accuracy**: keywords (`--keyword`), several expected languages (`-l en,ja`), and a free-form prompt, with OpenAI's `gpt-transcribe` (default)
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

Dependencies: `jq`; `curl` for the API backend; `sox` for recording from the microphone (not needed with `-f`). On Linux, `xclip` copies results to the clipboard; without it they are saved to a file. Optional: `whisper-cpp` for `--backend local` — see [Local backend](#local-backend-whispercpp).

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
- `-t, --token <value>`: Set the API token (only required for the OpenAI endpoint). Accepts a reference; see [API key](#api-key).
- `-m, --model <value>`: Set the model. Unknown names are passed through with a warning. See [Model selection](#model-selection-api-backend).
- `-r, --prompt <value>`: Set the prompt (works on both backends; not sent with `gpt-4o-transcribe-diarize`)
- `-l, --language <value>`: Set the input language as an ISO 639-1 code such as `en`. With `gpt-transcribe`, give several for mixed-language speech: `-l en,ja`.
- `--keyword <term>`: A term you expect to hear (product name, acronym, person's name). Repeat for more terms. `gpt-transcribe` only. Keywords are hints: they help the model spell a term correctly when it is spoken, and should not make it appear when it is not.
- `--keywords-file <file>`: Read keywords from a file, one term per line (blank lines ignored). Terms may contain commas but not `<`, `>`.
- `-tr, --translate`: Translate the transcribed text to English (local backend only)
- `--api-timeout <sec>`: Time limit for one API request (default: 120, or 600 with `-f`). See [Failed requests](#failed-requests).
- `--max-jobs <n>`: Maximum concurrent API requests in real-time mode (default: 4). See [Real-time queue](#real-time-queue).

**Output Options:**
- `-p, --path <value>`: Set the output directory path to create the transcription file
- `-p2, --pipe-to <cmd>`: Pipe the transcribed text to the specified command (e.g., 'wc -w')
- `-q, --quiet`: Suppress the banner and settings
- `--stdout`: Print transcriptions to stdout only. Suppresses banner, clipboard, file output, and progress indicators. Intended for shell pipelines.
- `--jsonl`: Emit one JSON object per utterance: `{version, seq, ts, model, duration, languages, text}`. Implies `--stdout`. Not compatible with `--diarize`.
  - `seq`: capture order of the utterance (1, 2, 3, …). In real-time mode with the API backend, lines may arrive out of speaking order because requests run concurrently — sort by `seq` if strict order matters. (`ts` is when the transcription finished, so it does not give speaking order.)
  - `duration`: length of the audio in seconds as measured by `soxi`, or `null` when it cannot be measured.
  - `languages`: languages the model detected, e.g. `[{"code":"en"}]`; `[]` when it could not tell; `null` when the model does not report them (everything except `gpt-transcribe`). This is never a copy of `-l`.
  - Consumers should ignore fields they do not know: new fields may be added without changing `version`.

**Diarization Options (gpt-4o-transcribe-diarize only):**

> OpenAI removes `gpt-4o-transcribe-diarize` from its API on 2027-02-26 and has not announced a replacement that keeps speaker labels. These options will stop working with the OpenAI endpoint then.

- `--diarize`: Enable speaker diarization
- `--register-speakers`: Interactively register known speakers (file mode only)
- `--list-speakers`: List saved speaker samples
- `--delete-speaker <name>`: Delete a saved speaker sample
- `--speaker-dir <path>`: Custom directory for speaker samples (default: ~/.whisper-stream/speakers)

**Other Options:**
- `-V, --version`: Show the version number
- `-h, --help`: Display the help message

## API key

The API backend uses the key given with `-t`, or else `OPENAI_API_KEY`. Either can hold the key itself or a reference to where it is stored. A reference is read once when whisper-stream starts, and the key is kept only in memory:

- `op://Vault/Item/field`: read with the [1Password CLI](https://developer.1password.com/docs/cli/) (`op read`). Install it with `brew install --cask 1password-cli`, and in the 1Password app turn on Settings › Developer › Integrate with 1Password CLI. 1Password may ask you to approve with Touch ID.
- `keychain:<service>`: read from the macOS keychain, from a generic password whose service is `<service>`. Add it with `security add-generic-password -s <service> -a openai -w` (you are prompted for the key).

```bash
export OPENAI_API_KEY="op://Private/OpenAI/credential"
whisper-stream
```

If the key cannot be read (the CLI is missing or not signed in, the approval prompt is dismissed, the item does not exist, or there is no answer within 60 seconds), whisper-stream stops with an explanation. Over SSH, an approval prompt on that Mac cannot be answered; if your setup needs one, set the key itself for that session.

A key given with `-t` is visible to other users of the machine in the process list; prefer `OPENAI_API_KEY` or a reference.

## Examples

```bash
# Default: continuous recording, copy to clipboard
whisper-stream

# Specify input language (ISO 639-1)
whisper-stream -l ja

# Mixed Japanese/English speech with domain terms
whisper-stream -l ja,en --keyword "Kubernetes" --keyword "whisper.cpp"

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
| Several languages (`-l en,ja`)     |   ✓   |    –    |
| `--keyword`, `--keywords-file`     |   ✓   |    –    |
| `--translate` (to English)         |   –   |    ✓    |
| `--vad` (built-in VAD)             |   –   |    ✓    |
| `--stdout`, `--jsonl`              |   ✓   |    ✓    |
| `--diarize` / speaker registration |   ✓   |    –    |

### Real-time mode notes

- Per-utterance latency depends on the model size. `ggml-tiny.en` is roughly half a second on Apple Silicon; larger models scale up.
- The local backend transcribes one utterance at a time to avoid GPU contention between concurrent `whisper-cli` processes. Recording continues meanwhile; see [Real-time queue](#real-time-queue).
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

- `gpt-transcribe` (default) — OpenAI's recommended transcription model. Supports `--keyword`, several `-l` languages, and reports detected languages in `--jsonl`.
- `gpt-4o-transcribe-diarize` — needed for `--diarize` (multi-speaker). Removed by OpenAI on 2027-02-26.
- `gpt-4o-transcribe`, `gpt-4o-mini-transcribe` — still accepted (with a warning) until OpenAI removes them on 2027-02-26. They take a single `-l` language and no keywords.

Dated snapshot names are sent as-is; the API decides whether they exist. `whisper-1` is rejected, and so is `gpt-live-transcribe`: it works only in OpenAI's Realtime sessions, not with the file transcription endpoint this tool uses. These checks apply to the OpenAI endpoint; with `--api-url` pointing at another server, model names are passed through unchecked.

For translation to English, use `--backend local --translate` (whisper.cpp does this natively).

API limits: 25 MB per file. With the API backend, `-f` accepts the extensions `mp3`, `mp4`, `mpeg`, `mpga`, `m4a`, `wav`, `webm`, `flac`, `ogg`, `opus` (case-insensitive); the [OpenAI Speech to Text guide](https://developers.openai.com/api/docs/guides/speech-to-text) lists the formats the API itself supports.

## Failed requests

Network errors, timeouts, and HTTP 408, 429 (rate limits), 500, 502, 503, and 504 are retried up to twice, waiting at least as long as the server's `Retry-After` asks. If the server asks for more than 60 seconds, the utterance fails instead. Other errors, including billing, spend, and quota errors, are not retried. A response that is not a transcript (for example, an HTML page from a proxy) counts as a failure. A failed utterance is skipped with a warning on stderr; in `-f` mode the exit status is non-zero.

## Real-time queue

Recording continues while earlier utterances are transcribed. Up to `--max-jobs` API requests run at once (one `whisper-cli` at a time with the local backend), and the other utterances wait in capture order. If 100 utterances are waiting, recording pauses until the queue shrinks, with a notice on stderr.

On Ctrl-C, whisper-stream finishes the utterances it has recorded, including the one in progress, before exiting. Press Ctrl-C again to discard them and exit at once.

## Author

Yoichiro Hasebe [<yohasebe@gmail.com>]

## License

This software is distributed under the [MIT License](http://www.opensource.org/licenses/mit-license.php).
