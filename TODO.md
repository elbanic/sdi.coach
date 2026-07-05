# sdi.coach TODO List

> **TDD Workflow**: 🧪 test-architect → ⚙️ implementer → 🔍 code-reviewer → ✨ refactorer
>
> **Legend**:
> - `[P]` = Can run in Parallel with other `[P]` tasks in same phase
> - `[S]` = Sequential (depends on previous tasks)
> - `[Swift]` / `[Python]` = Language/platform

---

## Phase 0: Project Foundation ✅

- [x] **0.1** `[P]` `[Swift]` Create Package.swift with dependencies
  - ArgumentParser, swift-testing
  - File: `Package.swift`

- [x] **0.2** `[P]` `[Python]` Create pyproject.toml with dependencies
  - mlx-whisper, strands-agents, boto3, pytest
  - File: `backend/pyproject.toml`
  - Virtual environment: `backend/.venv`

- [x] **0.3** `[P]` Create directory structure
  ```
  Sources/SDICoach/{Command,Audio,IPC,Services,Session,TUI}/
  backend/{ipc,transcription,tts,agents}/
  scripts/
  ```

- [x] **0.4** `[P]` Create configuration files
  - `.gitignore`
  - `.env.example`

---

## Phase 1: IPC Protocol Layer ✅

### 1.1 Protocol Definition (Critical Path - No Parallelization) ✅

- [x] **1.1.1** `[S]` `[Swift+Python]` Define message type enums
  - Files: `IPCProtocol.swift`, `protocol.py`
  - Types: audio_data, transcription, interview_*, feedback_*, tts_*, handshake_*

- [x] **1.1.2** `[S]` `[Swift+Python]` Implement JSON serialization/deserialization
  - Property test: round-trip encoding/decoding
  - Base64 encoding for audio data

- [x] **1.1.3** `[S]` `[Swift+Python]` Protocol version handshake
  - Version: 1.0

### 1.2 IPC Server (Python) - Parallel with 1.3 ✅

- [x] **1.2.1** `[P]` `[Python]` Asyncio Unix socket server
  - File: `backend/ipc/server.py`

- [x] **1.2.2** `[S]` `[Python]` Client connection management

- [x] **1.2.3** `[S]` `[Python]` Message dispatcher (type → handler routing)

- [x] **1.2.4** `[S]` `[Python]` Graceful shutdown (SIGTERM handling)

### 1.3 IPC Client (Swift) - Parallel with 1.2 ✅

- [x] **1.3.1** `[P]` `[Swift]` Unix socket client connection
  - File: `Sources/SDICoach/IPC/IPCClient.swift`

- [x] **1.3.2** `[S]` `[Swift]` Async message send/receive

- [x] **1.3.3** `[S]` `[Swift]` Reconnection with exponential backoff

- [x] **1.3.4** `[S]` `[Swift]` Response timeout handling

---

## Phase 2: Audio Pipeline ✅

### 2.1 Microphone Capture (Swift) - Parallel with 2.3 ✅

- [x] **2.1.1** `[P]` `[Swift]` AVAudioEngine initialization
  - File: `Sources/SDICoach/Audio/MicrophoneCapture.swift`

- [x] **2.1.2** `[S]` `[Swift]` PCM buffer continuous capture

- [x] **2.1.3** `[S]` `[Swift]` Audio session management (app state transitions)

- [x] **2.1.4** `[S]` `[Swift]` Error handling (no mic, permission denied)

### 2.2 Sample Rate Converter (Swift) - After 2.1 ✅

- [x] **2.2.1** `[S]` `[Swift]` vDSP resampling (48kHz → 16kHz)
  - File: `Sources/SDICoach/Audio/SampleRateConverter.swift`

- [x] **2.2.2** `[S]` `[Swift]` Buffer management for low latency

### 2.3 Transcription Engine (Python) - Parallel with 2.1, 2.2 ✅

- [x] **2.3.1** `[P]` `[Python]` MLX-Whisper model initialization
  - File: `backend/transcription/engine.py`

- [x] **2.3.2** `[S]` `[Python]` Audio buffering with overlap
  - File: `backend/transcription/service.py`

- [x] **2.3.3** `[S]` `[Python]` Streaming transcription (partial results)

- [x] **2.3.4** `[S]` `[Python]` VAD (Voice Activity Detection)

---

## Phase 3: TTS Integration ✅

### 3.1 TTS Engine (Python) - Parallel with Phase 2 ✅

- [x] **3.1.1** `[P]` `[Python]` Qwen3-TTS MLX model initialization
  - File: `backend/tts/engine.py`
  - Model: `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16`
  - Tests: 88 passed

