# SDI Coach

## Overview
sdi.coach is a CLI-based System Design Interview coach for macOS that provides AI-powered mock interviews
with real-time voice interaction and comprehensive feedback.

## Architecture
- **Frontend**: Swift CLI (macOS, AVAudioEngine for mic capture)
- **Backend**: Python (MLX-Whisper transcription, Qwen3-TTS, Strands Agents)
- **IPC**: Unix Domain Socket (JSON protocol)
- **Cloud**: Amazon Bedrock (Sonnet 4.5 for interviewer, Opus 4.6 for feedback)

## Project Structure
sdi.coach/
├── Package.swift                    # Swift package manifest
├── Package.resolved                 # Dependency lock file
├── CLAUDE.md                        # Project instructions
│
├── Sources/SDICoach/
│   ├── SDICoach.swift               # CLI entry point + Application class
│   │
│   ├── Command/
│   │   ├── Command.swift            # Command enum (start, pause, answer, end)
│   │   └── CommandParser.swift      # Input string → Command parsing
│   │
│   ├── Audio/
│   │   ├── MicrophoneCapture.swift  # AVAudioEngine mic input
│   │   ├── MicrophoneCaptureProtocol.swift  # Protocol for audio capture
│   │   ├── AudioTypes.swift         # AudioBuffer, AudioFrame types
│   │   └── SampleRateConverter.swift # 48kHz → 16kHz (vDSP)
│   │
│   ├── IPC/
│   │   ├── IPCClient.swift          # Unix socket client
│   │   └── IPCProtocol.swift        # Message types
│   │
│   ├── Services/
│   │   ├── InterviewService.swift   # Interview session management
│   │   ├── TTSEngine.swift          # TTS state management (backend-driven)
│   │   ├── TerminalRenderer.swift   # Display width, wrapping, status line
│   │   └── InputHandler.swift       # Raw mode terminal input handling
│   │
│   ├── Session/
│   │   ├── InterviewSession.swift   # Session state (question, timer, transcripts)
│   │   ├── SessionTimer.swift       # 30-minute countdown timer
│   │   ├── TranscriptManager.swift  # Transcript accumulation for feedback
│   │   └── TranscriptEntry.swift    # Single transcript entry data model
│   │
│   └── TUI/
│       ├── TUIEngine.swift          # Main UI engine
│       ├── HeaderView.swift         # Logo, version, timer display
│       ├── StatusBar.swift          # Interview status, mic status
│       ├── TranscriptView.swift     # Real-time transcript display
│       └── ApplicationMode.swift    # idle, interviewing, paused, feedback
│
├── backend/
│   ├── pyproject.toml               # Python dependencies
│   ├── init.py
│   ├── main.py                      # Backend entry point
│   │
│   ├── ipc/
│   │   ├── init.py
│   │   ├── server.py                # Asyncio Unix socket server
│   │   └── protocol.py              # Message protocol definitions
│   │
│   ├── transcription/
│   │   ├── init.py
│   │   ├── engine.py                # MLX-Whisper transcription
│   │   └── service.py               # Audio buffering + transcription
│   │
│   ├── tts/
│   │   ├── init.py
│   │   ├── engine.py                # Qwen3-TTS engine (MLX)
│   │   └── service.py               # TTS service with voice presets
│   │
│   └── agents/
│       ├── init.py
│       ├── interviewer.py           # Interviewer Agent (Sonnet 4.5)
│       ├── feedback.py              # Feedback Agent (Opus 4.6)
│       └── service.py               # Agent orchestration service
│
└── scripts/
    └── sdi-coach                    # Unified launcher script

## Implementation

### TUI Pattern: "Append to Scrollback + Redraw Prompt"
Uses native terminal scrollback for natural mouse scroll.

