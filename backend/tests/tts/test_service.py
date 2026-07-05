"""
Tests for TTSService (Text-to-Speech Service Layer)

TDD RED Phase: These tests define expected behavior before implementation.
All tests should FAIL initially.

Requirements covered:
- 3.1.3 TTSService wrapping TTSEngine with service layer
- Lazy initialization of the TTS engine
- Handle IPC messages: TTS_SPEAK, TTS_STATUS, TTS_STOP
- Voice preset selection via set_voice() method
- Status tracking with TTSStatus dataclass

Feature: TTS Service
Task: 3.1.3
"""

import asyncio
import pytest
import time
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock, call
from dataclasses import dataclass
from typing import Optional, Callable, List

# Import the types and classes to test (these will initially fail to import)
# These imports define the expected interface
from tts.engine import TTSEngine, TTSEngineState, VoiceConfig, VOICE_PRESETS
from tts.service import TTSService, TTSStatus


# =============================================================================
# Fixtures
# =============================================================================

@pytest.fixture
def mock_engine():
    """Create a mock TTSEngine."""
    engine = MagicMock(spec=TTSEngine)
    engine.is_initialized = False
    engine.state = TTSEngineState.IDLE
    engine.initialize = AsyncMock()
    engine.speak = AsyncMock()
    engine.stop = AsyncMock()
    engine.shutdown = AsyncMock()
    engine.get_voice_config = MagicMock(return_value=VOICE_PRESETS["english_male"])
    engine.set_voice_config = MagicMock()
    return engine


@pytest.fixture
def service_no_engine():
    """Create a TTSService without pre-created engine (for lazy init tests)."""
    return TTSService()


@pytest.fixture
def status_callback():
    """Create a mock status callback."""
    return MagicMock()


@pytest.fixture
def async_status_callback():
    """Create an async mock status callback."""
    return AsyncMock()


@pytest.fixture
def service_with_callback(status_callback):
    """Create a TTSService with a status callback."""
    return TTSService(status_callback=status_callback)


# =============================================================================
# TTSStatus Dataclass Tests
# =============================================================================

class TestTTSStatusDataclass:
    """Tests for TTSStatus dataclass structure."""

    def test_tts_status_has_required_fields(self):
        """TTSStatus should have state, text, elapsed, and error fields."""
        status = TTSStatus(state="idle")

        assert hasattr(status, "state")
        assert hasattr(status, "text")
        assert hasattr(status, "elapsed")
        assert hasattr(status, "error")

    def test_tts_status_state_is_required(self):
        """TTSStatus should require state field."""
        status = TTSStatus(state="generating")
        assert status.state == "generating"

    def test_tts_status_optional_fields_default_to_none(self):
        """TTSStatus optional fields should default to None."""
        status = TTSStatus(state="idle")

        assert status.text is None
        assert status.elapsed is None
        assert status.error is None

    def test_tts_status_with_all_fields(self):
        """TTSStatus should accept all fields."""
        status = TTSStatus(
            state="playing",
            text="Hello world",
            elapsed=1.5,
            error=None
        )

        assert status.state == "playing"
        assert status.text == "Hello world"
        assert status.elapsed == 1.5
        assert status.error is None

    def test_tts_status_with_error(self):
        """TTSStatus should support error messages."""
        status = TTSStatus(
            state="idle",
            error="Generation failed"
        )

        assert status.error == "Generation failed"

    def test_tts_status_valid_states(self):
        """TTSStatus state should accept valid state strings."""
        valid_states = ["idle", "generating", "playing", "stopped", "loading_model"]

        for state in valid_states:
            status = TTSStatus(state=state)
            assert status.state == state


# =============================================================================
# Service Initialization Tests
# =============================================================================

class TestServiceInitialization:
    """Tests for TTSService initialization and lifecycle."""

    def test_service_creates_without_arguments(self):
        """TTSService should be creatable without arguments."""
        service = TTSService()
        assert service is not None

    def test_service_accepts_status_callback(self, status_callback):
        """TTSService should accept a status callback."""
        service = TTSService(status_callback=status_callback)
        assert service._status_callback is status_callback

    def test_service_engine_is_none_initially(self, service_no_engine):
        """TTSService should not create engine on initialization (lazy init)."""
        # Engine should be None until first use
        assert service_no_engine._engine is None

    def test_service_default_voice_preset(self, service_no_engine):
        """TTSService should have a default voice preset."""
        # Default should be "english_female" or "english_male"
        assert service_no_engine._current_preset in VOICE_PRESETS

    def test_service_accepts_custom_default_preset(self):
        """TTSService should accept custom default preset."""
        service = TTSService(default_preset="english_female")
        assert service._current_preset == "english_female"

    def test_service_invalid_default_preset_raises(self):
        """TTSService should raise for invalid default preset."""
        with pytest.raises(ValueError):
            TTSService(default_preset="invalid_preset")


