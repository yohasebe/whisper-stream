# Whisper Voice-to-Text Stream Transcriber

This project is a bash script that uses the [OpenAI Whisper API](https://platform.openai.com/docs/guides/speech-to-text) to transcribe stream audio into text. It records audio using SoX, detects silence, and transcribes the audio into text. The transcribed text is automatically copied to the system clipboard for immediate use and also saved in a text file for record keeping.

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
- `-r, --prompt <value>`: Set the prompt for the API call (the prompt should match the audio language)
- `-l, --language <value>`: Set the input language in ISO-639-1 format
- `-h, --help`: Display the help message

## Examples

Here are some usage examples with a brief comment on each of them:

`> ./whisper-stream.sh`

This will start the script with the default settings, recording audio continuously and transcribing it into text using the default volume threshold and silence length. If the OpenAI API token is not provided as an argument, the script will automatically use the value of the `OPENAI_API_KEY` environment variable if it is set.

`> ./whisper-stream.sh -v 2% -s 2 -o -d 60 -t your_openai_api_token -p /path/to/output/directory`

This example sets the minimum volume threshold to 2%, the minimum silence length to 2 seconds, enables one-shot mode, sets the recording duration to 60 seconds, specifies the OpenAI API token, and sets the output directory path to `/path/to/output/directory`. If the OpenAI API token is not provided as an argument, the script will automatically use the value of the `OPENAI_API_KEY` environment variable if it is set.
