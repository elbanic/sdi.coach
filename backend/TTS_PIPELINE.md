# TTS Pipeline Architecture

## Problem Statement

When the LLM (interviewer agent) generates a response, it returns the **entire text at once**. Converting this full text to speech using TTS would cause significant delay:

```
LLM Response (500 chars, ~5 sentences)
    ↓
TTS Generation (entire text) → 10-15 seconds delay
    ↓
User finally hears audio
```

This creates a poor user experience where the user waits in silence for a long time before hearing anything.

## Solution: Pipelined TTS Generation

Instead of processing the entire text at once, we split it into sentences and process them in a pipeline:

```
LLM Response
    ↓
Split into sentences: [S1, S2, S3, S4, S5]
    ↓
Pipeline Processing:

Time 0s:   Generate S1 (2-3 sec)
Time 3s:   S1 ready → Play S1 + Send S1 transcript + Start generating S2
Time 3-6s: S1 playing... + S2 generating...
Time 6s:   S1 done, S2 ready → Play S2 + Send S2 transcript + Start generating S3
...
```

## Key Benefits

### 1. Reduced Time-to-First-Audio
- **Before**: User waits 10-15 seconds for entire TTS generation
- **After**: User hears first sentence in 2-3 seconds

### 2. Parallel Processing
- While sentence N is playing, sentence N+1 is being generated
- Generation time is "hidden" behind playback time
- Total perceived delay ≈ first sentence generation time only

### 3. Natural Transcript Updates
- Transcript updates sentence-by-sentence as audio plays
- Mimics real-time speech transcription
- User sees what they're hearing, synchronized

## Implementation Details

### TTSEngine Methods

```python
# Separate generation and playback
async def generate(text: str) -> list[tuple[np.ndarray, int]]
async def play(audio_chunks: list) -> None

# Convenience method (generate + play)
async def speak(text: str) -> None
```

### Pipeline Flow (main.py)

```python
async def _speak_sentences_pipelined(sentences, message_id, is_question):
    # Pre-generate first sentence
    current_audio = await self.tts_engine.generate(sentences[0])

    for i, sentence in enumerate(sentences):
        # Start generating next sentence in background
        next_audio_task = None
        if i + 1 < len(sentences):
            next_audio_task = asyncio.create_task(
                self.tts_engine.generate(sentences[i + 1])
            )

        # Send transcript (playback about to start)
        await self.ipc_server.send_message(transcript_msg)

        # Play current sentence
        await self.tts_engine.play(current_audio)

        # Get next sentence audio (already generated in background)
        if next_audio_task:
            current_audio = await next_audio_task
```

## Performance Comparison

| Approach | Time to First Audio | Total Time | User Experience |
|----------|---------------------|------------|-----------------|
| Full text TTS | 10-15 sec | 10-15 sec | Poor (long silence) |
| Sequential sentences | 2-3 sec | 15-20 sec | Better (but gaps) |
| **Pipelined sentences** | 2-3 sec | 10-12 sec | Best (smooth) |

## GPU Conflict Handling

MLX-Whisper (transcription) and MLX-TTS share the same GPU. To avoid conflicts:

1. Pause transcription when TTS pipeline starts
2. Resume transcription when TTS pipeline completes

```python
# In _handle_interview_start / _handle_interview_response
if self._transcription is not None:
    self._transcription.pause()

await self._speak_sentences_pipelined(sentences, ...)

if self._transcription is not None:
    self._transcription.resume()
```

## Sentence Splitting

Uses `SentenceSplitter` to split text on sentence boundaries:
- Handles English punctuation (. ! ?)
- Preserves abbreviations (Mr., Dr., etc.)
- Handles URLs and decimal numbers

## Voice Consistency

Each sentence uses the same `voice_instruct` configuration, ensuring consistent voice across the entire response even though sentences are generated separately.