[Terminal Scrollback Buffer - mouse scrollable]
│
│  ╔═══════════════════════════════════════════════════════════════╗
│  ║  ▐▛███▜▌ sdi.coach - System Design Interview Coach            ║
│  ║   ▗▗ ▗▗  Question: Design a URL shortener service             ║
│  ║  ▐█████▌ Time Remaining: 24:35                                ║
│  ╚═══════════════════════════════════════════════════════════════╝
│
│  🤖 [10:30:15] Let's start with the requirements. What are the...
│  🎤 [10:30:25] I think we need to support around 100 million...
│  🤖 [10:30:45] Good. How would you estimate the storage needs?
│  🎤 [10:31:02] If each URL mapping is about 500 bytes...
│
├─────────────────────────────────────────────────────────────────
│  🎙️ Interviewing │ 🎤ON │ ⏱️ 24:35 │ /pause /end
│  ❯ _

### Core Workflow

┌─────────────────────────────────────────────────────────────────┐
│                    Interview Session Flow                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   User: /start "Design a URL shortener"                         │
│      │                                                           │
│      ▼                                                           │
│   InterviewSession created (30 min timer starts)                │
│      │                                                           │
│      ▼                                                           │
│   ┌──────────────────────────────────────────────┐              │
│   │  Interview Loop (until /end or 30 min)       │              │
│   │                                               │              │
│   │  1. Interviewer Agent generates question      │              │
│   │  2. TTS speaks question                       │              │
│   │  3. User speaks answer (mic capture)          │              │
│   │  4. STT transcribes answer                    │              │
│   │  5. Interviewer Agent processes + follow-up   │              │
│   │     (3-5 follow-up questions per topic)       │              │
│   │  6. Loop back to step 2                       │              │
│   └──────────────────────────────────────────────┘              │
│      │                                                           │
│      ▼ (/end or timeout)                                        │
│   Feedback Agent analyzes all transcripts                       │
│      │                                                           │
│      ▼                                                           │
│   Markdown report saved (strengths, weaknesses, suggestions)    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

## Key Components

### Swift CLI Components

| Component | File | Description |
|-----------|------|-------------|
| **Entry Point** | `SDICoach.swift` | ArgumentParser command, Application class |
| **InterviewService** | `Services/InterviewService.swift` | Interview session lifecycle via IPC |
| **TTSEngine** | `Services/TTSEngine.swift` | TTS state management (backend-driven) |
| **TerminalRenderer** | `Services/TerminalRenderer.swift` | Display width, wrapping, status line |
| **InputHandler** | `Services/InputHandler.swift` | Raw mode terminal input handling |
| **Command** | `Command.swift` | start, pause, end commands |
| **CommandParser** | `CommandParser.swift` | String → Command parsing |
| **IPCClient** | `IPCClient.swift` | Unix socket client for Python backend |
| **InterviewSession** | `Session/InterviewSession.swift` | Session state management |
| **SessionTimer** | `Session/SessionTimer.swift` | 30-minute countdown with callbacks |
| **TranscriptManager** | `Session/TranscriptManager.swift` | Accumulates transcripts for feedback |
| **MicrophoneCapture** | `Audio/MicrophoneCapture.swift` | AVAudioEngine microphone input |
| **SampleRateConverter** | `Audio/SampleRateConverter.swift` | 48kHz → 16kHz conversion (vDSP) |

### Python Backend Components

| Component | File | Description |
|-----------|------|-------------|
| **IPC Server** | `ipc/server.py` | Asyncio Unix socket server |
| **Protocol** | `ipc/protocol.py` | Message protocol definitions |
| **TranscriptionEngine** | `transcription/engine.py` | MLX-Whisper transcription |
| **TranscriptionService** | `transcription/service.py` | Audio buffering + transcription |
| **TTSEngine** | `tts/engine.py` | Qwen3-TTS (mlx-community) |
| **TTSService** | `tts/service.py` | TTS service with voice presets |
| **InterviewerAgent** | `agents/interviewer.py` | Strands Agent with Bedrock Sonnet 4.5 |
| **FeedbackAgent** | `agents/feedback.py` | Strands Agent with Bedrock Opus 4.6 |
| **AgentService** | `agents/service.py` | Agent orchestration layer |