- [x] **3.1.2** `[S]` `[Python]` Text → audio conversion

- [x] **3.1.3** `[S]` `[Python]` Voice preset management (English)
  - File: `backend/tts/service.py`
  - Tests: 69 passed

- [x] **3.1.4** `[S]` `[Python]` Chunked audio streaming

### 3.2 TTS Client (Swift) - After 3.1 ✅

- [x] **3.2.1** `[S]` `[Swift]` TTS state management (idle/speaking/paused)
  - File: `Sources/SDICoach/Services/TTSEngine.swift`
  - Tests: 48 passed

- [x] **3.2.2** `[S]` `[Swift]` Audio stream playback (AVAudioPlayer)

- [x] **3.2.3** `[S]` `[Swift]` Interruption handling (user starts speaking)

---

## Phase 4: AI Agents ✅

### 4.1 Interviewer Agent (Python) - Parallel with 4.2 ✅

- [x] **4.1.1** `[P]` `[Python]` Strands Agent + Bedrock Haiku setup
  - File: `backend/agents/interviewer.py`
  - Tests: 107 passed

- [x] **4.1.2** `[S]` `[Python]` System prompt design (interviewer persona)

- [x] **4.1.3** `[S]` `[Python]` Conversation context management

- [x] **4.1.4** `[S]` `[Python]` Follow-up question generation (3-5 per topic)

### 4.2 Feedback Agent (Python) - Parallel with 4.1 ✅

- [x] **4.2.1** `[P]` `[Python]` Strands Agent + Bedrock Opus setup
  - File: `backend/agents/feedback.py`
  - Tests: 52 passed

- [x] **4.2.2** `[S]` `[Python]` Feedback markdown template

- [x] **4.2.3** `[S]` `[Python]` Scoring logic (1-10 scale)

- [x] **4.2.4** `[S]` `[Python]` Recommendation generation

### 4.3 Agent Service (Python) - After 4.1, 4.2 ✅

- [x] **4.3.1** `[S]` `[Python]` Agent orchestration
  - File: `backend/agents/service.py`
  - Tests: 56 passed

- [x] **4.3.2** `[S]` `[Python]` Session state tracking

- [x] **4.3.3** `[S]` `[Python]` Error recovery (API failures)

### 4.4 E2E Integration Test (Python) - After 4.3 ✅

- [x] **4.4.1** `[S]` `[Python]` E2E interview flow test
  - File: `backend/tests/test_e2e_interview.py`
  - Automated interview flow test at IPC level
  - Validates 3-round Q&A ping-pong + feedback generation
  - Reference: `E2E_SCENARIO.md` (Scenario 1: URL Shortener)
  - Tests: 27 passed

---

## Phase 5: CLI & TUI ✅

### 5.1 Command System (Swift) - Parallel with 5.2 ✅

- [x] **5.1.1** `[P]` `[Swift]` Command enum (start, pause, end, quit)
  - File: `Sources/SDICoach/Command/Command.swift`
  - Tests: 98 passed

- [x] **5.1.2** `[S]` `[Swift]` CommandParser implementation
  - File: `Sources/SDICoach/Command/CommandParser.swift`

- [x] **5.1.3** `[S]` `[Swift]` ArgumentParser CLI options

### 5.2 Terminal Rendering (Swift) - Parallel with 5.1 ✅

- [x] **5.2.1** `[P]` `[Swift]` Terminal width detection
  - File: `Sources/SDICoach/Services/TerminalRenderer.swift`
  - Tests: 50 passed

- [x] **5.2.2** `[S]` `[Swift]` Unicode-aware text wrapping

- [x] **5.2.3** `[P]` `[Swift]` Raw mode input handling
  - File: `Sources/SDICoach/Services/InputHandler.swift`
  - Tests: 50 passed

- [x] **5.2.4** `[S]` `[Swift]` Fixed-position status bar

### 5.3 TUI Components (Swift) - After 5.2 ✅

- [x] **5.3.1** `[S]` `[Swift]` TUIEngine main event loop
  - File: `Sources/SDICoach/TUI/TUIEngine.swift`
  - Tests: 185 passed

- [x] **5.3.2** `[P]` `[Swift]` HeaderView (logo, version, timer)
  - File: `Sources/SDICoach/TUI/HeaderView.swift`

- [x] **5.3.3** `[P]` `[Swift]` StatusBar (interview status, mic status)
  - File: `Sources/SDICoach/TUI/StatusBar.swift`

- [x] **5.3.4** `[P]` `[Swift]` TranscriptView (real-time conversation)
  - File: `Sources/SDICoach/TUI/TranscriptView.swift`

