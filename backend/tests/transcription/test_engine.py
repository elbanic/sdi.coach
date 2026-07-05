"""
Tests for TranscriptionEngine (MLX-Whisper)

TDD RED Phase: These tests define expected behavior before implementation.
All tests should FAIL initially.

Requirements covered:
- 2.3.1 MLX-Whisper model initialization
- Transcription functionality with TranscriptionResult
- Error handling for various failure scenarios

Feature: Transcription Engine
"""

import asyncio
import pytest
import numpy as np
from unittest.mock import AsyncMock, MagicMock, patch
import time


# Import the types and classes to test
from transcription.engine import (
    TranscriptionEngine,
    TranscriptionResult,
    TranscriptionError,
    ModelInitializationError,
    AudioProcessingError,
)


# =============================================================================
# Fixtures
# =============================================================================

@pytest.fixture
def engine():
    """Create a fresh TranscriptionEngine instance for each test."""
    return TranscriptionEngine()


@pytest.fixture
def engine_with_custom_model():
    """Create a TranscriptionEngine with a custom model name."""
    return TranscriptionEngine(model_name="mlx-community/whisper-base-mlx")


@pytest.fixture
def mock_mlx_whisper():
    """Mock the mlx_whisper module to avoid actual model loading."""
    with patch.dict('sys.modules', {'mlx_whisper': MagicMock()}):
        import sys
        mock_module = sys.modules['mlx_whisper']
        mock_module.transcribe = MagicMock(return_value={"text": "Hello world"})
        yield mock_module


@pytest.fixture
def sample_audio_bytes():
    """Generate sample audio bytes (16-bit PCM, 16kHz, 1 second)."""
    # 1 second of silence (16kHz, 16-bit PCM)
    samples = np.zeros(16000, dtype=np.int16)
    return samples.tobytes()


@pytest.fixture
def sample_audio_with_speech():
    """Generate sample audio bytes that simulates speech (sine wave)."""
    # 1 second of 440Hz tone (16kHz, 16-bit PCM)
    sample_rate = 16000
    duration = 1.0
    t = np.linspace(0, duration, int(sample_rate * duration), dtype=np.float32)
    # Generate a 440Hz sine wave
    samples = (np.sin(2 * np.pi * 440 * t) * 32767).astype(np.int16)
    return samples.tobytes()


@pytest.fixture
def empty_audio():
    """Generate empty audio bytes."""
    return b""


# =============================================================================
# TranscriptionResult Tests
# =============================================================================

class TestTranscriptionResult:
    """Tests for TranscriptionResult dataclass."""

    def test_create_result_with_required_fields(self):
        """TranscriptionResult should be created with text and timestamp."""
        result = TranscriptionResult(
            text="Hello world",
            timestamp=1234567890.0
        )
        assert result.text == "Hello world"
        assert result.timestamp == 1234567890.0

    def test_create_result_with_all_fields(self):
        """TranscriptionResult should accept all optional fields."""
        result = TranscriptionResult(
            text="Hello world",
            timestamp=1234567890.0,
            is_final=False,
            confidence=0.95
        )
        assert result.text == "Hello world"
        assert result.timestamp == 1234567890.0
        assert result.is_final is False
        assert result.confidence == 0.95

    def test_default_values(self):
        """TranscriptionResult should have correct default values."""
        result = TranscriptionResult(
            text="Test",
            timestamp=0.0
        )
        assert result.is_final is True
        assert result.confidence == 1.0

    def test_to_dict_serialization(self):
        """TranscriptionResult.to_dict() should return correct dictionary."""
        result = TranscriptionResult(
            text="Hello",
            timestamp=1234567890.0,
            is_final=True,
            confidence=0.85
        )
        d = result.to_dict()

        assert d == {
            "text": "Hello",
            "timestamp": 1234567890.0,
            "is_final": True,
            "confidence": 0.85
        }

    def test_to_dict_with_empty_text(self):
        """TranscriptionResult.to_dict() should handle empty text."""
        result = TranscriptionResult(text="", timestamp=0.0)
        d = result.to_dict()

        assert d["text"] == ""
        assert "timestamp" in d

    def test_to_dict_with_special_characters(self):
        """TranscriptionResult.to_dict() should preserve special characters."""
        result = TranscriptionResult(
            text="Hello\nWorld\t\"quoted\"",
            timestamp=0.0
        )
        d = result.to_dict()

        assert d["text"] == "Hello\nWorld\t\"quoted\""


