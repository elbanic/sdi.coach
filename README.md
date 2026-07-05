# sdi.coach

AI-powered System Design Interview coach with real-time voice interaction.

![Demo](resources/sdi-coach-demo.gif)

## Features

- Real-time voice conversation with AI interviewer
- Speech-to-text transcription (MLX-Whisper)
- Text-to-speech responses (Qwen3-TTS)
- AI-powered feedback generation (Claude on Bedrock)
- 30-minute timed interview sessions

## Requirements

### Hardware
- Apple Silicon Mac (M1/M2/M3/M4) - required for MLX
- Microphone - for voice input
- Speaker/Headphones - for TTS output

### Software
- macOS 13.0+
- Xcode 15+ (for Swift CLI build)
- Python 3.10+

### Cloud
- AWS credentials with Bedrock access (Claude model)

### ML Models (~5GB, downloaded on first run)
- MLX-Whisper (large-v3-mlx) - speech recognition
- Qwen3-TTS (1.7B-Base-8bit) - text-to-speech via mlx-audio

## Installation

```bash
git clone https://github.com/elbanic/sdi.coach.git
cd sdi.coach
./scripts/sdi-coach --build
```

## Usage

### First Run - Download Models

```bash
sdi-coach init
```

This downloads required ML models (~5GB):
- MLX-Whisper (large-v3-mlx)
- Qwen3-TTS (1.7B)

### Start Interview

```bash
sdi-coach
```

### Commands

| Command | Description |
|---------|-------------|
| `/start "question"` | Start interview with a topic |
| `/start` | Start with default topic |
| `/pause` | Pause interview |
| `/end` | End interview and get feedback |
| `/quit` | Exit application |

### Example Session

```bash
$ sdi-coach
> /start "Design a URL shortener service"

# AI interviewer asks questions via voice
# Speak your answers into the microphone
# After 30 minutes (or /end), receive feedback report
```

## Environment Variables

```bash
# Required for AI features
export AWS_REGION=us-west-2
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret

# Optional
export SDICOACH_MODEL_PATH=~/.cache/sdi-coach
export SDICOACH_LOG_LEVEL=INFO
```

## Development

```bash
# Build
./scripts/sdi-coach --build

# Run tests
swift test
cd backend && pytest

# Debug mode
./scripts/sdi-coach --debug
```

## Third-Party Licenses

This project uses the following ML models:

- **MLX-Whisper** (large-v3-mlx) - MIT License
  - https://huggingface.co/mlx-community/whisper-large-v3-mlx
- **Qwen3-TTS** - Apache-2.0 License
  - https://github.com/QwenLM/Qwen3-TTS

## License

MIT License - see [LICENSE](LICENSE) file.
