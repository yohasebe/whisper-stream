# Whisper Stream Speech-to-Text Transcriber

![whisper-stream](https://github.com/yohasebe/whisper-stream/assets/18207/7b419ba0-a621-40ac-82c6-9c498e038e0d)

**whisper-stream**は**リアルタイム音声認識**のための1ファイル完結のbashスクリプトです。音声を録音し、発話間の無音を検出して、各発話を[OpenAIの音声認識API](https://platform.openai.com/docs/guides/speech-to-text)またはローカルの[whisper.cpp](https://github.com/ggml-org/whisper.cpp)バイナリで書き起こします。

このスクリプトは**パイプネイティブなCLIプリミティブ**として動作します。`--stdout`や`--jsonl`オプションを使うと書き起こし結果が副作用なしでstdoutに流れるため、`jq`、シェルループ、tmuxペイン、コマンドラインのAIコーディングエージェントなどと自由に合成できます。これらのオプションを付けない場合は、書き起こしがシステムクリップボードにコピーされ、任意でファイルとしても保存されます。

一回限りのディクテーションから、音声駆動型のシェルワークフローのための常時起動ローカル書き起こしまで、幅広い用途で使えます。

## 特徴

- **パイプネイティブ出力**: `--stdout`でプレーンテキスト、`--jsonl`で発話1件ごとに1つのJSONオブジェクト。どちらもシェルツールやAIエージェントとの合成に適した形
- **2つのバックエンド**: 品質と多言語対応のOpenAI音声認識API、または**無料・オフライン・プライベート**な常時起動ディクテーションのためのローカル`whisper.cpp`
- **複数の出力モード**: プレーンテキスト、JSON Lines、クリップボードコピー、ファイル保存 — ワークフローに合わせて選択
- **複数のAPIモデル**: `gpt-4o-transcribe`、`gpt-4o-mini-transcribe`(デフォルト)、`gpt-4o-transcribe-diarize`
- **話者ダイアライゼーション**と既知話者登録(APIバックエンドの`gpt-4o-transcribe-diarize`のみ)
- **リアルタイム/ファイルモード**で無音ベースの発話区切り

## インストール

### Homebrew(推奨)

以下のコマンドを実行:

```
> brew tap yohasebe/whisper-stream
> brew install whisper-stream
```

以上です。`whisper-stream`コマンドがターミナルで利用できるようになります。

### 手動インストール

依存: `curl`、`jq`、`sox`(Linuxでは加えて`xclip`)。`--backend local`を使う場合は`whisper-cpp`も — 下記[ローカルバックエンド](#ローカルバックエンドwhispercpp)参照。

```bash
brew install curl jq sox                    # macOS
sudo apt-get install curl jq sox xclip      # Debian/Ubuntu
```

その後、`whisper-stream`スクリプトをPATH上の任意の場所に配置し、実行権限を付与します:

```bash
install -m 755 whisper-stream /usr/local/bin/
```

## 使い方

以下のコマンドで起動できます:

```bash
> whisper-stream [options]
```

利用可能なオプション:

**録音オプション:**
- `-v, --volume <value>`: 最小ボリューム閾値。パーセント(`1%`)またはdBFS(`-30d`)で指定可能。デフォルト: `1%`(≈ -40 dBFS)
- `-s, --silence <value>`: 最小無音長(デフォルト: 1.5)
- `-o, --oneshot`: ワンショットモードを有効化
- `-d, --duration <value>`: 録音時間(秒)を指定(デフォルト: 0、連続録音)
- `-f, --file <value>`: 書き起こし対象の音声ファイルを指定

**バックエンドオプション:**
- `-b, --backend <value>`: 書き起こしバックエンドを指定。`api`(OpenAIまたは互換、デフォルト)または`local`(whisper.cpp、ローカル実行)。詳細は下記[ローカルバックエンド](#ローカルバックエンドwhispercpp)を参照。
- `--model-path <file>`: ローカルバックエンド用のggmlモデルファイルパス。未指定時は`$WHISPER_STREAM_MODEL`、それも未設定なら`~/.whisper-stream/models/ggml-base.en.bin`にフォールバック。
- `--api-url <url>`: APIエンドポイントを上書き。whisper.cppの`whisper-server`などOpenAI互換のセルフホストサーバを指す用途に便利。設定時はトークンは任意。
- `--vad`:(ローカルバックエンド限定)whisper.cppの組み込みVADを有効化し、各チャンク内の非発話区間をスキップ。文字起こし精度の向上と"Thank you for watching"のような幻覚の抑制に効きます。VADモデルが必要。
- `--vad-model-path <file>`: ggml形式のVADモデルパス。未指定時は`$WHISPER_STREAM_VAD_MODEL`、それも未設定なら`~/.whisper-stream/models/ggml-silero-v5.1.2.bin`。

**APIオプション(backend=api):**
- `-t, --token <value>`: APIトークンを指定(OpenAIエンドポイント使用時のみ必須)
- `-m, --model <value>`: モデルを指定。任意のモデル名はAPIにそのまま渡されます。未知のモデル名は警告のみ出るため、`gpt-4o-mini-transcribe-2025-12-15`のような日付付きスナップショットも指定可能です。既知の値: `gpt-4o-transcribe`、`gpt-4o-mini-transcribe`(デフォルト)、`gpt-4o-transcribe-diarize`。
- `-r, --prompt <value>`: プロンプトを指定(両バックエンドで有効)
- `-l, --language <value>`: 入力言語をISO-639-1形式で指定
- `-tr, --translate`: 書き起こしテキストを英語に翻訳(ローカルバックエンドのみ)

**出力オプション:**
- `-p, --path <value>`: 書き起こしファイルを作成する出力ディレクトリを指定
- `-p2, --pipe-to <cmd>`: 書き起こしテキストを指定コマンドにパイプ(例: `'wc -w'`)
- `-q, --quiet`: バナーと設定表示を抑制
- `--stdout`: 書き起こしをstdoutにのみ出力。バナー・クリップボード・ファイル出力・進捗表示を全て抑制します。シェルパイプライン向け。
- `--jsonl`: 発話ごとに1つのJSONオブジェクトを出力: `{version, ts, model, duration, text}`。`--stdout`を暗黙に含み、`--diarize`とは併用不可。リアルタイムモードでAPIバックエンドを使っている場合、行の順序は発話順と異なる場合があります — 厳密な順序が必要なら`ts`でソートするか`--oneshot`を使用してください。

**ダイアライゼーションオプション(`gpt-4o-transcribe-diarize`専用):**
- `--diarize`: 話者ダイアライゼーションを有効化
- `--register-speakers`: 既知話者を対話的に登録(ファイルモードのみ)
- `--list-speakers`: 保存された話者サンプルを一覧表示
- `--delete-speaker <name>`: 保存された話者サンプルを削除
- `--speaker-dir <path>`: 話者サンプルのカスタムディレクトリ(デフォルト: `~/.whisper-stream/speakers`)

**その他のオプション:**
- `-V, --version`: バージョン番号を表示
- `-h, --help`: ヘルプメッセージを表示

## 使用例

```bash
# デフォルト: 連続録音、クリップボードにコピー
whisper-stream

# 入力言語を指定(ISO-639-1)
whisper-stream -l ja

# 英語への翻訳(ローカルバックエンドが必要)
whisper-stream --backend local --translate

# ワンショット録音、厳しめの閾値、ディレクトリ保存
whisper-stream -v -35d -s 2 -o -p ~/Desktop

# 既存の音声ファイルを書き起こし
whisper-stream -f ~/Desktop/interview.mp3 -l en

# 会議録音の話者ダイアライゼーション
whisper-stream -f meeting.mp3 -m gpt-4o-transcribe-diarize --diarize

# パイプネイティブ: 書き起こしを任意のシェルツールに流す
whisper-stream --stdout | your-tool

# 構造化JSONL出力、発話ごとに1オブジェクト
whisper-stream --jsonl | jq -r .text
```

## ローカルバックエンド(whisper.cpp)

OpenAI APIに加えて、`whisper-stream`はローカルの[`whisper.cpp`](https://github.com/ggml-org/whisper.cpp)バイナリを駆動できます。これにより継続的なディクテーションが**無料・オフライン・プライベート**になります。APIコストを気にせず音声認識を常時起動したいとき、あるいはネットワーク隔離環境で作業するときに有用です。

### セットアップ

```bash
# whisper.cpp をインストール(`whisper-cli`バイナリを提供)
brew install whisper-cpp     # macOS
# またはソースからビルド: https://github.com/ggml-org/whisper.cpp

# ggmlモデルファイルをダウンロード
mkdir -p ~/.whisper-stream/models
curl -L -o ~/.whisper-stream/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

# オプション: --vad 用のVADモデル
curl -L -o ~/.whisper-stream/models/ggml-silero-v5.1.2.bin \
  https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin
```

他のサイズや言語対応モデルは[whisper.cppのモデル一覧](https://huggingface.co/ggerganov/whisper.cpp/tree/main)を参照してください。

### 使い方

```bash
# デフォルトのモデルパス(~/.whisper-stream/models/ggml-base.en.bin)を使用
whisper-stream --backend local

# 特定のモデルを指定
whisper-stream --backend local --model-path ~/models/your-model.bin

# 環境変数経由で指定
WHISPER_STREAM_MODEL=~/models/your-model.bin whisper-stream -b local

# パイプネイティブモードと組み合わせ
whisper-stream -b local --jsonl | jq -r '.text'
```

### 機能マトリクス(local vs API)

| 機能                              | `api` | `local` |
|-----------------------------------|:-----:|:-------:|
| 基本の書き起こし                  |   ✓   |    ✓    |
| `--language`、`--prompt`          |   ✓   |    ✓    |
| `--translate`(英語への翻訳)      |   –   |    ✓    |
| `--vad`(組み込みVAD)             |   –   |    ✓    |
| `--stdout`、`--jsonl`             |   ✓   |    ✓    |
| `--diarize` / 話者登録            |   ✓   |    –    |

### リアルタイムモードでの注意点

- 発話ごとのレイテンシはモデルサイズ次第です。Apple Siliconでは`ggml-tiny.en`で0.5秒程度、大きなモデルは比例して遅くなります。
- ローカルバックエンドは複数の`whisper-cli`プロセスによるGPU競合を避けるため、発話を逐次処理します。
- `whisper-cli`エラー時、その発話はスキップされ、stderrに警告が出ます。

### セルフホストwhisper.cppサーバー(`--api-url`)

whisper.cppの`whisper-server`(OpenAI互換のHTTPエンドポイントを公開)を実行している場合、ローカルバックエンドを使わずに`--api-url`でそこに向けることができます。モデルがメモリに常駐したままになり、`whisper-cli`の発話ごとの起動コストが消えます:

```bash
# 別のターミナルで whisper-server を起動:
whisper-server --model ~/.whisper-stream/models/ggml-base.en.bin \
  --host 127.0.0.1 --port 2022 \
  --inference-path /v1/audio/transcriptions --convert

# whisper-stream 側:
whisper-stream --api-url http://127.0.0.1:2022/v1/audio/transcriptions
```

`--api-url`設定時はAPIキー不要です。

> **セキュリティ注意:** `--api-url`は指定されたURLにリクエストを送信します。音声データと(指定されている場合は)トークンもそのURLに渡るため、信頼できるエンドポイントのみに使用してください。本物のOpenAIトークンを第三者のURLと組み合わせるのは避けてください。

## モデル選択(APIバックエンド)

- `gpt-4o-mini-transcribe`(デフォルト) — 汎用的な書き起こし。最速・最安
- `gpt-4o-transcribe` — 最高品質
- `gpt-4o-transcribe-diarize` — `--diarize`(複数話者)に必要

英語への翻訳には`--backend local --translate`を使ってください(whisper.cppがネイティブ対応)。

APIの制約: 1ファイル25MB、対応形式は`mp3`、`mp4`、`mpeg`、`mpga`、`m4a`、`wav`、`webm`。詳細は[OpenAI Speech to Text API](https://platform.openai.com/docs/guides/speech-to-text)を参照。

## 作者

Yoichiro Hasebe [<yohasebe@gmail.com>]

## ライセンス

このソフトウェアは[MITライセンス](http://www.opensource.org/licenses/mit-license.php)で配布されています。
