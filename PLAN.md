# sdi.coach Implementation Plan

## Context

sdi.coach is a CLI-based System Design Interview coach for macOS. The project is **fully implemented** with all Phases (0-7) completed and tested. This document describes the phased approach used to build the Swift CLI frontend and Python backend that communicate via Unix Domain Socket, providing AI-powered voice interaction for mock interviews.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         sdi.coach Architecture                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────┐     Unix Socket      ┌──────────────────────┐ │
│  │   Swift CLI      │◄──────────────────►│   Python Backend     │ │
│  │   (Frontend)     │   /tmp/sdicoach.sock │   (AI Services)      │ │
│  ├──────────────────┤                      ├──────────────────────┤ │
│  │ • TUI Engine     │                      │ • IPC Server         │ │
│  │ • Audio Capture  │                      │ • MLX-Whisper (STT)  │ │
│  │ • IPC Client     │                      │ • Qwen3-TTS          │ │
│  │ • Session Mgmt   │                      │ • Strands Agents     │ │
│  └──────────────────┘                      └──────────────────────┘ │
│                                                      │              │
│                                                      ▼              │
│                                            ┌──────────────────────┐ │
│                                            │   Amazon Bedrock     │ │
│                                            │ • Haiku (Interviewer)│ │
│                                            │ • Opus (Feedback)    │ │
│                                            └──────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Phase 0: Project Foundation

**Goal**: Set up project structure and dependencies

### Tasks
| ID | Task | Description |
|----|------|-------------|
| 0.1 | Create Package.swift | Swift package with ArgumentParser, swift-testing |
| 0.2 | Create pyproject.toml | Python deps: mlx-whisper, strands-agents, pytest |
| 0.3 | Create directory structure | As defined in PRD.md |
| 0.4 | Create .gitignore, .env.example | Environment configuration |

### Files to Create
- `Package.swift`
- `backend/pyproject.toml`
- `backend/__init__.py`
- `.gitignore`
- `.env.example`

---

## Phase 1: IPC Protocol Layer (Critical Path)

**Goal**: Establish communication protocol between Swift and Python

> **Why Critical**: Both frontend and backend depend on this. Must complete before parallel development.

### 1.1 Protocol Definition
| ID | Task | Files |
|----|------|-------|
| 1.1.1 | Define message types | `IPCProtocol.swift`, `protocol.py` |
| 1.1.2 | JSON serialization | Both files |
| 1.1.3 | Version handshake | Both files |

**Message Types** (from PRD.md):
- `audio_data`, `transcription`, `interview_start`, `interview_question`
- `interview_response`, `interview_followup`, `interview_end`
- `feedback_request`, `feedback_response`, `tts_speak`, `tts_status`, `tts_stop`

### 1.2 IPC Server (Python)
| ID | Task | File |
|----|------|------|
| 1.2.1 | Asyncio Unix socket server | `backend/ipc/server.py` |
| 1.2.2 | Client connection management | `backend/ipc/server.py` |
| 1.2.3 | Message dispatcher | `backend/ipc/server.py` |
| 1.2.4 | Graceful shutdown | `backend/ipc/server.py` |

### 1.3 IPC Client (Swift)
| ID | Task | File |
|----|------|------|
| 1.3.1 | Unix socket client | `Sources/SDICoach/IPC/IPCClient.swift` |
| 1.3.2 | Async message handling | `Sources/SDICoach/IPC/IPCClient.swift` |
| 1.3.3 | Reconnection logic | `Sources/SDICoach/IPC/IPCClient.swift` |
| 1.3.4 | Timeout handling | `Sources/SDICoach/IPC/IPCClient.swift` |

---

## Phase 2: Audio Pipeline

**Goal**: Capture microphone input and transcribe to text

### 2.1 Microphone Capture (Swift)
| ID | Task | File |
|----|------|------|
| 2.1.1 | AVAudioEngine setup | `MicrophoneCapture.swift` |
| 2.1.2 | PCM buffer capture | `MicrophoneCapture.swift` |
| 2.1.3 | Audio session management | `MicrophoneCapture.swift` |
| 2.1.4 | Error handling | `MicrophoneCapture.swift` |

### 2.2 Sample Rate Converter (Swift)
| ID | Task | File |
|----|------|------|
| 2.2.1 | vDSP resampling (48kHz → 16kHz) | `SampleRateConverter.swift` |
| 2.2.2 | Buffer management | `SampleRateConverter.swift` |