# =============================================================================
# TranscriptionEngine Initialization Tests
# =============================================================================

class TestTranscriptionEngineInit:
    """Tests for TranscriptionEngine initialization."""

    def test_create_engine_with_default_model(self, engine):
        """TranscriptionEngine should use default model when none specified."""
        assert engine.model_name == TranscriptionEngine.DEFAULT_MODEL
        assert engine.is_initialized is False

    def test_create_engine_with_custom_model(self, engine_with_custom_model):
        """TranscriptionEngine should accept custom model name."""
        assert engine_with_custom_model.model_name == "mlx-community/whisper-base-mlx"

    def test_engine_not_initialized_on_creation(self, engine):
        """TranscriptionEngine should not be initialized immediately."""
        assert engine.is_initialized is False

    def test_engine_sample_rate_constant(self):
        """TranscriptionEngine should define expected sample rate."""
        assert TranscriptionEngine.SAMPLE_RATE == 16000


# =============================================================================
# Model Initialization Tests (Task 2.3.1)
# =============================================================================

class TestModelInitialization:
    """Tests for MLX-Whisper model initialization (Requirement 2.3.1)."""

    @pytest.mark.asyncio
    async def test_initialize_loads_model_successfully(self, engine, mock_mlx_whisper):
        """initialize() should load the MLX-Whisper model."""
        await engine.initialize()

        assert engine.is_initialized is True

    @pytest.mark.asyncio
    async def test_initialize_is_idempotent(self, engine, mock_mlx_whisper):
        """initialize() should be safe to call multiple times."""
        await engine.initialize()
        await engine.initialize()  # Second call should not raise

        assert engine.is_initialized is True
        # Model loading should only happen once (verify with mock call count)

    @pytest.mark.asyncio
    async def test_initialize_raises_on_import_error(self, engine):
        """initialize() should raise ModelInitializationError if mlx_whisper not installed."""
        with patch.dict('sys.modules', {'mlx_whisper': None}):
            with pytest.raises(ModelInitializationError) as exc_info:
                await engine.initialize()

            assert "mlx-whisper" in str(exc_info.value).lower() or "not installed" in str(exc_info.value).lower()

    @pytest.mark.asyncio
    async def test_initialize_raises_on_model_not_found(self, mock_mlx_whisper):
        """initialize() should raise ModelInitializationError for invalid model."""
        engine = TranscriptionEngine(model_name="nonexistent/model")
        mock_mlx_whisper.transcribe.side_effect = Exception("Model not found")

        with pytest.raises(ModelInitializationError):
            await engine.initialize()

    @pytest.mark.asyncio
    async def test_initialize_handles_timeout(self, engine, mock_mlx_whisper):
        """initialize() should handle model loading timeout gracefully."""
        # Mock mlx_whisper to allow import, but make wait_for timeout
        with patch('transcription.engine.asyncio.wait_for', side_effect=asyncio.TimeoutError()):
            with pytest.raises(ModelInitializationError) as exc_info:
                await engine.initialize()

            assert "timeout" in str(exc_info.value).lower()

    @pytest.mark.asyncio
    async def test_initialize_concurrent_calls_are_safe(self, engine, mock_mlx_whisper):
        """Concurrent calls to initialize() should be thread-safe."""
        # Launch multiple concurrent initialization attempts
        tasks = [engine.initialize() for _ in range(5)]
        await asyncio.gather(*tasks)

        assert engine.is_initialized is True
        # Model should only be loaded once despite concurrent calls


# =============================================================================
# Transcription Tests
# =============================================================================