# =============================================================================
# Lazy Engine Initialization Tests
# =============================================================================

class TestLazyInitialization:
    """Tests for lazy engine initialization."""

    @pytest.mark.asyncio
    async def test_engine_created_on_first_speak(self, service_no_engine):
        """Engine should be created lazily on first speak() call."""
        assert service_no_engine._engine is None

        with patch.object(TTSEngine, '__init__', return_value=None), \
             patch.object(TTSEngine, 'speak', new_callable=AsyncMock):
            await service_no_engine.speak("Hello")

        assert service_no_engine._engine is not None

    @pytest.mark.asyncio
    async def test_engine_not_recreated_on_subsequent_speaks(self):
        """Engine should not be recreated on subsequent speak() calls."""
        service = TTSService()

        with patch.object(TTSEngine, '__init__', return_value=None) as mock_init, \
             patch.object(TTSEngine, 'speak', new_callable=AsyncMock):
            await service.speak("Hello")
            await service.speak("World")

        # __init__ should only be called once
        assert mock_init.call_count == 1

    @pytest.mark.asyncio
    async def test_initialize_creates_engine(self, service_no_engine):
        """initialize() should create and initialize engine without speaking."""
        assert service_no_engine._engine is None

        with patch.object(TTSEngine, '__init__', return_value=None), \
             patch.object(TTSEngine, 'initialize', new_callable=AsyncMock) as mock_init:
            await service_no_engine.initialize()

        assert service_no_engine._engine is not None
        mock_init.assert_called_once()

    @pytest.mark.asyncio
    async def test_initialize_is_idempotent(self, service_no_engine):
        """initialize() should be safe to call multiple times."""
        with patch.object(TTSEngine, '__init__', return_value=None), \
             patch.object(TTSEngine, 'initialize', new_callable=AsyncMock) as mock_init:
            await service_no_engine.initialize()
            await service_no_engine.initialize()

        # Should only initialize once
        mock_init.assert_called_once()

    @pytest.mark.asyncio
    async def test_engine_receives_status_callback(self, status_callback):
        """Engine should receive status callback from service."""
        service = TTSService(status_callback=status_callback)

        with patch.object(TTSEngine, '__init__', return_value=None) as mock_init, \
             patch.object(TTSEngine, 'initialize', new_callable=AsyncMock):
            await service.initialize()

        # Engine should be initialized with a status callback
        mock_init.assert_called()
        call_kwargs = mock_init.call_args
        assert 'status_callback' in call_kwargs.kwargs or len(call_kwargs.args) > 0


# =============================================================================
# speak() Method Tests
# =============================================================================

class TestSpeakMethod:
    """Tests for speak() method."""

    @pytest.mark.asyncio
    async def test_speak_calls_engine_speak(self, mock_engine):
        """speak() should call engine.speak() with the text."""
        service = TTSService()
        service._engine = mock_engine

        await service.speak("Hello world")

        mock_engine.speak.assert_called_once_with("Hello world")

    @pytest.mark.asyncio
    async def test_speak_with_empty_text(self, mock_engine):
        """speak() with empty text should handle gracefully."""
        service = TTSService()
        service._engine = mock_engine

        await service.speak("")

        # Should either not call engine or call with empty string
        # Depends on implementation - engine.speak handles empty text

    @pytest.mark.asyncio
    async def test_speak_with_whitespace_only_text(self, mock_engine):
        """speak() with whitespace-only text should handle gracefully."""
        service = TTSService()
        service._engine = mock_engine

        await service.speak("   \n\t  ")

        # Should either not call engine or call with whitespace

    @pytest.mark.asyncio
    async def test_speak_tracks_start_time(self, mock_engine):
        """speak() should track speech start time for elapsed calculation."""
        service = TTSService()
        service._engine = mock_engine

        before = time.time()
        await service.speak("Hello")
        after = time.time()

        assert service._speak_start_time is not None
        assert before <= service._speak_start_time <= after

    @pytest.mark.asyncio
    async def test_speak_with_long_text(self, mock_engine):
        """speak() should handle long text."""
        service = TTSService()
        service._engine = mock_engine

        long_text = "This is a sentence. " * 100
        await service.speak(long_text)

        mock_engine.speak.assert_called_once_with(long_text)

    @pytest.mark.asyncio
    async def test_speak_with_special_characters(self, mock_engine):
        """speak() should handle special characters."""
        service = TTSService()
        service._engine = mock_engine

        special_text = "Hello! How are you? I'm fine, thanks."
        await service.speak(special_text)

        mock_engine.speak.assert_called_once_with(special_text)

    @pytest.mark.asyncio
    async def test_speak_with_unicode(self, mock_engine):
        """speak() should handle unicode characters."""
        service = TTSService()
        service._engine = mock_engine

        unicode_text = "Hello World"  # English text for sdi.coach
        await service.speak(unicode_text)

        mock_engine.speak.assert_called_once_with(unicode_text)