### 2.3 Transcription Engine (Python)
| ID | Task | File |
|----|------|------|
| 2.3.1 | MLX-Whisper initialization | `transcription/engine.py` |
| 2.3.2 | Audio buffering/chunking | `transcription/service.py` |
| 2.3.3 | Streaming transcription | `transcription/service.py` |
| 2.3.4 | VAD (Voice Activity Detection) | `transcription/service.py` |

---

## Phase 3: TTS Integration

**Goal**: Convert AI responses to speech

> **Model Download**: TTS engine checks for model presence on init. If not found, raises error (model download is handled by launcher with user confirmation). See PRD.md "ML Models" section.

### 3.1 TTS Engine (Python)
| ID | Task | File |
|----|------|------|
| 3.1.1 | Qwen3-TTS initialization + auto-download | `tts/engine.py` |
| 3.1.2 | Text-to-audio conversion | `tts/engine.py` |
| 3.1.3 | Voice preset management | `tts/service.py` |
| 3.1.4 | Audio streaming | `tts/service.py` |

### 3.2 TTS Client (Swift)
| ID | Task | File |
|----|------|------|
| 3.2.1 | TTS state management | `TTSEngine.swift` |
| 3.2.2 | Audio playback | `TTSEngine.swift` |
| 3.2.3 | Interruption handling | `TTSEngine.swift` |

---

## Phase 4: AI Agents

**Goal**: Implement interview and feedback AI agents

### 4.1 Interviewer Agent (Python)
| ID | Task | File |
|----|------|------|
| 4.1.1 | Strands Agent + Bedrock Haiku | `agents/interviewer.py` |
| 4.1.2 | System prompt design | `agents/interviewer.py` |
| 4.1.3 | Conversation context | `agents/interviewer.py` |
| 4.1.4 | Follow-up generation | `agents/interviewer.py` |

### 4.2 Feedback Agent (Python)
| ID | Task | File |
|----|------|------|
| 4.2.1 | Strands Agent + Bedrock Opus | `agents/feedback.py` |
| 4.2.2 | Feedback template | `agents/feedback.py` |
| 4.2.3 | Scoring logic | `agents/feedback.py` |
| 4.2.4 | Recommendation generation | `agents/feedback.py` |

### 4.3 Agent Service (Python)
| ID | Task | File |
|----|------|------|
| 4.3.1 | Agent orchestration | `agents/service.py` |
| 4.3.2 | Session state management | `agents/service.py` |
| 4.3.3 | Error recovery | `agents/service.py` |

### 4.4 E2E Integration Test (Python)
| ID | Task | File |
|----|------|------|
| 4.4.1 | E2E interview flow test | `tests/test_e2e_interview.py` |

> **Test Scope**: Automated interview flow test at IPC level. Validates 3-round Q&A ping-pong + feedback generation using Python backend only (no Swift CLI required). See `E2E_SCENARIO.md`.

---

## Phase 5: CLI & TUI

**Goal**: Build user interface components

### 5.1 Command System (Swift)
| ID | Task | File |
|----|------|------|
| 5.1.1 | Command enum | `Command/Command.swift` |
| 5.1.2 | CommandParser | `Command/CommandParser.swift` |
| 5.1.3 | ArgumentParser setup | `main.swift` |

### 5.2 Terminal Rendering (Swift)
| ID | Task | File |
|----|------|------|
| 5.2.1 | Terminal width detection | `TerminalRenderer.swift` |
| 5.2.2 | Text wrapping | `TerminalRenderer.swift` |
| 5.2.3 | Raw mode input | `InputHandler.swift` |
| 5.2.4 | Status bar rendering | `TerminalRenderer.swift` |

### 5.3 TUI Components (Swift)
| ID | Task | File |
|----|------|------|
| 5.3.1 | TUIEngine main loop | `TUI/TUIEngine.swift` |
| 5.3.2 | HeaderView | `TUI/HeaderView.swift` |
| 5.3.3 | StatusBar | `TUI/StatusBar.swift` |
| 5.3.4 | TranscriptView | `TUI/TranscriptView.swift` |
| 5.3.5 | ApplicationMode | `TUI/ApplicationMode.swift` |

---

## Phase 6: Session Management

**Goal**: Manage interview session lifecycle

### 6.1 Session Components (Swift)
| ID | Task | File |
|----|------|------|
| 6.1.1 | InterviewSession state | `Session/InterviewSession.swift` |
| 6.1.2 | SessionTimer (30 min) | `Session/SessionTimer.swift` |
| 6.1.3 | TranscriptManager | `Session/TranscriptManager.swift` |

