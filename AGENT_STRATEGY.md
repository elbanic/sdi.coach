# AI Agent Implementation Strategy

## Overview

This document describes the implementation strategy for AI agents (Interviewer, Feedback) using Strands Agents with Amazon Bedrock.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Agent Architecture                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  User Speech → STT → InterviewerAgent                               │
│                            │                                         │
│                            ▼ agent(message)                         │
│                      Bedrock (Sonnet 4.5)                           │
│                            │                                         │
│                            ▼ complete response                      │
│                      TTS Pipeline (sentence split)                  │
│                            │                                         │
│                            ▼                                        │
│                      Audio Playback                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Details

### 1. Interviewer Agent

**File**: `backend/agents/interviewer.py`

- Uses Strands Agent with Bedrock (Claude Sonnet 4.5)
- Synchronous call via `agent(message)` - waits for complete response
- Conversation context managed internally by Strands + custom ConversationContext
- Follow-up tracking to avoid repetitive questions

### 2. Feedback Agent

**File**: `backend/agents/feedback.py`

- Uses Strands Agent with Bedrock (Claude Sonnet 4.5)
- Generates comprehensive markdown feedback from transcript
- Scores candidate performance (1-10)

### 3. Agent Service (Orchestration)

**File**: `backend/agents/service.py`

- Coordinates InterviewerAgent and FeedbackAgent
- Manages session state (IDLE, INTERVIEWING, GENERATING_FEEDBACK)
- Records transcript for feedback generation
- TTS callback integration for sentence-by-sentence playback

---

## TTS Integration

The response flow:

1. Agent generates complete response
2. Response sent to TTSPipeline
3. SentenceSplitter splits into sentences
4. Each sentence queued for TTS playback
5. Sentences played sequentially

This provides good UX without LLM streaming complexity.

---

## Message Flow (IPC)

```
Swift CLI                          Python Backend
    │                                    │
    │ ── interview_response ──────────►  │
    │    {text: "user answer"}           │
    │                                    │
    │                              AgentService.process_user_response()
    │                                    │
    │                              (waits for complete response)
    │                                    │
    │  ◄── interview_followup ────────   │
    │      {question: "full response"}   │
    │                                    │
    │                              TTSPipeline processes sentences
    │                                    │
    │  ◄── tts_status ─────────────────  │  (speaking)
    │  ◄── interview_question ─────────  │  (transcript update)
    │  ◄── tts_status ─────────────────  │  (completed)
    │                                    │
```

---

## Conversation Context

Strands Agents handles conversation context internally, but we also maintain our own transcript for:

1. **Feedback Generation**: Full transcript needed for analysis
2. **Session Persistence**: Save/resume interview sessions
3. **Debugging**: Log conversation flow

---

## Error Handling

```python
class AgentService:
    async def process_user_response(self, user_input: str):
        try:
            response = await self.interviewer.process_user_response(user_input)
            # Process response...
        except Exception as e:
            logger.error(f"Agent error: {e}")
            # Return fallback response
```

---

## Configuration

### Environment Variables

```bash
# Bedrock Model IDs
SDICOACH_INTERVIEWER_MODEL=us.anthropic.claude-sonnet-4-5-20250929-v1:0
SDICOACH_FEEDBACK_MODEL=us.anthropic.claude-sonnet-4-5-20250929-v1:0

# AWS Region
AWS_REGION=us-west-2
```

---

## Future Improvements (Post-MVP)

### LLM Response Streaming

Currently, we wait for the complete LLM response before processing. Strands Agents supports `stream_async()` for token-by-token streaming:

```python
async for event in agent.stream_async(prompt):
    if "data" in event:
        text_chunk = event["data"]
        # Process incrementally...
```

**Benefits**:
- Reduced perceived latency (first sentence arrives faster)
- Pipelined TTS (generate sentence N+1 while playing N)

**Trade-offs**:
- Increased complexity
- Edge case handling (sentence boundaries)
- Current turn-based UX doesn't require real-time streaming

**Reference**: https://strandsagents.com/latest/documentation/docs/user-guide/concepts/streaming/async-iterators/

---

## References

- **Strands Agents Docs**: https://strandsagents.com/latest/documentation/docs/
- **PRD.md**: Agent system prompts and message types