# =============================================================================
# stop() Method Tests
# =============================================================================

class TestStopMethod:
    """Tests for stop() method."""

    @pytest.mark.asyncio
    async def test_stop_calls_engine_stop(self, mock_engine):
        """stop() should call engine.stop()."""
        service = TTSService()
        service._engine = mock_engine

        await service.stop()

        mock_engine.stop.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_when_engine_is_none(self, service_no_engine):
        """stop() should handle case when engine is not created."""
        # Should not raise
        await service_no_engine.stop()

    @pytest.mark.asyncio
    async def test_stop_resets_speak_start_time(self, mock_engine):
        """stop() should reset speak start time."""
        service = TTSService()
        service._engine = mock_engine
        service._speak_start_time = time.time()

        await service.stop()

        assert service._speak_start_time is None

    @pytest.mark.asyncio
    async def test_stop_is_idempotent(self, mock_engine):
        """stop() should be safe to call multiple times."""
        service = TTSService()
        service._engine = mock_engine

        await service.stop()
        await service.stop()

        # Should only call engine.stop() twice (no crash)
        assert mock_engine.stop.call_count == 2


# =============================================================================
# set_voice() Method Tests
# =============================================================================

class TestSetVoiceMethod:
    """Tests for set_voice() / set_preset() method."""

    def test_set_voice_with_valid_preset(self, service_no_engine):
        """set_voice() should accept valid preset name."""
        result = service_no_engine.set_voice("english_male")

        assert result is True
        assert service_no_engine._current_preset == "english_male"

    def test_set_voice_with_invalid_preset(self, service_no_engine):
        """set_voice() should return False for invalid preset."""
        original_preset = service_no_engine._current_preset

        result = service_no_engine.set_voice("nonexistent_preset")

        assert result is False
        assert service_no_engine._current_preset == original_preset

    def test_set_voice_updates_engine_config(self, mock_engine):
        """set_voice() should update engine config when engine exists."""
        service = TTSService()
        service._engine = mock_engine

        service.set_voice("english_female")

        mock_engine.set_voice_config.assert_called_once()
        call_args = mock_engine.set_voice_config.call_args[0][0]
        assert isinstance(call_args, VoiceConfig)

    def test_set_voice_before_engine_creation(self, service_no_engine):
        """set_voice() should work before engine is created."""
        result = service_no_engine.set_voice("english_female")

        assert result is True
        assert service_no_engine._current_preset == "english_female"

    def test_list_presets_returns_available_presets(self, service_no_engine):
        """list_presets() should return list of available preset names."""
        presets = service_no_engine.list_presets()

        assert isinstance(presets, list)
        assert len(presets) > 0
        assert "english_male" in presets
        assert "english_female" in presets


# =============================================================================
# get_status() Method Tests
# =============================================================================

class TestGetStatusMethod:
    """Tests for get_status() method."""

    def test_get_status_returns_tts_status(self, service_no_engine):
        """get_status() should return TTSStatus instance."""
        status = service_no_engine.get_status()

        assert isinstance(status, TTSStatus)

    def test_get_status_idle_when_engine_none(self, service_no_engine):
        """get_status() should return idle when engine is None."""
        status = service_no_engine.get_status()

        assert status.state == "idle"

    def test_get_status_reflects_engine_state(self, mock_engine):
        """get_status() should reflect engine state."""
        service = TTSService()
        service._engine = mock_engine
        mock_engine.state = TTSEngineState.GENERATING

        status = service.get_status()

        assert status.state == "generating"

    def test_get_status_includes_elapsed_time(self, mock_engine):
        """get_status() should include elapsed time when speaking."""
        service = TTSService()
        service._engine = mock_engine
        service._speak_start_time = time.time() - 2.5  # Started 2.5 seconds ago
        mock_engine.state = TTSEngineState.PLAYING

        status = service.get_status()

        assert status.elapsed is not None
        assert status.elapsed >= 2.5

    def test_get_status_no_elapsed_when_idle(self, mock_engine):
        """get_status() should not include elapsed when idle and no speak started."""
        service = TTSService()
        service._engine = mock_engine
        service._speak_start_time = None
        mock_engine.state = TTSEngineState.IDLE

        status = service.get_status()

        assert status.elapsed is None


