"""
TTS Pipeline Module

Provides a pipeline for concurrent TTS generation and playback.
Sentences are queued and processed in order, with callbacks when
each sentence starts playing (for transcript updates).

Flow:
1. Text is split into sentences
2. Sentences are added to queue
3. Background worker processes queue
4. When playback starts, callback is invoked with the sentence
5. CLI can update transcript in real-time
"""

import asyncio
import logging
from dataclasses import dataclass
from typing import Callable, Optional, Awaitable

from .engine import TTSEngine
from .sentence_splitter import SentenceSplitter

logger = logging.getLogger(__name__)


@dataclass
class PipelineItem:
    """Item in the TTS pipeline queue."""
    sentence: str
    message_id: Optional[str] = None


class TTSPipeline:
    """Pipeline for streaming TTS with real-time transcript updates.

    Processes sentences concurrently:
    - Sentences are queued as they arrive
    - Background worker plays them in order
    - When each sentence starts playing, callback is invoked
    """

    def __init__(
        self,
        engine: TTSEngine,
        on_sentence_playing: Optional[Callable[[str, Optional[str]], Awaitable[None]]] = None,
        on_speaking_start: Optional[Callable[[], Awaitable[None]]] = None,
        on_speaking_end: Optional[Callable[[], Awaitable[None]]] = None,
    ):
        """Initialize TTS pipeline.

        Args:
            engine: TTS engine to use for speech synthesis.
            on_sentence_playing: Async callback invoked when a sentence starts playing.
                                 Args: (sentence_text, message_id)
            on_speaking_start: Async callback when TTS starts speaking (pause transcription).
            on_speaking_end: Async callback when TTS stops speaking (resume transcription).
        """
        self._engine = engine
        self._on_sentence_playing = on_sentence_playing
        self._on_speaking_start = on_speaking_start
        self._on_speaking_end = on_speaking_end
        self._splitter = SentenceSplitter()
        self._queue: asyncio.Queue[Optional[PipelineItem]] = asyncio.Queue()
        self._worker_task: Optional[asyncio.Task] = None
        self._running = False
        self._is_speaking = False

    async def start(self) -> None:
        """Start the pipeline worker."""
        if self._running:
            return

        self._running = True
        self._worker_task = asyncio.create_task(self._worker())
        logger.info("TTS pipeline started")

    async def stop(self) -> None:
        """Stop the pipeline worker and clear queue."""
        if not self._running:
            return

        self._running = False

        # Signal worker to stop
        await self._queue.put(None)

        # Wait for worker to finish
        if self._worker_task is not None:
            try:
                await asyncio.wait_for(self._worker_task, timeout=2.0)
            except asyncio.TimeoutError:
                self._worker_task.cancel()
                try:
                    await self._worker_task
                except asyncio.CancelledError:
                    pass

        # Clear remaining items
        while not self._queue.empty():
            try:
                self._queue.get_nowait()
            except asyncio.QueueEmpty:
                break

        # Stop any current playback
        await self._engine.stop()

        logger.info("TTS pipeline stopped")

    async def add_text(self, text: str, message_id: Optional[str] = None) -> None:
        """Add text to the pipeline (will be split into sentences).

        Args:
            text: Full text to speak.
            message_id: Optional message ID for tracking.
        """
        if not text or not text.strip():
            return

        # Split text into sentences
        sentences = self._splitter.split(text)

        logger.debug("Adding %d sentences to TTS pipeline", len(sentences))

        # Queue each sentence
        for sentence in sentences:
            item = PipelineItem(sentence=sentence, message_id=message_id)
            await self._queue.put(item)

    async def add_sentence(self, sentence: str, message_id: Optional[str] = None) -> None:
        """Add a single sentence to the pipeline (no splitting).

        Args:
            sentence: Single sentence to speak.
            message_id: Optional message ID for tracking.
        """
        if not sentence or not sentence.strip():
            return

        item = PipelineItem(sentence=sentence, message_id=message_id)
        await self._queue.put(item)

    async def _worker(self) -> None:
        """Background worker that processes the queue."""
        logger.debug("TTS pipeline worker started")

        while self._running:
            try:
                # Wait for next item
                item = await self._queue.get()

                # None is the stop signal
                if item is None:
                    break

                logger.debug("Processing sentence: %s...", item.sentence[:30])

                # Notify speaking start (pause transcription to avoid GPU conflict)
                if not self._is_speaking:
                    self._is_speaking = True
                    if self._on_speaking_start is not None:
                        try:
                            await self._on_speaking_start()
                        except Exception as e:
                            logger.error("Error in on_speaking_start callback: %s", e)

                # Invoke callback BEFORE starting playback (to update transcript)
                if self._on_sentence_playing is not None:
                    try:
                        await self._on_sentence_playing(item.sentence, item.message_id)
                    except Exception as e:
                        logger.error("Error in on_sentence_playing callback: %s", e)

                # Play the sentence (blocks until done)
                try:
                    await self._engine.speak(item.sentence)
                except Exception as e:
                    logger.error("TTS error for sentence: %s", e)

                # Check if queue is empty - if so, notify speaking end
                if self._queue.empty():
                    self._is_speaking = False
                    if self._on_speaking_end is not None:
                        try:
                            await self._on_speaking_end()
                        except Exception as e:
                            logger.error("Error in on_speaking_end callback: %s", e)

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Pipeline worker error: %s", e)

        # Ensure speaking end is called on shutdown
        if self._is_speaking:
            self._is_speaking = False
            if self._on_speaking_end is not None:
                try:
                    await self._on_speaking_end()
                except Exception as e:
                    logger.error("Error in on_speaking_end callback: %s", e)

        logger.debug("TTS pipeline worker stopped")

    @property
    def is_running(self) -> bool:
        """Check if pipeline is running."""
        return self._running

    @property
    def queue_size(self) -> int:
        """Get current queue size."""
        return self._queue.qsize()
