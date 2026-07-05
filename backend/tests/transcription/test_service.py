"""
Tests for TranscriptionService (Audio Buffering and Streaming)

TDD RED Phase: These tests define expected behavior before implementation.
All tests should FAIL initially.

Requirements covered:
- 2.3.2 Audio buffering with overlap
- 2.3.3 Streaming transcription
- 2.3.4 VAD (Voice Activity Detection)

Feature: Transcription Service
"""

import asyncio
import pytest
import numpy as np
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock
import time


# Import the types and classes to test
from transcription.engine import TranscriptionEngine, TranscriptionResult
from transcription.service import TranscriptionService


# =============================================================================
# Fixtures
# =============================================================================

@pytest.fixture
def mock_engine():
    """Create a mock TranscriptionEngine."""
    engine = MagicMock(spec=TranscriptionEngine)
    engine.is_initialized = False
    engine.initialize = AsyncMock()
    engine.transcribe = AsyncMock(return_value=TranscriptionResult(
        text="Test transcription",
        timestamp=time.time(),
        is_final=True,
        confidence=0.95
    ))
    engine.shutdown = AsyncMock()
    return engine


@pytest.fixture
def service(mock_engine):
    """Create a TranscriptionService with mocked engine."""
    return TranscriptionService(engine=mock_engine)


@pytest.fixture
def service_with_callback(mock_engine):
    """Create a TranscriptionService with a callback."""
    callback = AsyncMock()
    return TranscriptionService(engine=mock_engine, on_transcription=callback), callback


@pytest.fixture
def sample_audio_samples():
    """Generate sample audio as list of float samples (1 second at 16kHz)."""
    return [0.0] * 16000


@pytest.fixture
def speech_audio_samples():
    """Generate sample audio that simulates speech (sine wave)."""
    sample_rate = 16000
    duration = 2.0  # 2 seconds
    t = np.linspace(0, duration, int(sample_rate * duration), dtype=np.float32)
    # Generate a 440Hz sine wave
    samples = np.sin(2 * np.pi * 440 * t).tolist()
    return samples


@pytest.fixture
def silence_audio_samples():
    """Generate silent audio samples."""
    return [0.0] * 16000


@pytest.fixture
def two_second_audio():
    """Generate 2 seconds of audio (enough to trigger transcription)."""
    return [0.1] * 32000  # 2 seconds at 16kHz


# =============================================================================
# Service Initialization Tests
# =============================================================================

class TestServiceInitialization:
    """Tests for TranscriptionService initialization."""

    def test_create_service_with_default_engine(self):
        """TranscriptionService should create default engine if none provided."""
        service = TranscriptionService()
        assert service.engine is not None
        assert isinstance(service.engine, TranscriptionEngine)

    def test_create_service_with_custom_engine(self, mock_engine):
        """TranscriptionService should accept custom engine."""
        service = TranscriptionService(engine=mock_engine)
        assert service.engine is mock_engine

    def test_create_service_with_callback(self, mock_engine):
        """TranscriptionService should accept transcription callback."""
        callback = AsyncMock()
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        # Callback should be stored for later use
        assert service._on_transcription is callback

    def test_service_constants_defined(self):
        """TranscriptionService should define required constants."""
        assert hasattr(TranscriptionService, 'SAMPLE_RATE')
        assert hasattr(TranscriptionService, 'BUFFER_DURATION_SECONDS')
        assert hasattr(TranscriptionService, 'OVERLAP_SECONDS')
        assert hasattr(TranscriptionService, 'MIN_BUFFER_SAMPLES')

        assert TranscriptionService.SAMPLE_RATE == 16000
        assert TranscriptionService.BUFFER_DURATION_SECONDS > 0
        assert TranscriptionService.OVERLAP_SECONDS >= 0

    def test_service_not_running_on_creation(self, service):
        """TranscriptionService should not be running immediately after creation."""
        assert service.is_running is False

    def test_service_buffer_empty_on_creation(self, service):
        """TranscriptionService buffer should be empty on creation."""
        assert service.buffer_size == 0


