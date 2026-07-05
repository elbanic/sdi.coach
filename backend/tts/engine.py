"""
TTS Engine Module - Qwen3-TTS MLX

Provides TTSEngine for text-to-speech using mlx_audio Qwen3-TTS model.
Audio is streamed chunk-by-chunk: playback starts as soon as the first
chunk is generated, without waiting for the full text to be synthesized.

The entire text is passed to the model at once to ensure consistent voice.
Model internally splits on sentence boundaries via split_pattern.

Model: mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16
Sample Rate: 24000 Hz
"""

import asyncio
import logging
import queue
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Optional, Callable, Dict, Awaitable

import numpy as np
from scipy import signal as scipy_signal

logger = logging.getLogger(__name__)

# Import mlx_audio load_model - will be mocked in tests
try:
    from mlx_audio.tts.utils import load_model
except ImportError:
    load_model = None  # Will be available when mlx_audio is installed

# Import sounddevice - will be mocked in tests
try:
    import sounddevice as sd
except ImportError:
    sd = None  # Will be available when sounddevice is installed


# =============================================================================
# Exceptions
# =============================================================================

class TTSError(Exception):
    """Base exception for TTS errors."""
    pass


class ModelInitializationError(TTSError):
    """Raised when model initialization fails."""
    pass


class GenerationError(TTSError):
    """Raised when audio generation fails."""
    pass


# =============================================================================
# Enums and Dataclasses
# =============================================================================

class TTSEngineState(str, Enum):
    """TTS Engine states."""
    IDLE = "idle"
    LOADING_MODEL = "loading_model"
    GENERATING = "generating"
    PLAYING = "playing"
    STOPPING = "stopping"


@dataclass
class VoiceConfig:
    """Voice configuration for TTS."""
    language: str
    voice_instruct: str


@dataclass
class AudioChunk:
    """Audio chunk from TTS generation."""
    audio: np.ndarray
    sample_rate: int
    is_final: bool = False


# =============================================================================
# Voice Presets (English voices for sdi.coach)
# =============================================================================

VOICE_PRESETS: Dict[str, VoiceConfig] = {
    "english_female": VoiceConfig(
        language="English",
        voice_instruct="A clear, friendly English female voice with natural intonation and professional tone",
    ),
    "english_male": VoiceConfig(
        language="English",
        voice_instruct="A deep, professional English male voice with clear articulation and calm demeanor",
    ),
}


# =============================================================================
# TTSEngine Implementation
# =============================================================================