## Type Definitions

### Commands (Swift)
```swift
enum Command {
    case start(question: String?)    // Start interview with question
    case pause                       // Pause interview
    case end                         // End interview
    case quit                        // Exit application
    case unknown(input: String)
}

Application Modes (Swift)

enum ApplicationMode {
    case idle           // Waiting for /start
    case interviewing   // Active interview session
    case paused         // Interview paused
    case feedback       // Generating feedback report
}

Interview Session State (Swift)

struct InterviewSession {
    let question: String
    let startTime: Date
    var transcripts: [TranscriptEntry]
    var followUpCount: Int           // Track follow-ups per topic
    var isPaused: Bool
    var remainingSeconds: Int        // 30 * 60 = 1800
}

Transcript Entry (Swift)

struct TranscriptEntry {
    let timestamp: Date
    let source: TranscriptSource     // .interviewer or .user
    let content: String
}

enum TranscriptSource {
    case interviewer   // 🤖
    case user          // 🎤
}

IPC Protocol

Message Types
┌────────────────────┬───────────────┬───────────────────────────────┐
│    Message Type    │   Direction   │          Description          │
├────────────────────┼───────────────┼───────────────────────────────┤
│ audio_data         │ CLI → Backend │ Mic audio samples (Base64)    │
├────────────────────┼───────────────┼───────────────────────────────┤
│ transcription      │ Backend → CLI │ Transcribed text              │
├────────────────────┼───────────────┼───────────────────────────────┤
│ interview_start    │ CLI → Backend │ Start interview with question │
├────────────────────┼───────────────┼───────────────────────────────┤
│ interview_question │ Backend → CLI │ AI-generated question         │
├────────────────────┼───────────────┼───────────────────────────────┤
│ interview_response │ CLI → Backend │ User's transcribed response   │
├────────────────────┼───────────────┼───────────────────────────────┤
│ interview_followup │ Backend → CLI │ Follow-up question from AI    │
├────────────────────┼───────────────┼───────────────────────────────┤
│ interview_end      │ CLI → Backend │ End interview session         │
├────────────────────┼───────────────┼───────────────────────────────┤
│ feedback_request   │ CLI → Backend │ Request feedback generation   │
├────────────────────┼───────────────┼───────────────────────────────┤
│ feedback_response  │ Backend → CLI │ Feedback markdown content     │
├────────────────────┼───────────────┼───────────────────────────────┤
│ tts_speak          │ CLI → Backend │ Request TTS playback          │
├────────────────────┼───────────────┼───────────────────────────────┤
│ tts_status         │ Backend → CLI │ TTS state update              │
├────────────────────┼───────────────┼───────────────────────────────┤
│ tts_stop           │ CLI → Backend │ Stop TTS playback             │
└────────────────────┴───────────────┴───────────────────────────────┘
AI Agent Design

Interviewer Agent (Sonnet 4.5 - Fast, Conversational)

SYSTEM_PROMPT = """
You are an experienced System Design interviewer. Your role is to:
1. Guide the candidate through a system design problem
2. Ask clarifying questions about requirements
3. Probe deeper into technical decisions
4. Challenge assumptions constructively
5. Generate 3-5 follow-up questions per topic

Keep responses concise (2-3 sentences) for natural conversation.
Speak in a professional but encouraging tone.
"""

Feedback Agent (Opus 4.6 - Deep Analysis)

SYSTEM_PROMPT = """
You are a senior engineering manager providing interview feedback.
Analyze the candidate's system design interview transcript and provide:

## Strengths
- What the candidate did well
- Strong technical decisions

## Areas for Improvement
- Gaps in the design
- Missed considerations
- Communication issues

## Detailed Feedback
- Requirements gathering
- High-level design
- Deep dive quality
- Trade-off analysis
- Scalability considerations

## Score (1-10)
- Overall performance rating with justification

## Recommendations
- Specific study areas for improvement
"""

Build Commands

# Unified launcher (recommended)
./scripts/sdi-coach              # Start both backend and CLI
./scripts/sdi-coach --debug      # With debug logging

# Manual execution
swift build                      # Build Swift CLI
swift run sdi.coach              # Run CLI directly

# Python backend
cd backend
source .venv/bin/activate
python main.py                   # Run backend server

# Tests
cd backend && pytest             # Python tests
swift test                       # Swift tests

Configuration

Environment Variables

# Required
AWS_REGION=us-west-2
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...

# Optional
SDICOACH_INTERVIEWER_MODEL=us.anthropic.claude-sonnet-4-5-20250929-v1:0
SDICOACH_FEEDBACK_MODEL=us.anthropic.claude-opus-4-6-v1
SDICOACH_TTS_MODEL=mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit
SDICOACH_LOG_LEVEL=INFO

IPC Configuration

- Socket path: /tmp/sdicoach.sock
- Protocol: JSON over Unix Domain Socket (newline-delimited)

Requirements

- macOS 13.0+ (AVAudioEngine)
- Swift 5.9+
- Python 3.10+
- Apple Silicon (M1/M2/M3) - required for MLX
- AWS credentials with Bedrock access

ML Models (User-Prompted Download)

On first run, user is prompted to confirm model download:

```
=====================================
sdi.coach requires ML models:

  • MLX-Whisper (large-v3-mlx)    ~3GB
  • Qwen3-TTS (0.5B-4bit)         ~500MB

  Total: ~2GB