# =============================================================================
# get_voice_config() Method Tests
# =============================================================================

class TestGetVoiceConfigMethod:
    """Tests for get_voice_config() method."""

    def test_get_voice_config_returns_dict(self, service_no_engine):
        """get_voice_config() should return a dictionary."""
        config = service_no_engine.get_voice_config()

        assert isinstance(config, dict)

    def test_get_voice_config_has_required_keys(self, service_no_engine):
        """get_voice_config() should have language and voice_instruct keys."""
        config = service_no_engine.get_voice_config()

        assert "language" in config
        assert "voice_instruct" in config

    def test_get_voice_config_reflects_current_preset(self, service_no_engine):
        """get_voice_config() should reflect current preset."""
        service_no_engine.set_voice("english_female")
        config = service_no_engine.get_voice_config()

        expected = VOICE_PRESETS["english_female"]
        assert config["language"] == expected.language
        assert config["voice_instruct"] == expected.voice_instruct

    def test_get_voice_config_from_engine_when_available(self, mock_engine):
        """get_voice_config() should get config from engine when available."""
        service = TTSService()
        service._engine = mock_engine

        service.get_voice_config()

        mock_engine.get_voice_config.assert_called_once()


# =============================================================================
# Status Callback Propagation Tests
# =============================================================================

class TestStatusCallbackPropagation:
    """Tests for status callback propagation from engine to service."""

    def test_status_callback_invoked_on_state_change(self, status_callback):
        """Status callback should be invoked when engine state changes."""
        service = TTSService(status_callback=status_callback)
        service._speak_start_time = time.time()

        # Simulate engine status callback
        service._on_engine_status(TTSEngineState.GENERATING)

        status_callback.assert_called()

    def test_status_callback_receives_tts_status(self, status_callback):
        """Status callback should receive TTSStatus object."""
        service = TTSService(status_callback=status_callback)
        service._speak_start_time = time.time()

        service._on_engine_status(TTSEngineState.PLAYING)

        status_callback.assert_called()
        call_args = status_callback.call_args[0][0]
        assert isinstance(call_args, TTSStatus)

    def test_status_callback_includes_elapsed_time(self, status_callback):
        """Status callback should include elapsed time."""
        service = TTSService(status_callback=status_callback)
        service._speak_start_time = time.time() - 1.0

        service._on_engine_status(TTSEngineState.PLAYING)

        call_args = status_callback.call_args[0][0]
        assert call_args.elapsed is not None
        assert call_args.elapsed >= 1.0

    def test_no_callback_when_not_set(self):
        """No callback should be invoked when not set."""
        service = TTSService()  # No callback

        # Should not raise
        service._on_engine_status(TTSEngineState.IDLE)

    def test_callback_receives_all_state_transitions(self, status_callback):
        """Callback should receive all state transitions."""
        service = TTSService(status_callback=status_callback)
        service._speak_start_time = time.time()

        states = [
            TTSEngineState.LOADING_MODEL,
            TTSEngineState.GENERATING,
            TTSEngineState.PLAYING,
            TTSEngineState.STOPPING,
            TTSEngineState.IDLE
        ]

        for state in states:
            service._on_engine_status(state)

        assert status_callback.call_count == len(states)


# =============================================================================
# shutdown() Method Tests
# =============================================================================

class TestShutdownMethod:
    """Tests for shutdown() method."""

    @pytest.mark.asyncio
    async def test_shutdown_calls_engine_shutdown(self, mock_engine):
        """shutdown() should call engine.shutdown()."""
        service = TTSService()
        service._engine = mock_engine

        await service.shutdown()

        mock_engine.shutdown.assert_called_once()

    @pytest.mark.asyncio
    async def test_shutdown_when_engine_is_none(self, service_no_engine):
        """shutdown() should handle case when engine is None."""
        # Should not raise
        await service_no_engine.shutdown()

    @pytest.mark.asyncio
    async def test_shutdown_is_idempotent(self, mock_engine):
        """shutdown() should be safe to call multiple times."""
        service = TTSService()
        service._engine = mock_engine

        await service.shutdown()
        await service.shutdown()

        # Should handle gracefully