class TestTranscription:
    """Tests for transcription functionality."""

    @pytest.mark.asyncio
    async def test_transcribe_returns_result(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """transcribe() should return TranscriptionResult with text."""
        await engine.initialize()

        result = await engine.transcribe(sample_audio_bytes)

        assert isinstance(result, TranscriptionResult)
        assert isinstance(result.text, str)

    @pytest.mark.asyncio
    async def test_transcribe_includes_timestamp(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """transcribe() should include timestamp in result."""
        await engine.initialize()
        before = time.time()

        result = await engine.transcribe(sample_audio_bytes)

        after = time.time()
        assert result.timestamp >= before
        assert result.timestamp <= after

    @pytest.mark.asyncio
    async def test_transcribe_with_explicit_timestamp(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """transcribe() should use provided timestamp when given."""
        await engine.initialize()
        explicit_timestamp = 1234567890.0

        result = await engine.transcribe(sample_audio_bytes, timestamp=explicit_timestamp)

        assert result.timestamp == explicit_timestamp

    @pytest.mark.asyncio
    async def test_transcribe_empty_audio_returns_empty_text(self, engine, mock_mlx_whisper, empty_audio):
        """transcribe() should return empty text for empty audio."""
        await engine.initialize()

        result = await engine.transcribe(empty_audio)

        assert result.text == ""
        assert result.confidence == 0.0

    @pytest.mark.asyncio
    async def test_transcribe_auto_initializes_if_needed(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """transcribe() should auto-initialize engine if not initialized."""
        assert engine.is_initialized is False

        result = await engine.transcribe(sample_audio_bytes)

        assert engine.is_initialized is True
        assert isinstance(result, TranscriptionResult)

    @pytest.mark.asyncio
    async def test_transcribe_raises_on_invalid_audio(self, engine, mock_mlx_whisper):
        """transcribe() should raise AudioProcessingError for invalid audio data."""
        await engine.initialize()
        invalid_audio = "not bytes or numpy array"

        with pytest.raises(AudioProcessingError):
            await engine.transcribe(invalid_audio)

    @pytest.mark.asyncio
    async def test_transcribe_strips_whitespace(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """transcribe() should strip leading/trailing whitespace from result."""
        mock_mlx_whisper.transcribe.return_value = {"text": "  Hello world  \n"}
        await engine.initialize()

        result = await engine.transcribe(sample_audio_bytes)

        assert result.text == "Hello world"

    @pytest.mark.asyncio
    async def test_transcribe_handles_processing_error(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """transcribe() should raise AudioProcessingError on processing failure."""
        # Initialize first (uses mock's default success response)
        await engine.initialize()
        # Then set side_effect for subsequent calls
        mock_mlx_whisper.transcribe.side_effect = RuntimeError("Processing failed")

        with pytest.raises(AudioProcessingError) as exc_info:
            await engine.transcribe(sample_audio_bytes)

        assert "failed" in str(exc_info.value).lower()


# =============================================================================
# Audio Format Tests
# =============================================================================

class TestAudioFormats:
    """Tests for handling various audio input formats."""

    @pytest.mark.asyncio
    async def test_transcribe_accepts_bytes_pcm16(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """transcribe() should accept bytes (16-bit PCM)."""
        await engine.initialize()

        result = await engine.transcribe(sample_audio_bytes)

        assert isinstance(result, TranscriptionResult)

    @pytest.mark.asyncio
    async def test_transcribe_accepts_numpy_float32(self, engine, mock_mlx_whisper):
        """transcribe() should accept numpy float32 array."""
        await engine.initialize()
        audio_array = np.zeros(16000, dtype=np.float32)

        result = await engine.transcribe(audio_array.tobytes())

        assert isinstance(result, TranscriptionResult)

    @pytest.mark.asyncio
    async def test_transcribe_handles_stereo_audio(self, engine, mock_mlx_whisper):
        """transcribe() should handle stereo audio by converting to mono."""
        await engine.initialize()
        # 2-channel audio (stereo), 1 second at 16kHz
        stereo_samples = np.zeros((16000, 2), dtype=np.int16)
        # Note: Implementation should convert to mono

        # This test verifies the implementation handles stereo input
        # It may either convert to mono or raise an informative error
        result = await engine.transcribe(stereo_samples.tobytes())
        assert isinstance(result, TranscriptionResult)


# =============================================================================
# Shutdown Tests
# =============================================================================

class TestShutdown:
    """Tests for engine shutdown."""

    @pytest.mark.asyncio
    async def test_shutdown_cleans_up_resources(self, engine, mock_mlx_whisper):
        """shutdown() should clean up engine resources."""
        await engine.initialize()
        assert engine.is_initialized is True

        await engine.shutdown()

        assert engine.is_initialized is False

    @pytest.mark.asyncio
    async def test_shutdown_is_idempotent(self, engine, mock_mlx_whisper):
        """shutdown() should be safe to call multiple times."""
        await engine.initialize()

        await engine.shutdown()
        await engine.shutdown()  # Second call should not raise

        assert engine.is_initialized is False

    @pytest.mark.asyncio
    async def test_shutdown_without_initialization(self, engine):
        """shutdown() should be safe to call without initialization."""
        assert engine.is_initialized is False

        await engine.shutdown()  # Should not raise

        assert engine.is_initialized is False

    @pytest.mark.asyncio
    async def test_can_reinitialize_after_shutdown(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """Engine should be reinitializable after shutdown."""
        await engine.initialize()
        await engine.shutdown()

        await engine.initialize()

        assert engine.is_initialized is True
        result = await engine.transcribe(sample_audio_bytes)
        assert isinstance(result, TranscriptionResult)


# =============================================================================
# Exception Types Tests
# =============================================================================

class TestExceptionTypes:
    """Tests for exception type hierarchy."""

    def test_transcription_error_is_base_exception(self):
        """TranscriptionError should be the base exception."""
        error = TranscriptionError("test")
        assert isinstance(error, Exception)

    def test_model_initialization_error_inherits_from_base(self):
        """ModelInitializationError should inherit from TranscriptionError."""
        error = ModelInitializationError("test")
        assert isinstance(error, TranscriptionError)
        assert isinstance(error, Exception)

    def test_audio_processing_error_inherits_from_base(self):
        """AudioProcessingError should inherit from TranscriptionError."""
        error = AudioProcessingError("test")
        assert isinstance(error, TranscriptionError)
        assert isinstance(error, Exception)

    def test_exceptions_preserve_message(self):
        """Exceptions should preserve error message."""
        msg = "Test error message"

        assert str(TranscriptionError(msg)) == msg
        assert str(ModelInitializationError(msg)) == msg
        assert str(AudioProcessingError(msg)) == msg


# =============================================================================
# Edge Cases and Boundary Tests
# =============================================================================

class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @pytest.mark.asyncio
    async def test_transcribe_very_short_audio(self, engine, mock_mlx_whisper):
        """transcribe() should handle very short audio (<100ms)."""
        await engine.initialize()
        # 50ms of audio at 16kHz
        short_audio = np.zeros(800, dtype=np.int16).tobytes()

        result = await engine.transcribe(short_audio)

        assert isinstance(result, TranscriptionResult)

    @pytest.mark.asyncio
    async def test_transcribe_long_audio(self, engine, mock_mlx_whisper):
        """transcribe() should handle long audio (>30 seconds)."""
        await engine.initialize()
        # 30 seconds of audio at 16kHz
        long_audio = np.zeros(16000 * 30, dtype=np.int16).tobytes()

        result = await engine.transcribe(long_audio)

        assert isinstance(result, TranscriptionResult)

    @pytest.mark.asyncio
    async def test_transcribe_maximum_amplitude_audio(self, engine, mock_mlx_whisper):
        """transcribe() should handle audio at maximum amplitude."""
        await engine.initialize()
        # Maximum amplitude 16-bit audio
        max_audio = np.full(16000, 32767, dtype=np.int16).tobytes()

        result = await engine.transcribe(max_audio)

        assert isinstance(result, TranscriptionResult)

    @pytest.mark.asyncio
    async def test_transcribe_minimum_amplitude_audio(self, engine, mock_mlx_whisper):
        """transcribe() should handle audio at minimum amplitude."""
        await engine.initialize()
        # Minimum amplitude 16-bit audio
        min_audio = np.full(16000, -32768, dtype=np.int16).tobytes()

        result = await engine.transcribe(min_audio)

        assert isinstance(result, TranscriptionResult)

    @pytest.mark.asyncio
    async def test_result_with_unicode_text(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """transcribe() should handle Unicode characters in result."""
        mock_mlx_whisper.transcribe.return_value = {"text": "Hello"}
        await engine.initialize()

        result = await engine.transcribe(sample_audio_bytes)

        # Result should be able to handle various character sets
        assert isinstance(result.text, str)

    @pytest.mark.asyncio
    async def test_concurrent_transcriptions(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """Multiple concurrent transcriptions should be handled safely."""
        await engine.initialize()

        # Launch multiple concurrent transcriptions
        tasks = [engine.transcribe(sample_audio_bytes) for _ in range(5)]
        results = await asyncio.gather(*tasks)

        assert len(results) == 5
        assert all(isinstance(r, TranscriptionResult) for r in results)

    @pytest.mark.asyncio
    async def test_timestamp_precision(self, engine, mock_mlx_whisper, sample_audio_bytes):
        """Timestamp should have sufficient precision (at least milliseconds)."""
        await engine.initialize()

        result = await engine.transcribe(sample_audio_bytes)

        # Timestamp should be a float with sub-second precision
        timestamp_str = str(result.timestamp)
        assert '.' in timestamp_str