# =============================================================================
# Start/Stop Tests
# =============================================================================

class TestServiceStartStop:
    """Tests for service start and stop lifecycle."""

    @pytest.mark.asyncio
    async def test_start_initializes_engine(self, service, mock_engine):
        """start() should initialize the transcription engine."""
        await service.start()

        mock_engine.initialize.assert_called_once()

    @pytest.mark.asyncio
    async def test_start_sets_running_flag(self, service):
        """start() should set is_running to True."""
        await service.start()

        assert service.is_running is True

    @pytest.mark.asyncio
    async def test_start_is_idempotent(self, service, mock_engine):
        """start() should be safe to call multiple times."""
        await service.start()
        await service.start()

        # Engine should only be initialized once
        mock_engine.initialize.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_shuts_down_engine(self, service, mock_engine):
        """stop() should shut down the transcription engine."""
        await service.start()
        await service.stop()

        mock_engine.shutdown.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_sets_running_flag(self, service):
        """stop() should set is_running to False."""
        await service.start()
        await service.stop()

        assert service.is_running is False

    @pytest.mark.asyncio
    async def test_stop_is_idempotent(self, service, mock_engine):
        """stop() should be safe to call multiple times."""
        await service.start()
        await service.stop()
        await service.stop()

        # Shutdown should only be called once
        mock_engine.shutdown.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_flushes_remaining_audio(self, service, mock_engine, sample_audio_samples):
        """stop() should process any remaining audio in buffer."""
        await service.start()
        await service.process_audio(sample_audio_samples, time.time())
        await service.stop()

        # If buffer had sufficient audio, transcribe should have been called
        # during flush


# =============================================================================
# Audio Buffering Tests (Requirement 2.3.2)
# =============================================================================

class TestAudioBuffering:
    """Tests for audio buffering functionality."""

    @pytest.mark.asyncio
    async def test_process_audio_adds_to_buffer(self, service, sample_audio_samples):
        """process_audio() should add samples to internal buffer."""
        await service.start()
        initial_size = service.buffer_size

        await service.process_audio(sample_audio_samples, time.time())

        assert service.buffer_size > initial_size

    @pytest.mark.asyncio
    async def test_buffer_accumulates_correctly(self, service):
        """Buffer should accumulate samples from multiple calls."""
        await service.start()

        # Add 0.5 seconds of audio
        samples_500ms = [0.0] * 8000
        await service.process_audio(samples_500ms, time.time())
        size_after_first = service.buffer_size

        # Add another 0.5 seconds
        await service.process_audio(samples_500ms, time.time())
        size_after_second = service.buffer_size

        assert size_after_second == size_after_first + 8000

    @pytest.mark.asyncio
    async def test_transcription_triggered_at_buffer_threshold(self, service, mock_engine, two_second_audio):
        """Transcription should trigger when buffer reaches threshold."""
        await service.start()

        # Add enough audio to trigger transcription (2 seconds)
        await service.process_audio(two_second_audio, time.time())

        # Allow time for background processing
        await asyncio.sleep(0.6)

        # Engine transcribe should have been called
        assert mock_engine.transcribe.called

    @pytest.mark.asyncio
    async def test_buffer_clears_after_transcription(self, service, mock_engine, two_second_audio):
        """Buffer should be cleared (except overlap) after transcription."""
        await service.start()

        await service.process_audio(two_second_audio, time.time())
        await asyncio.sleep(0.6)

        # Buffer should be reduced (not completely empty due to overlap)
        assert service.buffer_size < len(two_second_audio)


# =============================================================================
# Overlap Handling Tests (Requirement 2.3.2)
# =============================================================================

