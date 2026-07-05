"""
Transcription Service

Integrates TranscriptionEngine with audio buffering for real-time transcription.
Simple approach: transcribe 2-second chunks and send to CLI.
CLI handles aggregation for display.
"""

import asyncio
import logging
import re
import time
from typing import Callable, Optional, Awaitable, AsyncIterator

import numpy as np

from .engine import TranscriptionEngine, TranscriptionResult

logger = logging.getLogger(__name__)


def is_hallucination(text: str) -> bool:
    """Check if text appears to be a Whisper hallucination."""
    if not text or len(text.strip()) < 2:
        return True

    # Check for special tokens like <|bn|>, <|en|>
    if re.search(r'<\|[a-z]+\|>', text):
        return True

    # Check for excessive repetition (same word/phrase repeated many times)
    words = text.split()
    if len(words) >= 4:
        unique_ratio = len(set(words)) / len(words)
        if unique_ratio < 0.2:  # Less than 20% unique words
            return True

    # Check for common hallucination phrases
    lower_text = text.lower().strip()
    hallucination_phrases = [
        'thank you',
        'thank you.',
        'thanks for watching',
        'thanks for watching.',
        'subscribe',
        'subscribe.',
        'like and subscribe',
        'like and subscribe.',
    ]
    for phrase in hallucination_phrases:
        if lower_text == phrase:
            return True

    return False


