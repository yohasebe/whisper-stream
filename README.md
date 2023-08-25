# Whisper Voice-to-Text Stream Transcriber

![whisper-stream](https://github.com/yohasebe/whisper-stream/assets/18207/7b419ba0-a621-40ac-82c6-9c498e038e0d)

This is a **bash script** that utilizes the [OpenAI Whisper API](https://platform.openai.com/docs/guides/speech-to-text) to **transcribe continuous voice input into text**. It uses SoX for audio recording and includes a built-in feature that detects silence between speech segments.

The script is designed to convert voice audio into text each time the system identifies a **specified duration of silence**. This enables the Whisper API to function as if it were capable of real-time voice-to-text conversion.

After transcription, the text is automatically copied to your system's **clipboard** for immediate use. It can also be saved in a specified directory as a **text file**.

## Installation

### MacOS

1. Install [Homebrew](https://brew.sh/)

2. Run the following commands:

```
brew tap yohasebe/whisper-stream
brew install whisper-stream
```

### Linux and Windows

1. Install the following dependencies:

- `curl`
- `jq`
- `sox`
- `xclip` (for Linux)

On a Debian-based Linux distribution, you can install these dependencies with:

```bash
sudo apt-get install curl jq sox xclip
```

2. Identify a directory in your system's PATH variable where you want to place the script. You can check the directories in your PATH variable by running the following command:

```bash
echo $PATH
```

3. Move the `whisper-stream` script to the chosen directory. For example, if you want to move it to `/usr/local/bin`, run the following command:

```bash
mv whisper-stream /usr/local/bin
```

4. Make sure the script is executable by running the following command:

```bash
chmod +x /usr/local/bin/whisper-stream
```

## Usage

You can start the script with the following command:

```bash
whisper-stream [options]
```

The available options are:

- `-v, --volume <value>`: Set the minimum volume threshold (default: 1%)
- `-s, --silence <value>`: Set the minimum silence length (default: 1.5)
- `-o, --oneshot`: Enable one-shot mode
- `-d, --duration <value>`: Set the recording duration in seconds (default: 0, continuous)
- `-t, --token <value>`: Set the OpenAI API token
- `-p, --path <value>`: Set the output directory path to create the transcription file
- `-r, --prompt <value>`: Set the prompt for the API call
- `-l, --language <value>`: Set the input language in ISO-639-1 format
- `-h, --help`: Display the help message

## Examples

Here are some usage examples with a brief comment on each of them:

`whisper-stream`

This will start the script with the default settings, recording audio continuously and transcribing it into text using the default volume threshold and silence length. If the OpenAI API token is not provided as an argument, the script will automatically use the value of the `OPENAI_API_KEY` environment variable if it is set.

`whisper-stream -l ja`

This will start the script with the input language specified as Japanese; see the [Wikipedia](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes) page for ISO-639-1 language codes.

`whisper-stream -v 2% -s 2 -o -d 60 -t your_openai_api_token -p /path/to/output/directory`

This example sets the minimum volume threshold to 2%, the minimum silence length to 2 seconds, enables one-shot mode, sets the recording duration to 60 seconds, specifies the OpenAI API token, and sets the output directory path `/path/to/output/directory` to create a transcription text file.

## Author

Yoichiro Hasebe <yohasebe@gmail.com>

## License

This software is distributed under the [MIT License](http://www.opensource.org/licenses/mit-license.php).