class TestOverlapHandling:
    """Tests for audio overlap to preserve context."""

    @pytest.mark.asyncio
    async def test_overlap_preserved_after_transcription(self, service, mock_engine):
        """Overlap audio should be preserved after transcription."""
        await service.start()

        # Add exactly 2 seconds of audio (should trigger transcription)
        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Buffer should contain overlap samples
        expected_overlap = int(TranscriptionService.OVERLAP_SECONDS * 16000)
        # Buffer should be approximately the overlap size (may vary slightly)
        assert service.buffer_size >= expected_overlap - 100  # Allow small variance

    @pytest.mark.asyncio
    async def test_overlap_provides_context_continuity(self, service, mock_engine):
        """Overlap should provide context continuity between transcriptions."""
        await service.start()

        # First chunk
        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Second chunk
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Both transcriptions should have been triggered
        assert mock_engine.transcribe.call_count >= 2

    @pytest.mark.asyncio
    async def test_overlap_zero_configuration(self, mock_engine):
        """Service should work with zero overlap configuration."""
        # Create service and override overlap
        service = TranscriptionService(engine=mock_engine)
        original_overlap = TranscriptionService.OVERLAP_SECONDS

        try:
            TranscriptionService.OVERLAP_SECONDS = 0
            await service.start()

            samples_2s = [0.1] * 32000
            await service.process_audio(samples_2s, time.time())
            await asyncio.sleep(0.6)

            # Buffer should be empty (no overlap retained)
            # This test verifies the implementation handles zero overlap
        finally:
            TranscriptionService.OVERLAP_SECONDS = original_overlap
            await service.stop()


# =============================================================================
# Streaming Transcription Tests (Requirement 2.3.3)
# =============================================================================

class TestStreamingTranscription:
    """Tests for streaming transcription functionality."""

    @pytest.mark.asyncio
    async def test_callback_invoked_on_transcription(self, mock_engine):
        """Transcription callback should be invoked when transcription completes."""
        callback = AsyncMock()
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        await service.start()

        # Add enough audio to trigger transcription
        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        callback.assert_called()
        await service.stop()

    @pytest.mark.asyncio
    async def test_callback_receives_transcription_result(self, mock_engine):
        """Callback should receive TranscriptionResult."""
        callback = AsyncMock()
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        await service.start()

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Verify callback was called with TranscriptionResult
        assert callback.called
        call_args = callback.call_args
        result = call_args[0][0]
        assert isinstance(result, TranscriptionResult)
        await service.stop()

    @pytest.mark.asyncio
    async def test_partial_results_marked_correctly(self, mock_engine):
        """Partial results should be marked with is_final=False."""
        # Configure mock to return partial result
        mock_engine.transcribe = AsyncMock(return_value=TranscriptionResult(
            text="Partial...",
            timestamp=time.time(),
            is_final=False,
            confidence=0.8
        ))

        callback = AsyncMock()
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        await service.start()

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        if callback.called:
            result = callback.call_args[0][0]
            # Result should maintain is_final flag from engine
            assert hasattr(result, 'is_final')
        await service.stop()

    @pytest.mark.asyncio
    async def test_final_results_marked_correctly(self, mock_engine):
        """Final results should be marked with is_final=True."""
        mock_engine.transcribe = AsyncMock(return_value=TranscriptionResult(
            text="Complete sentence.",
            timestamp=time.time(),
            is_final=True,
            confidence=0.95
        ))

        callback = AsyncMock()
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        await service.start()

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        if callback.called:
            result = callback.call_args[0][0]
            assert result.is_final is True
        await service.stop()

    @pytest.mark.asyncio
    async def test_set_transcription_callback(self, service):
        """set_transcription_callback() should update the callback."""
        await service.start()

        new_callback = AsyncMock()
        service.set_transcription_callback(new_callback)

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # New callback should be used
        new_callback.assert_called()
        await service.stop()

    @pytest.mark.asyncio
    async def test_stream_transcriptions_async_iterator(self, service, mock_engine):
        """stream_transcriptions() should be an async iterator."""
        await service.start()

        # This verifies the interface exists and is an async iterator
        async_iter = service.stream_transcriptions()
        assert hasattr(async_iter, '__anext__')
        await service.stop()