Download now? [Y/n]:
=====================================
```

| Model | Size | Cache Location |
|-------|------|----------------|
| MLX-Whisper (large-v3-mlx) | ~3GB | `~/.cache/sdi-coach/whisper/` |
| Qwen3-TTS (0.5B-4bit) | ~500MB | `~/.cache/sdi-coach/tts/` |

Model Management:
- First run: Prompt user before download
- Manual download: `sdi-coach --download-models`
- Skip prompt: `sdi-coach --download-models --yes`
- Custom path: `SDICOACH_MODEL_PATH=~/models`
- Offline mode: Models must be pre-downloaded

---
Implementation Phases

Phase 1: Core Infrastructure

- Swift CLI skeleton with ArgumentParser
- IPC client/server (Unix Domain Socket)
- Basic TUI with status bar
- Command parsing (start, pause, end)

Phase 2: Audio Pipeline

- Microphone capture (AVAudioEngine)
- Sample rate conversion (48kHz → 16kHz)
- MLX-Whisper transcription
- Real-time transcript display

Phase 3: TTS Integration

- Qwen3-TTS engine (MLX)
- Voice presets (English)
- TTS state management (Swift)
- Audio playback coordination

Phase 4: AI Agents

- Interviewer Agent (Sonnet 4.5)
- Interview conversation flow
- Follow-up question generation
- Feedback Agent (Opus 4.6)
- Markdown report generation

Phase 5: Session Management

- 30-minute timer with callbacks
- Pause/resume functionality
- Transcript accumulation
- Session state persistence

Phase 6: Polish & Distribution

- Installation script
- Documentation
- Error handling improvements

---
Custom Subagents (TDD Multi-Agent System)

This project uses a 4-agent TDD feedback loop. See CLAUDE.md for details.
┌───────────────────┬──────────────┬────────────────────────────────────────┐
│       Agent       │  TDD Phase   │                Purpose                 │
├───────────────────┼──────────────┼────────────────────────────────────────┤
│ 🧪 test-architect │ RED          │ Design & write failing tests           │
├───────────────────┼──────────────┼────────────────────────────────────────┤
│ ⚙️ implementer    │ GREEN        │ Write minimal code to pass tests       │
├───────────────────┼──────────────┼────────────────────────────────────────┤
│ 🔍 code-reviewer  │ Quality Gate │ Review code, approve/reject            │
├───────────────────┼──────────────┼────────────────────────────────────────┤
│ ✨ refactorer     │ REFACTOR     │ Improve code without changing behavior │
└───────────────────┴──────────────┴────────────────────────────────────────┘
---