### 6.2 Interview Service (Swift)
| ID | Task | File |
|----|------|------|
| 6.2.1 | Interview lifecycle | `Services/InterviewService.swift` |
| 6.2.2 | IPC coordination | `Services/InterviewService.swift` |
| 6.2.3 | Feedback request/receive | `Services/InterviewService.swift` |

---

## Phase 7: Integration & Distribution

**Goal**: Integrate all components and prepare for distribution

### 7.1 Entry Points
| ID | Task | File |
|----|------|------|
| 7.1.1 | Swift Application class | `main.swift` |
| 7.1.2 | Python server main | `backend/main.py` |
| 7.1.3 | Global error handling | Both |

### 7.2 Launcher
| ID | Task | File |
|----|------|------|
| 7.2.1 | Launcher script | `scripts/sdi-coach` |

> **Model Management in Launcher**:
> - Check Apple Silicon (MLX requires M1/M2/M3)
> - First run: prompt user to confirm download (~2GB total)
> - `--download-models` for manual download with prompt
> - `--download-models --yes` to skip confirmation
> - Models: MLX-Whisper (~1.5GB), Qwen3-TTS (~500MB)

---

## Parallelization Strategy

```
Timeline (병렬 개발 가능 구조)
═══════════════════════════════════════════════════════════════════

Phase 0 ──────┐
              │
Phase 1.1 ────┼── IPC Protocol (양쪽 동시 정의 필요)
              │
       ┌──────┴──────┐
       │             │
Phase 1.2       Phase 1.3
(Python IPC)    (Swift IPC)
       │             │
       └──────┬──────┘
              │
    ┌─────────┼─────────┬─────────┐
    │         │         │         │
Phase 2    Phase 3   Phase 4   Phase 5
(Audio)    (TTS)     (Agents)  (CLI/TUI)
    │         │         │         │
    └─────────┴─────────┴─────────┘
              │
         Phase 6
      (Session Mgmt)
              │
         Phase 7
      (Integration)
```

### Parallel Work Streams

| Stream | Swift Developer | Python Developer |
|--------|-----------------|------------------|
| Week 1 | Phase 0, 1.1, 1.3 | Phase 0, 1.1, 1.2 |
| Week 2 | Phase 2.1, 2.2, 5.1 | Phase 2.3, 3.1 |
| Week 3 | Phase 3.2, 5.2, 5.3 | Phase 4.1, 4.2, 4.3 |
| Week 4 | Phase 6.1, 6.2 | Phase 7.2 (backend) |
| Week 5 | Phase 7.1, 7.2 | Testing & Integration |

---

## TDD Workflow

Each task follows the 4-agent TDD cycle:

```
🧪 test-architect → ⚙️ implementer → 🔍 code-reviewer → ✨ refactorer
```

**Max 3 iterations per task**. If unresolved, stop and report.

---

## Verification Plan

### Unit Tests
- Swift: `swift test`
- Python: `pytest backend/tests/`

### Integration Tests
1. IPC communication test (Swift ↔ Python)
2. Audio pipeline test (mic → transcription)
3. Full interview flow test

### End-to-End Test
```bash
# Start application
./scripts/sdi-coach --debug

# Test commands
/start "Design a URL shortener"
# Speak into microphone
/pause
/end

# Verify feedback.md generated
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| MLX-Whisper compatibility | Test early, prepare fallback model |
| AVAudioEngine permissions | Clear error messages, documentation |
| Bedrock API costs | Mock during development |
| TTS latency | Buffering, preloading optimization |

---

## Post-MVP Improvements

### LLM Response Streaming

**Current**: Wait for complete LLM response before TTS processing.

**Improvement**: Use Strands Agents `stream_async()` for token-by-token streaming.

**Benefits**:
- Reduced perceived latency (first sentence arrives 1-2s faster)
- Pipelined TTS (generate sentence N+1 while playing sentence N)
- More natural conversation flow

**Trade-offs**:
- Increased implementation complexity
- Sentence boundary detection edge cases
- Current turn-based UX already provides acceptable latency

**Reference**: See `AGENT_STRATEGY.md` "Future Improvements" section.

### Other Potential Improvements

| Feature | Description | Priority |
|---------|-------------|----------|
| Session Resume | Save/restore interview sessions | Medium |
| Multi-language | Support non-English interviews | Low |
| Custom Prompts | User-defined interviewer personas | Low |
| Analytics | Track improvement over sessions | Medium |

---

## Reference Documents

- **PRD**: `./PRD.md`
- **TDD Workflow**: `./CLAUDE.md`
- **Agents**: `./.claude/agents/`
- **Agent Strategy**: `./AGENT_STRATEGY.md`