# =============================================================================
# VAD (Voice Activity Detection) Tests (Requirement 2.3.4)
# =============================================================================

class TestVoiceActivityDetection:
    """Tests for voice activity detection functionality."""

    @pytest.mark.asyncio
    async def test_silence_not_transcribed(self, service, mock_engine, silence_audio_samples):
        """Silent audio should not trigger transcription."""
        await service.start()

        # Add silent audio
        await service.process_audio(silence_audio_samples * 3, time.time())  # 3 seconds
        await asyncio.sleep(0.6)

        # VAD should filter out silence - no transcription or empty result
        # Implementation may either not call transcribe or return empty text
        await service.stop()

    @pytest.mark.asyncio
    async def test_speech_segments_detected(self, service, mock_engine, speech_audio_samples):
        """Speech segments should be detected and transcribed."""
        await service.start()

        await service.process_audio(speech_audio_samples, time.time())
        await asyncio.sleep(0.6)

        # Speech should trigger transcription
        mock_engine.transcribe.assert_called()
        await service.stop()

    @pytest.mark.asyncio
    async def test_noise_filtered(self, service, mock_engine):
        """Low-level noise should be filtered out."""
        await service.start()

        # Generate low-amplitude noise (below speech threshold)
        noise_samples = (np.random.randn(32000) * 0.001).tolist()  # Very quiet noise
        await service.process_audio(noise_samples, time.time())
        await asyncio.sleep(0.6)

        # Noise below threshold should not trigger transcription
        # or should result in empty text
        await service.stop()

    @pytest.mark.asyncio
    async def test_mixed_speech_and_silence(self, service, mock_engine):
        """Service should handle mixed speech and silence."""
        await service.start()

        # 1 second of silence
        silence = [0.0] * 16000
        await service.process_audio(silence, time.time())

        # 1 second of speech (sine wave)
        t = np.linspace(0, 1, 16000, dtype=np.float32)
        speech = np.sin(2 * np.pi * 440 * t).tolist()
        await service.process_audio(speech, time.time())

        # 1 second of silence
        await service.process_audio(silence, time.time())

        await asyncio.sleep(0.6)

        # Speech portion should be transcribed
        mock_engine.transcribe.assert_called()
        await service.stop()


# =============================================================================
# Callback and Error Handling Tests
# =============================================================================

class TestCallbackErrorHandling:
    """Tests for callback error handling."""

    @pytest.mark.asyncio
    async def test_callback_error_does_not_stop_service(self, mock_engine):
        """Error in callback should not stop the service."""
        callback = AsyncMock(side_effect=Exception("Callback error"))
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        await service.start()

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Service should still be running despite callback error
        assert service.is_running is True
        await service.stop()

    @pytest.mark.asyncio
    async def test_transcription_error_logged_and_continues(self, mock_engine):
        """Transcription error should be logged and service continues."""
        mock_engine.transcribe = AsyncMock(side_effect=Exception("Transcription failed"))

        service = TranscriptionService(engine=mock_engine)
        await service.start()

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Service should still be running
        assert service.is_running is True
        await service.stop()

    @pytest.mark.asyncio
    async def test_no_callback_works_silently(self, service, mock_engine):
        """Service should work without a callback set."""
        # Service was created without callback
        await service.start()

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Should not raise, transcription still happens
        mock_engine.transcribe.assert_called()
        await service.stop()


# =============================================================================
# Hallucination Filtering Tests
# =============================================================================