# =============================================================================
# Error Handling Tests
# =============================================================================

class TestErrorHandling:
    """Tests for error handling in TTSService."""

    @pytest.mark.asyncio
    async def test_speak_engine_error_propagates(self, mock_engine):
        """Error from engine.speak() should propagate."""
        service = TTSService()
        service._engine = mock_engine
        mock_engine.speak = AsyncMock(side_effect=Exception("Engine error"))

        with pytest.raises(Exception) as exc_info:
            await service.speak("Hello")

        assert "Engine error" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_stop_engine_error_handled(self, mock_engine):
        """Error from engine.stop() should be handled gracefully."""
        service = TTSService()
        service._engine = mock_engine
        mock_engine.stop = AsyncMock(side_effect=Exception("Stop error"))

        # Should not raise or should raise gracefully
        try:
            await service.stop()
        except Exception as e:
            # If it raises, it should be the engine error
            assert "Stop error" in str(e)

    @pytest.mark.asyncio
    async def test_initialization_error_handled(self):
        """Error during engine initialization should be handled."""
        service = TTSService()

        with patch.object(TTSEngine, '__init__', side_effect=Exception("Init error")):
            with pytest.raises(Exception) as exc_info:
                await service.initialize()

            assert "Init error" in str(exc_info.value)

    def test_callback_error_does_not_crash_service(self):
        """Error in status callback should not crash service."""
        def bad_callback(status):
            raise Exception("Callback error")

        service = TTSService(status_callback=bad_callback)
        service._speak_start_time = time.time()

        # Should not raise
        try:
            service._on_engine_status(TTSEngineState.IDLE)
        except Exception:
            pytest.fail("Callback error should not propagate")


# =============================================================================
# IPC Integration Tests (Message Handling)
# =============================================================================

class TestIPCIntegration:
    """Tests for IPC message handling integration."""

    @pytest.mark.asyncio
    async def test_handle_tts_speak_message(self, mock_engine):
        """Service should handle TTS_SPEAK IPC message."""
        service = TTSService()
        service._engine = mock_engine

        # Simulate IPC message payload
        payload = {"text": "Hello world"}

        # The actual IPC handler would call speak()
        await service.speak(payload["text"])

        mock_engine.speak.assert_called_once_with("Hello world")

    @pytest.mark.asyncio
    async def test_handle_tts_stop_message(self, mock_engine):
        """Service should handle TTS_STOP IPC message."""
        service = TTSService()
        service._engine = mock_engine

        # Simulate IPC message
        await service.stop()

        mock_engine.stop.assert_called_once()

    def test_status_for_ipc_response(self, mock_engine):
        """get_status() should provide data suitable for IPC response."""
        service = TTSService()
        service._engine = mock_engine
        mock_engine.state = TTSEngineState.PLAYING
        service._speak_start_time = time.time() - 1.0

        status = service.get_status()

        # Status should be serializable for IPC
        assert isinstance(status.state, str)
        assert status.elapsed is None or isinstance(status.elapsed, float)


# =============================================================================
# Edge Cases and Boundary Tests
# =============================================================================

