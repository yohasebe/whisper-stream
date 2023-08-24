# Whisper Voice-to-Text Stream Transcriber

![whisper-stream](https://github.com/yohasebe/whisper-stream/assets/18207/ea8e3eff-f4da-4749-bc5f-6d58ed119b13)

This project, "Whisper Voice-to-Text Stream Transcriber", is a bash script that utilizes the [OpenAI Whisper API](https://platform.openai.com/docs/guides/speech-to-text) to transcribe streaming voice input into text. It employs SoX for audio recording and includes a built-in feature that detects silence between spoken phrases.

The script is designed to convert voice audio into text each time the system identifies a specified duration of silence. This unique feature essentially enables the Whisper API to function as if it were capable of real-time voice-to-text conversion.

After transcription, the text is automatically copied to your system’s clipboard for immediate use. For future reference, it can also be saved in a specified directory as a text file.

## Installation

1. Download the `whisper-stream.sh` script to your local machine.

2. Make the script executable by running the following command:

```bash
chmod +x whisper-stream.sh
```

3. To make the script available universally, move it to `/usr/local/bin` directory:

```bash
sudo mv whisper-stream.sh /usr/local/bin
```

## Dependencies

This script requires the following dependencies:

- `curl`
- `jq`
- `sox`
- `xclip` or `pbcopy` or `clip.exe` depending on your OS

### Linux

On a Debian-based Linux distribution, you can install these dependencies with:

```bash
sudo apt-get install curl jq sox xclip
```

### macOS

On macOS, you can install these dependencies with Homebrew:

```bash
brew install curl jq sox
```

`pbcopy` is pre-installed on macOS.

### Windows

On Windows, you can install these dependencies with Chocolatey:

```bash
choco install curl jq sox
```

`clip.exe` is pre-installed on Windows.

## Usage

You can start the script with the following command:

```bash
./whisper-stream.sh [options]
```

The available options are:

- `-v, --volume <value>`: Set the minimum volume threshold (default: 1%)
- `-s, --silence <value>`: Set the minimum silence length (default: 1.5)
- `-o, --oneshot`: Enable one-shot mode
- `-d, --duration <value>`: Set the recording duration in seconds (default: 0, continuous)
- `-t, --token <value>`: Set the OpenAI API token
- `-p, --path <value>`: Set the output directory path
- `-r, --prompt <value>`: Set the prompt for the API call
- `-l, --language <value>`: Set the input language in ISO-639-1 format
- `-h, --help`: Display the help message

## Examples

Here are some usage examples with a brief comment on each of them:

`./whisper-stream.sh`

This will start the script with the default settings, recording audio continuously and transcribing it into text using the default volume threshold and silence length. If the OpenAI API token is not provided as an argument, the script will automatically use the value of the `OPENAI_API_KEY` environment variable if it is set.

`./whisper-stream.sh -l ja`

This will start the script with the input language specified as Japanese; see the [Wikipedia](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes) page for ISO-639-1 language codes.

`./whisper-stream.sh -v 2% -s 2 -o -d 60 -t your_openai_api_token -p /path/to/output/directory`

This example sets the minimum volume threshold to 2%, the minimum silence length to 2 seconds, enables one-shot mode, sets the recording duration to 60 seconds, specifies the OpenAI API token, and sets the output directory path to `/path/to/output/directory`. If the OpenAI API token is not provided as an argument, the script will automatically use the value of the `OPENAI_API_KEY` environment variable if it is set.
