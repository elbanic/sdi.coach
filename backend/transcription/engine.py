"""
MLX-Whisper Transcription Engine

Provides real-time transcription using MLX-Whisper for local processing.
"""

import asyncio
import logging
import time
from dataclasses import dataclass
from typing import Optional
import numpy as np

logger = logging.getLogger(__name__)


class TranscriptionError(Exception):
    """Base exception for transcription errors."""
    pass


class ModelInitializationError(TranscriptionError):
    """Raised when model initialization fails."""
    pass


class AudioProcessingError(TranscriptionError):
    """Raised when audio processing fails."""
    pass


@dataclass
class TranscriptionResult:
    """Result of a transcription operation."""
    text: str
    timestamp: float
    is_final: bool = True
    confidence: float = 1.0

    def to_dict(self) -> dict:
        """Convert to dictionary for IPC serialization."""
        return {
            "text": self.text,
            "timestamp": self.timestamp,
            "is_final": self.is_final,
            "confidence": self.confidence
        }


class TranscriptionEngine:
    """
    MLX-Whisper based transcription engine.

    Handles model initialization, audio processing, and transcription.
    """

    DEFAULT_MODEL = "mlx-community/whisper-large-v3-mlx"
    SAMPLE_RATE = 16000  # Expected input sample rate

    def __init__(self, model_name: Optional[str] = None):
        """
        Initialize the transcription engine.

        Args:
            model_name: MLX-Whisper model to use. Defaults to whisper-large-v3-mlx.
        """
        self.model_name = model_name or self.DEFAULT_MODEL
        self._model = None
        self._initialized = False
        self._lock = asyncio.Lock()

    async def initialize(self) -> None:
        """
        Initialize the MLX-Whisper model.

        Loads the model on startup for faster subsequent transcriptions.

        Raises:
            ModelInitializationError: If model loading fails
        """
        if self._initialized:
            return

        async with self._lock:
            if self._initialized:
                return

            logger.info(f"Initializing MLX-Whisper model: {self.model_name}")

            try:
                # Import mlx_whisper here to avoid import errors if not installed
                import mlx_whisper

                # Load model (this downloads if not cached)
                # Run in executor to avoid blocking event loop
                loop = asyncio.get_event_loop()
                await asyncio.wait_for(
                    loop.run_in_executor(None, self._load_model),
                    timeout=300.0
                )

                self._initialized = True
                logger.info("MLX-Whisper model initialized successfully")

            except asyncio.TimeoutError:
                logger.error("Model initialization timeout after 300 seconds")
                raise ModelInitializationError(
                    "Model initialization timeout. Please check your system resources."
                )
            except ImportError as e:
                logger.error("mlx-whisper not installed. Run: pip install mlx-whisper")
                raise ModelInitializationError(
                    "mlx-whisper not installed. Run: pip install mlx-whisper"
                ) from e
            except Exception as e:
                logger.error(f"Failed to initialize MLX-Whisper: {e}")
                raise ModelInitializationError(f"Failed to initialize model: {e}") from e

    def _load_model(self) -> None:
        """Load the MLX-Whisper model (blocking operation)."""
        import mlx_whisper
        # Perform a dummy transcription to ensure model is loaded
        # This triggers model download and caching
        dummy_audio = np.zeros(self.SAMPLE_RATE, dtype=np.float32)
        mlx_whisper.transcribe(
            dummy_audio,
            path_or_hf_repo=self.model_name,
            language="en",
            verbose=False
        )
        self._model = self.model_name

    async def transcribe(
        self,
        audio_data: bytes,
        timestamp: Optional[float] = None
    ) -> TranscriptionResult:
        """
        Transcribe audio data and return result.

        Args:
            audio_data: Audio samples (16kHz, mono, 16-bit PCM bytes)
            timestamp: Optional timestamp for the audio segment

        Returns:
            TranscriptionResult with text and timestamp

        Raises:
            AudioProcessingError: If transcription fails
        """
        if not self._initialized:
            await self.initialize()

        timestamp = timestamp or time.time()

        # Convert audio data to numpy array
        try:
            audio_array = self._prepare_audio(audio_data)
        except Exception as e:
            logger.error(f"Failed to prepare audio data: {e}")
            raise AudioProcessingError(f"Invalid audio data: {e}") from e

        if len(audio_array) == 0:
            return TranscriptionResult(
                text="",
                timestamp=timestamp,
                confidence=0.0
            )

        try:
            import mlx_whisper

            # Run transcription in executor to avoid blocking
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                None,
                lambda: mlx_whisper.transcribe(
                    audio_array,
                    path_or_hf_repo=self.model_name,
                    language="en",
                    verbose=False
                )
            )

            text = result.get("text", "").strip()

            if text:
                logger.debug(f"Transcribed: {text[:50]}...")

            return TranscriptionResult(
                text=text,
                timestamp=timestamp,
                confidence=1.0
            )

        except Exception as e:
            logger.error(f"Transcription failed: {e}")
            raise AudioProcessingError(f"Transcription failed: {e}") from e

    def _prepare_audio(self, audio_data: bytes) -> np.ndarray:
        """
        Prepare audio data for transcription.

        Converts various input formats to numpy float32 array.
        """
        if not isinstance(audio_data, bytes):
            raise ValueError(f"Unsupported audio data type: {type(audio_data)}")

        if len(audio_data) == 0:
            return np.array([], dtype=np.float32)

        # Assume 16-bit PCM
        audio_array = np.frombuffer(audio_data, dtype=np.int16)
        audio_array = audio_array.astype(np.float32) / 32768.0

        return audio_array

    async def shutdown(self) -> None:
        """Clean up resources."""
        self._initialized = False
        self._model = None
        logger.info("Transcription engine shut down")

    @property
    def is_initialized(self) -> bool:
        """Check if the engine is initialized."""
        return self._initialized