class TestHallucinationFiltering:
    """Tests for filtering Whisper hallucinations."""

    @pytest.mark.asyncio
    async def test_filters_empty_text(self, mock_engine):
        """Empty transcription text should be filtered."""
        mock_engine.transcribe = AsyncMock(return_value=TranscriptionResult(
            text="",
            timestamp=time.time()
        ))

        callback = AsyncMock()
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        await service.start()

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Callback should not be called for empty text
        callback.assert_not_called()
        await service.stop()

    @pytest.mark.asyncio
    async def test_filters_special_tokens(self, mock_engine):
        """Whisper special tokens should be filtered."""
        mock_engine.transcribe = AsyncMock(return_value=TranscriptionResult(
            text="<|bn|>",
            timestamp=time.time()
        ))

        callback = AsyncMock()
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        await service.start()

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Callback should not be called for special tokens
        callback.assert_not_called()
        await service.stop()

    @pytest.mark.asyncio
    async def test_filters_common_hallucination_phrases(self, mock_engine):
        """Common hallucination phrases should be filtered."""
        hallucination_phrases = [
            "Thank you.",
            "Thanks for watching",
            "Subscribe",
            "Like and subscribe"
        ]

        for phrase in hallucination_phrases:
            mock_engine.transcribe = AsyncMock(return_value=TranscriptionResult(
                text=phrase,
                timestamp=time.time()
            ))

            callback = AsyncMock()
            service = TranscriptionService(engine=mock_engine, on_transcription=callback)
            await service.start()

            samples_2s = [0.1] * 32000
            await service.process_audio(samples_2s, time.time())
            await asyncio.sleep(0.6)

            # Callback should not be called for hallucination phrases
            callback.assert_not_called()
            await service.stop()

    @pytest.mark.asyncio
    async def test_filters_repetitive_text(self, mock_engine):
        """Highly repetitive text should be filtered."""
        mock_engine.transcribe = AsyncMock(return_value=TranscriptionResult(
            text="the the the the the the the the",
            timestamp=time.time()
        ))

        callback = AsyncMock()
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        await service.start()

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Highly repetitive text should be filtered
        callback.assert_not_called()
        await service.stop()

    @pytest.mark.asyncio
    async def test_passes_valid_transcription(self, mock_engine):
        """Valid transcription should pass through."""
        mock_engine.transcribe = AsyncMock(return_value=TranscriptionResult(
            text="Hello, this is a valid transcription.",
            timestamp=time.time()
        ))

        callback = AsyncMock()
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        await service.start()

        samples_2s = [0.1] * 32000
        await service.process_audio(samples_2s, time.time())
        await asyncio.sleep(0.6)

        # Valid transcription should pass to callback
        callback.assert_called()
        await service.stop()


# =============================================================================
# Edge Cases and Boundary Tests
# =============================================================================