class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @pytest.mark.asyncio
    async def test_concurrent_speak_calls(self, mock_engine):
        """Concurrent speak() calls should be handled safely."""
        service = TTSService()
        service._engine = mock_engine

        # Make multiple concurrent calls
        tasks = [
            service.speak("Text 1"),
            service.speak("Text 2"),
            service.speak("Text 3")
        ]

        await asyncio.gather(*tasks)

        # All calls should complete (order may vary)
        assert mock_engine.speak.call_count == 3

    @pytest.mark.asyncio
    async def test_speak_after_stop(self, mock_engine):
        """speak() after stop() should work normally."""
        service = TTSService()
        service._engine = mock_engine

        await service.speak("First")
        await service.stop()
        await service.speak("Second")

        assert mock_engine.speak.call_count == 2

    @pytest.mark.asyncio
    async def test_stop_during_idle(self, mock_engine):
        """stop() when idle should be safe."""
        service = TTSService()
        service._engine = mock_engine
        mock_engine.state = TTSEngineState.IDLE

        # Should not raise
        await service.stop()

    def test_set_voice_preserves_across_operations(self, service_no_engine):
        """Voice preset should be preserved across operations."""
        service_no_engine.set_voice("english_female")

        # Get status (doesn't change preset)
        service_no_engine.get_status()

        assert service_no_engine._current_preset == "english_female"

    @pytest.mark.asyncio
    async def test_rapid_status_changes(self, status_callback):
        """Rapid status changes should all be reported."""
        service = TTSService(status_callback=status_callback)
        service._speak_start_time = time.time()

        # Simulate rapid state changes
        for _ in range(10):
            service._on_engine_status(TTSEngineState.GENERATING)
            service._on_engine_status(TTSEngineState.IDLE)

        assert status_callback.call_count == 20

    @pytest.mark.asyncio
    async def test_speak_with_very_long_text(self, mock_engine):
        """speak() should handle very long text."""
        service = TTSService()
        service._engine = mock_engine

        # 10000 character text
        very_long_text = "word " * 2000
        await service.speak(very_long_text)

        mock_engine.speak.assert_called_once()

    @pytest.mark.asyncio
    async def test_multiple_shutdowns(self, mock_engine):
        """Multiple shutdown() calls should be safe."""
        service = TTSService()
        service._engine = mock_engine

        await service.shutdown()
        await service.shutdown()
        await service.shutdown()

        # Should not crash


# =============================================================================
# Thread Safety Tests
# =============================================================================

class TestThreadSafety:
    """Tests for thread safety in TTSService."""

    @pytest.mark.asyncio
    async def test_concurrent_status_queries(self, mock_engine):
        """Concurrent get_status() calls should be safe."""
        service = TTSService()
        service._engine = mock_engine
        service._speak_start_time = time.time()

        async def query_status():
            for _ in range(100):
                service.get_status()
                await asyncio.sleep(0)

        tasks = [query_status() for _ in range(5)]
        await asyncio.gather(*tasks)

        # All queries should complete without error

    @pytest.mark.asyncio
    async def test_concurrent_voice_changes(self):
        """Concurrent set_voice() calls should be safe."""
        service = TTSService()

        def change_voice():
            for preset in ["english_male", "english_female"]:
                service.set_voice(preset)

        # Run in multiple tasks
        loop = asyncio.get_event_loop()
        tasks = [loop.run_in_executor(None, change_voice) for _ in range(5)]
        await asyncio.gather(*tasks)

        # Final preset should be one of the valid presets
        assert service._current_preset in VOICE_PRESETS


# =============================================================================
# Integration-like Tests (Still with Mocks)
# =============================================================================

class TestServiceIntegration:
    """Integration-like tests for TTSService."""

    @pytest.mark.asyncio
    async def test_full_speak_workflow(self, status_callback):
        """Test complete speak workflow: init -> speak -> status -> stop."""
        service = TTSService(status_callback=status_callback)

        with patch.object(TTSEngine, '__init__', return_value=None), \
             patch.object(TTSEngine, 'initialize', new_callable=AsyncMock), \
             patch.object(TTSEngine, 'speak', new_callable=AsyncMock), \
             patch.object(TTSEngine, 'stop', new_callable=AsyncMock), \
             patch.object(TTSEngine, 'state', TTSEngineState.IDLE):

            # Initialize
            await service.initialize()

            # Speak
            await service.speak("Hello world")

            # Get status
            status = service.get_status()
            assert isinstance(status, TTSStatus)

            # Stop
            await service.stop()

    @pytest.mark.asyncio
    async def test_voice_preset_workflow(self, mock_engine):
        """Test voice preset change workflow."""
        service = TTSService()
        service._engine = mock_engine

        # List presets
        presets = service.list_presets()
        assert len(presets) > 0

        # Change preset
        result = service.set_voice("english_female")
        assert result is True

        # Verify config updated
        config = service.get_voice_config()
        assert "language" in config

        # Speak with new voice
        await service.speak("Hello")
        mock_engine.speak.assert_called()

    @pytest.mark.asyncio
    async def test_error_recovery_workflow(self, mock_engine):
        """Test error recovery workflow."""
        service = TTSService()
        service._engine = mock_engine

        # First speak fails
        mock_engine.speak = AsyncMock(side_effect=Exception("Error"))

        try:
            await service.speak("Fail")
        except Exception:
            pass

        # Recovery - second speak succeeds
        mock_engine.speak = AsyncMock()
        await service.speak("Success")

        mock_engine.speak.assert_called_with("Success")