class TranscriptionService:
    """
    Service layer for transcription with audio buffering.

    Simple approach:
    - Buffer audio for 2 seconds
    - Transcribe the buffer
    - Send chunk to CLI
    - CLI handles aggregation/display
    """

    # Audio buffer settings
    SAMPLE_RATE = 16000
    BUFFER_DURATION_SECONDS = 2.0  # Transcribe every 2 seconds
    MIN_BUFFER_SAMPLES = int(SAMPLE_RATE * 0.5)  # Minimum 0.5 seconds

    def __init__(
        self,
        engine: Optional[TranscriptionEngine] = None,
        on_transcription: Optional[Callable[[TranscriptionResult], Awaitable[None]]] = None
    ):
        """
        Initialize the transcription service.

        Args:
            engine: TranscriptionEngine instance. Creates new one if not provided.
            on_transcription: Callback for transcription results.
        """
        self.engine = engine or TranscriptionEngine()
        self._on_transcription = on_transcription

        # Simple audio buffer
        self._buffer: list[float] = []
        self._buffer_timestamp: Optional[float] = None
        self._lock = asyncio.Lock()

        self._running = False
        self._stopped = False
        self._paused = False  # Pause transcription (e.g., during TTS to avoid GPU conflict)
        self._resume_time: Optional[float] = None  # Time when resumed, to discard old queued audio
        self._process_task: Optional[asyncio.Task] = None

        # Queue for async iterator
        self._result_queue: asyncio.Queue[TranscriptionResult] = asyncio.Queue()

    async def start(self) -> None:
        """Start the transcription service."""
        if self._running:
            return

        await self.engine.initialize()
        self._running = True
        self._stopped = False

        # Reset buffer
        self._buffer = []
        self._buffer_timestamp = None

        # Start background processing task
        self._process_task = asyncio.create_task(self._process_loop())

        logger.info("Transcription service started")

    async def stop(self) -> None:
        """Stop the transcription service."""
        if not self._running:
            return

        self._running = False

        if self._process_task:
            self._process_task.cancel()
            try:
                await self._process_task
            except asyncio.CancelledError:
                pass

        # Process any remaining audio
        await self._flush_buffer()

        await self.engine.shutdown()
        self._stopped = True
        logger.info("Transcription service stopped")

    async def process_audio(
        self,
        samples: list[float],
        timestamp: float
    ) -> None:
        """
        Process incoming audio data.

        Args:
            samples: Audio samples (16kHz, mono, float32)
            timestamp: Timestamp of the audio data
        """
        if not samples:
            return

        # Skip audio while paused (don't accumulate during TTS)
        if self._paused:
            return

        # Discard old queued audio that arrived after resume
        # (IPC messages can queue during TTS and arrive after resume is called)
        if self._resume_time is not None:
            # Give 0.5 second grace period for queued messages to flush
            if timestamp < self._resume_time - 0.5:
                logger.debug(f"Discarding old audio (timestamp {timestamp:.1f} < resume_time {self._resume_time:.1f})")
                return
            # Clear resume_time after 2 seconds to allow normal processing
            if time.time() - self._resume_time > 2.0:
                self._resume_time = None

        async with self._lock:
            # Add samples to buffer
            self._buffer.extend(samples)

            # Track first timestamp in buffer
            if self._buffer_timestamp is None:
                self._buffer_timestamp = timestamp

            # Log buffer status (debug level)
            buffer_len = len(self._buffer)
            buffer_seconds = buffer_len / self.SAMPLE_RATE
            logger.debug(f"Received {len(samples)} samples, buffer: {buffer_seconds:.1f}s")

    async def stream_transcriptions(self) -> AsyncIterator[TranscriptionResult]:
        """
        Async iterator for streaming transcription results.

        Yields:
            TranscriptionResult for each processed audio segment
        """
        while self._running or not self._result_queue.empty():
            try:
                result = await asyncio.wait_for(
                    self._result_queue.get(),
                    timeout=0.5
                )
                yield result
            except asyncio.TimeoutError:
                continue

    def set_transcription_callback(
        self,
        callback: Callable[[TranscriptionResult], Awaitable[None]]
    ) -> None:
        """Set the callback for transcription results."""
        self._on_transcription = callback

    @property
    def is_running(self) -> bool:
        """Check if the service is running."""
        return self._running

    @property
    def is_paused(self) -> bool:
        """Check if the service is paused."""
        return self._paused

    @property
    def buffer_size(self) -> int:
        """Get current buffer size in samples."""
        return len(self._buffer)

    def pause(self) -> None:
        """Pause transcription processing (e.g., during TTS to avoid GPU conflict)."""
        if not self._paused:
            self._paused = True
            logger.info("Transcription paused")

    def resume(self) -> None:
        """Resume transcription processing and clear old buffer."""
        if self._paused:
            # Clear any audio that accumulated during pause
            self._buffer = []
            self._buffer_timestamp = None
            # Set resume time to discard old queued IPC messages
            self._resume_time = time.time()
            self._paused = False
            logger.info("Transcription resumed (buffer cleared, resume_time set)")

    async def _process_loop(self) -> None:
        """Background loop to process buffered audio."""
        while self._running:
            try:
                await asyncio.sleep(0.5)  # Check buffers every 500ms
                await self._check_and_process_buffer()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in process loop: {e}")
                continue

    async def _check_and_process_buffer(self) -> None:
        """Check buffer and process if ready."""
        # Skip processing if paused (e.g., during TTS to avoid GPU conflict)
        if self._paused:
            return

        buffer_threshold = int(self.SAMPLE_RATE * self.BUFFER_DURATION_SECONDS)

        async with self._lock:
            buffer = self._buffer

            if len(buffer) >= buffer_threshold:
                # Extract buffer for processing
                samples = buffer[:buffer_threshold]
                self._buffer = buffer[buffer_threshold:]
                timestamp = self._buffer_timestamp or time.time()

                # Update timestamp for remaining buffer
                if self._buffer:
                    self._buffer_timestamp = time.time()
                else:
                    self._buffer_timestamp = None
            else:
                return

        # Process outside lock
        await self._transcribe_buffer(samples, timestamp)

    async def _transcribe_buffer(
        self,
        samples: list[float],
        timestamp: float
    ) -> None:
        """
        Transcribe a buffer of audio samples.

        Args:
            samples: Audio samples to transcribe
            timestamp: Timestamp of the audio
        """
        try:
            logger.debug(f"Starting transcription of {len(samples)} samples...")

            # Convert samples to bytes (16-bit PCM)
            audio_array = np.array(samples, dtype=np.float32)
            audio_int16 = (audio_array * 32768).astype(np.int16)
            audio_bytes = audio_int16.tobytes()

            result = await self.engine.transcribe(audio_bytes, timestamp)

            if result.text:
                # Filter hallucinations
                if is_hallucination(result.text):
                    logger.debug(f"Filtered hallucination: {result.text[:50]}...")
                    return

                logger.info(f"Transcription: {result.text}")

                # Add to queue for async iterator
                await self._result_queue.put(result)

                # Call callback
                if self._on_transcription:
                    try:
                        await self._on_transcription(result)
                    except Exception as e:
                        logger.error(f"Callback error: {e}")
            else:
                logger.debug("No speech detected")

        except Exception as e:
            logger.error(f"Transcription error: {e}")

    async def _flush_buffer(self) -> None:
        """Process any remaining audio in buffer."""
        async with self._lock:
            buffer = self._buffer
            timestamp = self._buffer_timestamp or time.time()
            self._buffer = []
            self._buffer_timestamp = None

        if len(buffer) >= self.MIN_BUFFER_SAMPLES:
            await self._transcribe_buffer(buffer, timestamp)