- [x] **5.3.5** `[S]` `[Swift]` ApplicationMode state transitions
  - File: `Sources/SDICoach/TUI/ApplicationMode.swift`

---

## Phase 6: Session Management ✅

### 6.1 Session Components (Swift) ✅

- [x] **6.1.1** `[S]` `[Swift]` InterviewSession state management
  - File: `Sources/SDICoach/Session/InterviewSession.swift`
  - Tests: 80 passed

- [x] **6.1.2** `[P]` `[Swift]` SessionTimer (30-minute countdown)
  - File: `Sources/SDICoach/Session/SessionTimer.swift`
  - Tests: 70 passed

- [x] **6.1.3** `[P]` `[Swift]` TranscriptManager (accumulation, export)
  - File: `Sources/SDICoach/Session/TranscriptManager.swift`
  - File: `Sources/SDICoach/Session/TranscriptEntry.swift` (refactored)
  - Tests: 83 passed

### 6.2 Interview Service (Swift) - After 6.1 ✅

- [x] **6.2.1** `[S]` `[Swift]` Interview lifecycle (start → interview → end)
  - File: `Sources/SDICoach/Services/InterviewService.swift`
  - Tests: 69 passed

- [x] **6.2.2** `[S]` `[Swift]` IPC message coordination

- [x] **6.2.3** `[S]` `[Swift]` Feedback request and markdown saving

---

## Phase 7: Integration & Distribution ✅

### 7.1 Entry Points

- [x] **7.1.1** `[P]` `[Swift]` Application class (component assembly)
  - File: `Sources/SDICoach/SDICoach.swift` ✅

- [x] **7.1.2** `[P]` `[Python]` Backend server main (service initialization)
  - File: `backend/main.py` ✅

- [x] **7.1.3** `[S]` Global error handling and signal handling ✅

### 7.2 Launcher & Distribution

- [x] **7.2.1** `[S]` Launcher script
  - File: `scripts/sdi-coach` ✅
  - Backend process management, CLI execution, env validation
  - Apple Silicon check (MLX requires M1/M2/M3)
  - First run: prompt user to confirm model download (~2GB total)
  - `--download-models` option for manual download
  - `--download-models --yes` to skip confirmation prompt

---

## Parallelization Summary

### By Phase

| Phase | Parallel Tasks | Sequential Tasks |
|-------|----------------|------------------|
| 0 | 0.1, 0.2, 0.3, 0.4 | - |
| 1.1 | - | All (Critical Path) |
| 1.2 + 1.3 | 1.2.1 ‖ 1.3.1 | Rest sequential |
| 2 | 2.1.1 ‖ 2.3.1 | Rest sequential |
| 3 | 3.1.1 | Rest sequential |
| 4 | 4.1.1 ‖ 4.2.1 | Rest sequential |
| 5 | 5.1.1 ‖ 5.2.1, 5.2.3, 5.3.2-5.3.4 | Rest sequential |
| 6 | 6.1.2 ‖ 6.1.3 | Rest sequential |
| 7 | 7.1.1 ‖ 7.1.2 | Rest sequential |

### Cross-Phase Parallelization

```
After Phase 1 completes:
├── Phase 2 (Audio)      ─┐
├── Phase 3 (TTS)        ─┼── All parallel
├── Phase 4 (Agents)     ─┤
└── Phase 5 (CLI/TUI)    ─┘
```

### Developer Assignment (2-Person Team)

| Week | Swift Developer | Python Developer |
|------|-----------------|------------------|
| 1 | 0.1, 0.3, 1.1, 1.3 | 0.2, 0.4, 1.1, 1.2 |
| 2 | 2.1, 2.2, 5.1 | 2.3, 3.1 |
| 3 | 3.2, 5.2, 5.3 | 4.1, 4.2, 4.3 |
| 4 | 6.1, 6.2, 7.1.1 | 7.1.2, 7.2 |
| 5 | Integration testing | Integration testing |

---

## Quick Start Commands

```bash
# Phase 0: Setup
swift package init --type executable --name SDICoach
cd backend && python -m venv .venv && pip install -e .

# Development
swift build                    # Build Swift CLI
cd backend && pytest           # Run Python tests
swift test                     # Run Swift tests

# Run
./scripts/sdi-coach            # Unified launcher
./scripts/sdi-coach --debug    # Debug mode
```

---

## Notes

- **TDD**: Each task follows 🧪→⚙️→🔍→✨ cycle (max 3 iterations)
- **Stop Condition**: After 3 failed iterations, report to user
- **Completion**: Confirm with user before marking task complete