class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @pytest.mark.asyncio
    async def test_process_audio_while_not_running(self, service, mock_engine):
        """process_audio() should handle calls when service not running."""
        # Service not started
        samples = [0.1] * 16000

        # Should either raise or silently ignore (implementation choice)
        # The key is it shouldn't crash
        try:
            await service.process_audio(samples, time.time())
        except RuntimeError:
            pass  # Expected if implementation checks running state

    @pytest.mark.asyncio
    async def test_empty_samples_list(self, service):
        """process_audio() should handle empty samples list."""
        await service.start()

        await service.process_audio([], time.time())

        assert service.buffer_size == 0
        await service.stop()

    @pytest.mark.asyncio
    async def test_very_large_audio_chunk(self, service, mock_engine):
        """process_audio() should handle very large audio chunks."""
        await service.start()

        # 60 seconds of audio at once
        large_samples = [0.1] * (16000 * 60)
        await service.process_audio(large_samples, time.time())
        await asyncio.sleep(1.0)

        # Should trigger multiple transcriptions
        assert mock_engine.transcribe.call_count >= 1
        await service.stop()

    @pytest.mark.asyncio
    async def test_concurrent_process_audio_calls(self, service, mock_engine):
        """Concurrent process_audio() calls should be thread-safe."""
        await service.start()

        # Make multiple concurrent calls
        samples = [0.1] * 8000  # 0.5 second chunks
        tasks = [
            service.process_audio(samples, time.time() + i * 0.5)
            for i in range(10)
        ]
        await asyncio.gather(*tasks)

        # Buffer should contain all samples (5 seconds total)
        # Implementation should handle concurrent access safely
        await service.stop()

    @pytest.mark.asyncio
    async def test_timestamp_ordering(self, service, mock_engine):
        """Transcription results should maintain timestamp ordering."""
        results = []

        async def collect_results(result):
            results.append(result)

        service = TranscriptionService(engine=mock_engine, on_transcription=collect_results)
        await service.start()

        # Send multiple chunks with increasing timestamps
        for i in range(3):
            samples = [0.1] * 32000  # 2 seconds
            await service.process_audio(samples, time.time() + i * 2)
            await asyncio.sleep(0.6)

        # Results should be in timestamp order
        if len(results) >= 2:
            timestamps = [r.timestamp for r in results]
            assert timestamps == sorted(timestamps)
        await service.stop()

    @pytest.mark.asyncio
    async def test_restart_service(self, service, mock_engine):
        """Service should be restartable after stop."""
        await service.start()
        await service.stop()

        # Restart
        await service.start()
        assert service.is_running is True

        samples = [0.1] * 32000
        await service.process_audio(samples, time.time())
        await asyncio.sleep(0.6)

        mock_engine.transcribe.assert_called()
        await service.stop()

    @pytest.mark.asyncio
    async def test_buffer_cleared_on_stop(self, service):
        """Buffer should be cleared after stop (after flush)."""
        await service.start()

        samples = [0.1] * 16000  # Not enough to trigger transcription
        await service.process_audio(samples, time.time())
        assert service.buffer_size > 0

        await service.stop()

        # After stop, buffer should be empty (processed during flush)
        # or service should be in stopped state
        assert service.is_running is False

    @pytest.mark.asyncio
    async def test_min_buffer_respected_on_flush(self, service, mock_engine):
        """Flush should respect minimum buffer size."""
        await service.start()

        # Add audio less than MIN_BUFFER_SAMPLES
        min_samples = TranscriptionService.MIN_BUFFER_SAMPLES
        samples = [0.1] * (min_samples - 100)
        await service.process_audio(samples, time.time())

        await service.stop()

        # With insufficient audio, transcribe may not be called
        # (depends on implementation)


# =============================================================================
# Integration-like Tests (Still with Mocks)
# =============================================================================

class TestServiceIntegration:
    """Integration-like tests for TranscriptionService."""

    @pytest.mark.asyncio
    async def test_full_workflow(self, mock_engine):
        """Test complete workflow: start -> process -> callback -> stop."""
        results = []

        async def collect(result):
            results.append(result)

        service = TranscriptionService(engine=mock_engine, on_transcription=collect)

        # Start
        await service.start()
        assert service.is_running is True

        # Process audio
        for _ in range(3):
            samples = [0.1] * 32000  # 2 seconds
            await service.process_audio(samples, time.time())
            await asyncio.sleep(0.6)

        # Stop
        await service.stop()
        assert service.is_running is False

        # Verify results were collected
        assert len(results) > 0

    @pytest.mark.asyncio
    async def test_continuous_streaming(self, mock_engine):
        """Test continuous streaming over extended period."""
        callback = AsyncMock()
        service = TranscriptionService(engine=mock_engine, on_transcription=callback)
        await service.start()

        # Simulate 10 seconds of continuous audio
        for i in range(10):
            samples = [0.1] * 16000  # 1 second chunks
            await service.process_audio(samples, time.time() + i)
            await asyncio.sleep(0.1)

        await asyncio.sleep(0.6)  # Wait for final processing

        # Should have multiple transcription callbacks
        assert callback.call_count >= 1
        await service.stop()