class TTSEngine:
    """
    Qwen3-TTS based TTS engine.

    Handles model initialization, audio generation, and streaming playback.
    Entire text is passed to model at once for consistent voice.
    Model internally splits on sentence boundaries.
    """

    MODEL_ID = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"
    SAMPLE_RATE = 24000  # Model output sample rate
    MIN_BUFFER_CHUNKS = 3  # Minimum chunks to buffer before starting playback

    @staticmethod
    def _get_output_device_info() -> tuple[int | None, int]:
        """Get the default output device ID and sample rate.

        Returns:
            Tuple of (device_id, sample_rate). Device ID may be None to use system default.
        """
        if sd is None:
            return None, 48000
        try:
            device_id = sd.default.device[1]
            device_info = sd.query_devices(device_id, 'output')
            sample_rate = int(device_info['default_samplerate'])
            logger.debug("Output device: %s (ID=%d, SR=%d)", device_info['name'], device_id, sample_rate)
            return device_id, sample_rate
        except Exception as e:
            logger.warning("Failed to query output device: %s, using system default", e)
            return None, 48000

    @staticmethod
    def _resample_audio(audio: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
        """Resample audio from orig_sr to target_sr.

        Args:
            audio: Input audio samples
            orig_sr: Original sample rate
            target_sr: Target sample rate

        Returns:
            Resampled audio
        """
        if orig_sr == target_sr:
            return audio
        # Calculate number of samples in output
        num_samples = int(len(audio) * target_sr / orig_sr)
        return scipy_signal.resample(audio, num_samples).astype(np.float32)

    def __init__(self, status_callback: Optional[Callable[[TTSEngineState], None]] = None):
        """Initialize the TTS engine.

        Args:
            status_callback: Optional callback invoked on state changes.
        """
        self._status_callback = status_callback
        self._model = None
        self._state = TTSEngineState.IDLE
        self._stop_event = threading.Event()
        self._playback_thread: Optional[threading.Thread] = None
        self._voice_config = VOICE_PRESETS["english_male"]
        self._init_lock = asyncio.Lock()

    @property
    def state(self) -> TTSEngineState:
        """Return the current engine state."""
        return self._state

    @property
    def is_initialized(self) -> bool:
        """Check if the model is initialized."""
        return self._model is not None

    def _set_state(self, state: TTSEngineState) -> None:
        """Update state and notify callback if present."""
        self._state = state
        if self._status_callback is not None:
            self._status_callback(state)

    def get_voice_config(self) -> VoiceConfig:
        """Get the current voice configuration."""
        return self._voice_config

    def set_voice_config(self, config: VoiceConfig) -> None:
        """Set the voice configuration."""
        self._voice_config = config

    async def initialize(self) -> None:
        """Load the TTS model if not already loaded.

        Raises:
            ModelInitializationError: If model loading fails.
        """
        if self._model is not None:
            return

        async with self._init_lock:
            # Double-check after acquiring lock
            if self._model is not None:
                return

            if load_model is None:
                raise ModelInitializationError(
                    "mlx_audio not installed. Run: pip install mlx-audio[tts]"
                )

            logger.info("Loading TTS model: %s", self.MODEL_ID)
            self._set_state(TTSEngineState.LOADING_MODEL)

            try:
                loop = asyncio.get_running_loop()
                # Use wait_for with timeout
                self._model = await asyncio.wait_for(
                    loop.run_in_executor(None, load_model, self.MODEL_ID),
                    timeout=300.0
                )
                self._set_state(TTSEngineState.IDLE)
                logger.info("TTS model loaded successfully")

            except asyncio.TimeoutError:
                self._set_state(TTSEngineState.IDLE)
                raise ModelInitializationError(
                    "Model initialization timeout. Please check your system resources."
                )
            except ImportError as e:
                self._set_state(TTSEngineState.IDLE)
                raise ModelInitializationError(
                    f"mlx_audio not installed. Please install mlx-audio package. Error: {e}"
                )
            except Exception as e:
                self._set_state(TTSEngineState.IDLE)
                raise ModelInitializationError(f"Failed to initialize model: {e}") from e

    async def generate(self, text: str) -> list[tuple[np.ndarray, int]]:
        """Generate audio for the given text (no playback).

        Args:
            text: The text to synthesize.

        Returns:
            List of (audio_np, sample_rate) tuples.
        """
        if not text or not text.strip():
            return []

        # Ensure model is loaded
        await self.initialize()

        self._stop_event.clear()
        logger.debug("Generating audio for: %s...", text[:50])

        config = self._voice_config
        model = self._model
        loop = asyncio.get_running_loop()

        def generate_sync() -> list[tuple[np.ndarray, int]]:
            """Synchronous generation in executor."""
            chunks = []
            try:
                gen_iter = model.generate(
                    text=text,
                    instruct=config.voice_instruct,
                    lang_code=config.language,
                    stream=False,  # Get all at once for single sentence
                )
                # Handle both iterator and single result
                if hasattr(gen_iter, '__iter__') and not hasattr(gen_iter, 'audio'):
                    for chunk in gen_iter:
                        if self._stop_event.is_set():
                            break
                        audio_np = np.array(chunk.audio, dtype=np.float32).flatten()
                        chunks.append((audio_np, chunk.sample_rate))
                else:
                    # Single result
                    audio_np = np.array(gen_iter.audio, dtype=np.float32).flatten()
                    chunks.append((audio_np, gen_iter.sample_rate))
            except Exception as e:
                logger.error("Generation error: %s", e)
            return chunks

        return await loop.run_in_executor(None, generate_sync)

    async def speak_streamed(
        self,
        text: str,
        on_playback_start: Optional[Callable[[], Awaitable[None]]] = None,
    ) -> None:
        """Generate and play speech with streaming for consistent voice.

        Uses the full text for voice consistency. Audio is buffered and played
        continuously without gaps.

        Args:
            text: The full text to synthesize and play.
            on_playback_start: Async callback called when audio playback actually starts
                              (after initial buffering). Use for transcript sync.
        """
        if not text or not text.strip():
            return

        if sd is None:
            logger.error("sounddevice not installed, cannot play audio")
            return

        # Stop any existing playback before starting new one
        if self._state in (TTSEngineState.GENERATING, TTSEngineState.PLAYING):
            await self.stop()

        # Ensure model is loaded
        await self.initialize()

        self._stop_event.clear()
        self._set_state(TTSEngineState.GENERATING)
        logger.info("Starting streamed speech for text (%d chars)", len(text))

        config = self._voice_config
        model = self._model
        loop = asyncio.get_running_loop()

        # Completion event for async waiting
        completion_event = asyncio.Event()
        # Playback started event
        playback_started_event = asyncio.Event()

        def on_complete():
            loop.call_soon_threadsafe(completion_event.set)

        def on_started():
            loop.call_soon_threadsafe(playback_started_event.set)

        # Run generation + playback in thread
        self._playback_thread = threading.Thread(
            target=self._generate_and_play,
            args=(model, text, config, on_complete, on_started),
            daemon=True,
        )
        self._playback_thread.start()

        # Wait for playback to start, then call the callback
        await playback_started_event.wait()
        if on_playback_start is not None:
            await on_playback_start()

        # Wait for completion
        await completion_event.wait()

    async def play(self, audio_chunks: list[tuple[np.ndarray, int]]) -> None:
        """Play pre-generated audio chunks.

        Args:
            audio_chunks: List of (audio_np, sample_rate) tuples.
        """
        if not audio_chunks or sd is None:
            return

        self._stop_event.clear()
        completion_event = asyncio.Event()
        loop = asyncio.get_running_loop()

        def on_complete():
            loop.call_soon_threadsafe(completion_event.set)

        def play_sync():
            try:
                # Get current output device info
                device_id, output_sr = self._get_output_device_info()

                # Use output sample rate and explicit device for playback
                stream = sd.OutputStream(
                    device=device_id,
                    samplerate=output_sr,
                    channels=1,
                    dtype="float32"
                )
                stream.start()
                self._set_state(TTSEngineState.PLAYING)

                for audio_np, orig_sr in audio_chunks:
                    if self._stop_event.is_set():
                        break
                    # Resample to output sample rate
                    resampled = self._resample_audio(audio_np, orig_sr, output_sr)
                    stream.write(resampled.reshape(-1, 1))

                if not self._stop_event.is_set():
                    time.sleep(0.2)  # Let buffer drain
                stream.stop()
                stream.close()
            except Exception as e:
                logger.error("Playback error: %s", e)
            finally:
                self._set_state(TTSEngineState.IDLE)
                on_complete()

        self._playback_thread = threading.Thread(target=play_sync, daemon=True)
        self._playback_thread.start()
        await completion_event.wait()

    async def speak(self, text: str) -> None:
        """Generate and play speech for the given text (convenience method).

        Args:
            text: The text to synthesize and play.
        """
        if not text or not text.strip():
            return

        # Stop any current playback
        if self._state in (TTSEngineState.GENERATING, TTSEngineState.PLAYING):
            await self.stop()

        chunks = await self.generate(text)
        if chunks:
            await self.play(chunks)

    def _generate_and_play(
        self,
        model,
        text: str,
        config: VoiceConfig,
        on_complete: Callable,
        on_started: Optional[Callable] = None,
    ) -> None:
        """Generate audio chunks and play them using pipeline (runs in thread).

        Uses model.generate() with the entire text to ensure consistent voice.
        Buffers MIN_BUFFER_CHUNKS before starting playback for smooth audio.

        Args:
            model: The TTS model.
            text: Text to synthesize.
            config: Voice configuration.
            on_complete: Called when playback is done.
            on_started: Called when playback actually starts (after buffering).
        """
        if sd is None:
            logger.error("sounddevice not installed, cannot play audio")
            self._set_state(TTSEngineState.IDLE)
            on_complete()
            return

        playback_started = False

        # Queue for audio chunks (None = sentinel for end)
        audio_queue: queue.Queue = queue.Queue(maxsize=20)
        generator_error = [None]

        def generator_worker():
            """Generate audio using model.generate() for consistent voice."""
            try:
                if self._stop_event.is_set():
                    return

                text_preview = text[:50] + "..." if len(text) > 50 else text
                logger.debug("Generating audio for: %s", text_preview)

                # Use generate() with instruct for consistent voice across text
                # stream=True enables chunked output for smooth playback
                # split_pattern splits on sentence endings internally
                gen_iter = model.generate(
                    text=text,
                    instruct=config.voice_instruct,
                    lang_code=config.language,
                    split_pattern=r'[.!?。！？]\s*',  # Split on sentence endings
                    stream=True,
                    streaming_interval=2.0,  # Yield chunks every ~2 seconds
                )

                for chunk in gen_iter:
                    if self._stop_event.is_set():
                        break
                    audio_np = np.array(chunk.audio, dtype=np.float32).flatten()
                    audio_queue.put((audio_np, chunk.sample_rate))

            except Exception as exc:
                generator_error[0] = exc
                logger.error("Generator error: %s", exc)
            finally:
                audio_queue.put(None)  # Sentinel

        # Start generator thread
        generator_thread = threading.Thread(target=generator_worker, daemon=True)
        generator_thread.start()

        # Get output device info once at start
        device_id, output_sr = self._get_output_device_info()

        # Collect initial buffer then play
        stream = None
        start_time = time.monotonic()
        chunk_count = 0
        total_samples = 0
        initial_buffer = []

        try:
            while True:
                if self._stop_event.is_set():
                    break

                try:
                    item = audio_queue.get(timeout=0.1)
                except queue.Empty:
                    continue

                if item is None:  # Sentinel - generation complete
                    # Play any remaining buffered chunks
                    if initial_buffer and stream is None:
                        # Use explicit device and sample rate for playback
                        stream = sd.OutputStream(
                            device=device_id,
                            samplerate=output_sr,
                            channels=1,
                            dtype="float32"
                        )
                        stream.start()
                        logger.info("Starting playback with %d buffered chunks", len(initial_buffer))
                        self._set_state(TTSEngineState.PLAYING)
                        # Notify that playback started
                        if not playback_started and on_started is not None:
                            on_started()
                            playback_started = True
                        for buf_audio, buf_sr in initial_buffer:
                            # Resample to output sample rate
                            resampled = self._resample_audio(buf_audio, buf_sr, output_sr)
                            stream.write(resampled.reshape(-1, 1))
                            chunk_count += 1
                            total_samples += len(resampled)
                    break

                audio_np, sample_rate = item

                # Buffer initial chunks for smooth playback
                if stream is None:
                    initial_buffer.append((audio_np, sample_rate))
                    if len(initial_buffer) >= self.MIN_BUFFER_CHUNKS:
                        # Start playback with explicit device and sample rate
                        stream = sd.OutputStream(
                            device=device_id,
                            samplerate=output_sr,
                            channels=1,
                            dtype="float32"
                        )
                        stream.start()
                        first_chunk_time = time.monotonic() - start_time
                        logger.info(
                            "Buffer ready (%d chunks) in %.1f sec, starting playback at %d Hz",
                            len(initial_buffer), first_chunk_time, output_sr,
                        )
                        self._set_state(TTSEngineState.PLAYING)
                        # Notify that playback started
                        if not playback_started and on_started is not None:
                            on_started()
                            playback_started = True
                        # Play buffered chunks (resample each)
                        for buf_audio, buf_sr in initial_buffer:
                            resampled = self._resample_audio(buf_audio, buf_sr, output_sr)
                            stream.write(resampled.reshape(-1, 1))
                            chunk_count += 1
                            total_samples += len(resampled)
                        initial_buffer.clear()
                else:
                    # Normal playback - check buffer before writing
                    # If buffer is empty, wait for generation to catch up
                    if audio_queue.qsize() == 0:
                        logger.info("Buffer empty, pausing 1.5s for generation...")
                        time.sleep(1.5)

                    # Resample before writing
                    resampled = self._resample_audio(audio_np, sample_rate, output_sr)
                    stream.write(resampled.reshape(-1, 1))
                    chunk_count += 1
                    total_samples += len(resampled)

        except Exception as exc:
            logger.error("Playback failed: %s", exc)
        finally:
            generator_thread.join(timeout=2.0)

            if generator_error[0] is not None:
                logger.error("Generator thread error: %s", generator_error[0])

            if stream is not None:
                if not self._stop_event.is_set():
                    time.sleep(0.3)  # Let buffer drain
                stream.stop()
                stream.close()

            elapsed = time.monotonic() - start_time
            duration = total_samples / output_sr if total_samples > 0 else 0
            logger.info(
                "Playback done: %d chunks, %.1f sec audio, %.1f sec elapsed",
                chunk_count, duration, elapsed,
            )
            self._set_state(TTSEngineState.IDLE)
            on_complete()

    async def stop(self) -> None:
        """Stop current speech generation/playback."""
        if self._state == TTSEngineState.IDLE:
            return

        logger.info("Stop requested (current state: %s)", self._state.value)
        self._set_state(TTSEngineState.STOPPING)
        self._stop_event.set()

        # Wait for playback thread to finish (longer timeout for cleanup)
        if self._playback_thread is not None and self._playback_thread.is_alive():
            self._playback_thread.join(timeout=2.0)
            if self._playback_thread.is_alive():
                logger.warning("Playback thread still running after timeout")

        # Clear thread reference
        self._playback_thread = None
        self._set_state(TTSEngineState.IDLE)

    async def shutdown(self) -> None:
        """Stop playback and release model resources."""
        await self.stop()
        self._model = None
        self._set_state(TTSEngineState.IDLE)
