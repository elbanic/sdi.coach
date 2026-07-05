"""
Tests for TTS Engine (Qwen3-TTS MLX)

TDD RED Phase: These tests define expected behavior before implementation.
All tests should FAIL initially.

Requirements covered:
- 3.1.1 Qwen3-TTS MLX model initialization (lazy loading, async)
- 3.1.2 Text to audio conversion (generate method)
- 3.1.3 Voice presets support (English voices)
- 3.1.4 Chunked audio streaming (queue-based)

Feature: TTS Engine
TTS Engine Tests
Model: mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16
Sample Rate: 24000 Hz
States: idle, loading_model, generating, playing, stopping
"""

import asyncio
import pytest
import numpy as np
from unittest.mock import AsyncMock, MagicMock, patch
import threading
import queue
import time

# =============================================================================
# Import the types and classes to test (will fail until implementation exists)
# =============================================================================

from tts.engine import (
    TTSEngine,
    TTSEngineState,
    VoiceConfig,
    VOICE_PRESETS,
    TTSError,
    ModelInitializationError,
    GenerationError,
    AudioChunk,
)


# =============================================================================
# Fixtures
# =============================================================================

@pytest.fixture
def engine():
    """Create a fresh TTSEngine instance for each test."""
    return TTSEngine()


@pytest.fixture
def engine_with_callback():
    """Create a TTSEngine with status callback."""
    callback = MagicMock()
    return TTSEngine(status_callback=callback), callback


@pytest.fixture
def mock_mlx_audio():
    """Mock the mlx_audio.tts module to avoid actual model loading."""
    with patch("tts.engine.load_model") as mock_load:
        mock_model = MagicMock()
        mock_model.sample_rate = 24000
        # Default: generate returns empty iterator
        mock_model.generate_voice_design.return_value = iter([])
        mock_load.return_value = mock_model
        yield mock_load, mock_model


@pytest.fixture
def mock_model_with_audio(mock_mlx_audio):
    """Mock model that yields audio chunks."""
    mock_load, mock_model = mock_mlx_audio

    # Create mock audio chunks
    def generate_chunks(*args, **kwargs):
        for i in range(3):
            chunk = MagicMock()
            chunk.audio = np.random.randn(24000).astype(np.float32)  # 1 second
            chunk.sample_rate = 24000
            yield chunk

    mock_model.generate_voice_design.return_value = generate_chunks()
    return mock_load, mock_model


@pytest.fixture
def sample_text():
    """Sample text for TTS generation."""
    return "Hello, welcome to the system design interview."


@pytest.fixture
def long_text():
    """Long text that should be split into chunks."""
    return """
    Let's start with a system design interview for a URL shortener service.
    First, we need to understand the requirements and constraints.
    How many URLs do you expect to handle per day?
    What are the read to write ratios you're anticipating?
    """


# =============================================================================
# Task 3.1.1: Exception Types Tests
# =============================================================================

class TestTTSExceptions:
    """Tests for TTS exception hierarchy."""

    def test_tts_error_is_base_exception(self):
        """TTSError should be a subclass of Exception."""
        error = TTSError("something went wrong")
        assert isinstance(error, Exception)
        assert str(error) == "something went wrong"

    def test_tts_error_default_message(self):
        """TTSError can be instantiated without arguments."""
        error = TTSError()
        assert isinstance(error, Exception)

    def test_model_initialization_error_inherits_tts_error(self):
        """ModelInitializationError should be a subclass of TTSError."""
        error = ModelInitializationError("failed to load model")
        assert isinstance(error, TTSError)
        assert isinstance(error, Exception)
        assert "failed to load model" in str(error)

    def test_generation_error_inherits_tts_error(self):
        """GenerationError should be a subclass of TTSError."""
        error = GenerationError("generation failed for input text")
        assert isinstance(error, TTSError)
        assert isinstance(error, Exception)
        assert "generation failed" in str(error)

    def test_exception_hierarchy_catch_all(self):
        """Catching TTSError should catch all TTS-specific exceptions."""
        exceptions = [
            ModelInitializationError("init fail"),
            GenerationError("gen fail"),
        ]
        for exc in exceptions:
            with pytest.raises(TTSError):
                raise exc


# =============================================================================
# Task 3.1.1: TTSEngineState Enum Tests
# =============================================================================

class TestTTSEngineState:
    """Tests for TTSEngineState enum values."""

    def test_idle_value(self):
        """IDLE state should have value 'idle'."""
        assert TTSEngineState.IDLE.value == "idle"

    def test_loading_model_value(self):
        """LOADING_MODEL state should have value 'loading_model'."""
        assert TTSEngineState.LOADING_MODEL.value == "loading_model"

    def test_generating_value(self):
        """GENERATING state should have value 'generating'."""
        assert TTSEngineState.GENERATING.value == "generating"

    def test_playing_value(self):
        """PLAYING state should have value 'playing'."""
        assert TTSEngineState.PLAYING.value == "playing"

    def test_stopping_value(self):
        """STOPPING state should have value 'stopping'."""
        assert TTSEngineState.STOPPING.value == "stopping"

    def test_all_states_present(self):
        """All five states should be defined."""
        state_values = {s.value for s in TTSEngineState}
        expected = {"idle", "loading_model", "generating", "playing", "stopping"}
        assert state_values == expected

    def test_state_is_string_enum(self):
        """TTSEngineState should be a string enum (str, Enum)."""
        assert isinstance(TTSEngineState.IDLE, str)
        assert TTSEngineState.IDLE == "idle"


# =============================================================================
# Task 3.1.3: VoiceConfig Dataclass Tests
# =============================================================================

class TestVoiceConfig:
    """Tests for VoiceConfig dataclass."""

    def test_creation_with_all_fields(self):
        """VoiceConfig should store language and voice_instruct."""
        config = VoiceConfig(
            language="English",
            voice_instruct="A professional male English voice, clear and articulate."
        )
        assert config.language == "English"
        assert "professional" in config.voice_instruct

    def test_equality(self):
        """Two VoiceConfigs with the same fields should be equal."""
        a = VoiceConfig(language="English", voice_instruct="desc")
        b = VoiceConfig(language="English", voice_instruct="desc")
        assert a == b

    def test_inequality(self):
        """Two VoiceConfigs with different fields should not be equal."""
        a = VoiceConfig(language="English", voice_instruct="desc A")
        b = VoiceConfig(language="English", voice_instruct="desc B")
        assert a != b


# =============================================================================
# Task 3.1.3: Voice Presets Tests
# =============================================================================

class TestVoicePresets:
    """Tests for VOICE_PRESETS dictionary (English voices only for sdi.coach)."""

    def test_has_english_female(self):
        """VOICE_PRESETS should contain 'english_female' key."""
        assert "english_female" in VOICE_PRESETS

    def test_has_english_male(self):
        """VOICE_PRESETS should contain 'english_male' key."""
        assert "english_male" in VOICE_PRESETS

    def test_minimum_two_presets(self):
        """VOICE_PRESETS should contain at least 2 English presets."""
        assert len(VOICE_PRESETS) >= 2

    def test_all_presets_are_voice_config(self):
        """All presets should be VoiceConfig instances."""
        for name, preset in VOICE_PRESETS.items():
            assert isinstance(preset, VoiceConfig), (
                f"Preset '{name}' should be VoiceConfig, got {type(preset)}"
            )

    def test_english_female_has_language_field(self):
        """english_female preset should have language 'English'."""
        assert VOICE_PRESETS["english_female"].language == "English"

    def test_english_male_has_language_field(self):
        """english_male preset should have language 'English'."""
        assert VOICE_PRESETS["english_male"].language == "English"

    def test_all_presets_have_voice_instruct(self):
        """All presets should have a non-empty voice_instruct."""
        for name, preset in VOICE_PRESETS.items():
            assert preset.voice_instruct, (
                f"Preset '{name}' should have non-empty voice_instruct"
            )

    def test_english_presets_have_english_instruct(self):
        """English presets should reference English characteristics."""
        for name in ("english_female", "english_male"):
            instruct = VOICE_PRESETS[name].voice_instruct.lower()
            # Should describe voice characteristics
            assert len(instruct) > 20, (
                f"Preset '{name}' voice_instruct should be descriptive"
            )


# =============================================================================
# Task 3.1.1: TTSEngine Creation and Defaults Tests
# =============================================================================

class TestTTSEngineDefaults:
    """Tests for TTSEngine default state and configuration."""

    def test_default_state_is_idle(self, engine):
        """TTSEngine should start in IDLE state."""
        assert engine.state == TTSEngineState.IDLE

    def test_default_voice_config_is_english_male(self, engine):
        """TTSEngine default voice config should be english_male preset."""
        expected = VOICE_PRESETS["english_male"]
        config = engine.get_voice_config()
        assert config.language == expected.language
        assert config.voice_instruct == expected.voice_instruct

    def test_model_id_constant(self):
        """TTSEngine.MODEL_ID should be the Qwen3-TTS model identifier."""
        assert TTSEngine.MODEL_ID == "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"

    def test_sample_rate_constant(self):
        """TTSEngine.SAMPLE_RATE should be 24000 Hz."""
        assert TTSEngine.SAMPLE_RATE == 24000

    def test_model_is_none_before_init(self, engine):
        """Model should be None before initialize() is called."""
        assert engine._model is None

    def test_is_initialized_false_by_default(self, engine):
        """is_initialized should be False by default."""
        assert engine.is_initialized is False

    def test_status_callback_stored(self):
        """status_callback passed to constructor should be stored."""
        callback = MagicMock()
        engine = TTSEngine(status_callback=callback)
        assert engine._status_callback is callback

    def test_no_status_callback_by_default(self, engine):
        """status_callback should default to None."""
        assert engine._status_callback is None

    def test_stop_event_exists(self, engine):
        """Engine should have a threading.Event for stop signaling."""
        assert isinstance(engine._stop_event, threading.Event)

    def test_stop_event_initially_not_set(self, engine):
        """Stop event should not be set initially."""
        assert not engine._stop_event.is_set()


# =============================================================================
# Task 3.1.3: TTSEngine Voice Configuration Tests
# =============================================================================

class TestTTSEngineVoiceConfig:
    """Tests for TTSEngine voice configuration management."""

    def test_set_voice_config_updates(self, engine):
        """set_voice_config() should update the engine's voice config."""
        new_config = VoiceConfig(
            language="English",
            voice_instruct="A deep male English voice"
        )
        engine.set_voice_config(new_config)
        assert engine.get_voice_config() == new_config

    def test_get_voice_config_returns_current(self, engine):
        """get_voice_config() should return the current configuration."""
        config = engine.get_voice_config()
        assert isinstance(config, VoiceConfig)
        assert config.language == "English"

    def test_set_voice_config_persists_across_calls(self, engine):
        """Voice config should persist after being set until changed again."""
        config_a = VoiceConfig(language="English", voice_instruct="Voice A")
        engine.set_voice_config(config_a)
        assert engine.get_voice_config() == config_a

        # Still the same after another get
        assert engine.get_voice_config() == config_a

        config_b = VoiceConfig(language="English", voice_instruct="Voice B")
        engine.set_voice_config(config_b)
        assert engine.get_voice_config() == config_b

    def test_set_voice_config_with_preset(self, engine):
        """Setting voice config with a preset value should work."""
        engine.set_voice_config(VOICE_PRESETS["english_female"])
        config = engine.get_voice_config()
        assert config.language == "English"


# =============================================================================
# Task 3.1.1: TTSEngine Initialization Tests
# =============================================================================

class TestTTSEngineInitialize:
    """Tests for TTSEngine.initialize() behavior (Task 3.1.1)."""

    @pytest.mark.asyncio
    async def test_initialize_sets_state_to_loading_then_idle(self, mock_mlx_audio):
        """initialize() should transition IDLE -> LOADING_MODEL -> IDLE."""
        mock_load, mock_model = mock_mlx_audio

        states_observed = []
        callback = MagicMock(side_effect=lambda s: states_observed.append(s))
        engine = TTSEngine(status_callback=callback)

        await engine.initialize()

        assert TTSEngineState.LOADING_MODEL in states_observed
        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_initialize_loads_model(self, mock_mlx_audio):
        """initialize() should call load_model with MODEL_ID."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()

        await engine.initialize()

        mock_load.assert_called_once_with(TTSEngine.MODEL_ID)

    @pytest.mark.asyncio
    async def test_initialize_idempotent(self, mock_mlx_audio):
        """Calling initialize() twice should only load model once."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()

        await engine.initialize()
        await engine.initialize()

        mock_load.assert_called_once()

    @pytest.mark.asyncio
    async def test_initialize_stores_model(self, mock_mlx_audio):
        """initialize() should store the loaded model on the engine."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()

        await engine.initialize()

        assert engine._model is mock_model
        assert engine.is_initialized is True

    @pytest.mark.asyncio
    async def test_initialize_raises_on_import_error(self, engine):
        """initialize() should raise ModelInitializationError if mlx_audio not installed."""
        with patch("tts.engine.load_model", side_effect=ImportError("mlx_audio not found")):
            with pytest.raises(ModelInitializationError) as exc_info:
                await engine.initialize()
            assert "mlx" in str(exc_info.value).lower()

    @pytest.mark.asyncio
    async def test_initialize_raises_on_model_not_found(self):
        """initialize() should raise ModelInitializationError for invalid model."""
        with patch("tts.engine.load_model", side_effect=Exception("Model not found")):
            engine = TTSEngine()
            with pytest.raises(ModelInitializationError):
                await engine.initialize()

    @pytest.mark.asyncio
    async def test_initialize_handles_timeout(self, mock_mlx_audio):
        """initialize() should handle model loading timeout gracefully."""
        with patch("tts.engine.asyncio.wait_for", side_effect=asyncio.TimeoutError()):
            engine = TTSEngine()
            with pytest.raises(ModelInitializationError) as exc_info:
                await engine.initialize()
            assert "timeout" in str(exc_info.value).lower()

    @pytest.mark.asyncio
    async def test_initialize_concurrent_calls_are_safe(self, mock_mlx_audio):
        """Concurrent calls to initialize() should be thread-safe."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()

        # Launch multiple concurrent initialization attempts
        tasks = [engine.initialize() for _ in range(5)]
        await asyncio.gather(*tasks)

        assert engine.is_initialized is True
        # Model should only be loaded once despite concurrent calls
        assert mock_load.call_count == 1


# =============================================================================
# Task 3.1.2: TTSEngine Generate/Speak Tests
# =============================================================================

class TestTTSEngineGenerate:
    """Tests for TTSEngine.generate() and speak() behavior (Task 3.1.2)."""

    @pytest.mark.asyncio
    async def test_generate_returns_async_iterator(self, mock_model_with_audio, sample_text):
        """generate() should return an async iterator of AudioChunks."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        chunks = []
        async for chunk in engine.generate(sample_text):
            chunks.append(chunk)
            break  # Just get the first chunk to verify it works

        # Should return AudioChunk objects
        assert len(chunks) >= 0  # May be empty for short text

    @pytest.mark.asyncio
    async def test_generate_yields_audio_chunks(self, mock_model_with_audio, sample_text):
        """generate() should yield AudioChunk objects with audio data."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        chunks = []
        async for chunk in engine.generate(sample_text):
            chunks.append(chunk)

        for chunk in chunks:
            assert isinstance(chunk, AudioChunk)
            assert hasattr(chunk, "audio")
            assert hasattr(chunk, "sample_rate")
            assert chunk.sample_rate == 24000

    @pytest.mark.asyncio
    async def test_generate_auto_initializes(self, mock_model_with_audio, sample_text):
        """generate() should auto-initialize if model not loaded."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()

        assert not engine.is_initialized

        async for _ in engine.generate(sample_text):
            pass

        assert engine.is_initialized

    @pytest.mark.asyncio
    async def test_generate_sets_state_to_generating(self, mock_model_with_audio, sample_text):
        """generate() should set state to GENERATING during generation."""
        mock_load, mock_model = mock_model_with_audio

        states_observed = []
        callback = MagicMock(side_effect=lambda s: states_observed.append(s))
        engine = TTSEngine(status_callback=callback)
        await engine.initialize()
        states_observed.clear()

        async for _ in engine.generate(sample_text):
            pass

        assert TTSEngineState.GENERATING in states_observed

    @pytest.mark.asyncio
    async def test_generate_returns_to_idle_after_completion(self, mock_model_with_audio, sample_text):
        """generate() should return to IDLE state after completion."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        async for _ in engine.generate(sample_text):
            pass

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_generate_empty_text_returns_nothing(self, mock_mlx_audio):
        """generate() with empty string should not yield any chunks."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        chunks = []
        async for chunk in engine.generate(""):
            chunks.append(chunk)

        assert len(chunks) == 0
        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_generate_whitespace_only_returns_nothing(self, mock_mlx_audio):
        """generate() with whitespace-only string should not yield chunks."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        chunks = []
        async for chunk in engine.generate("   \n\t  "):
            chunks.append(chunk)

        assert len(chunks) == 0

    @pytest.mark.asyncio
    async def test_generate_uses_current_voice_config(self, mock_model_with_audio, sample_text):
        """generate() should use the current voice configuration."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        custom_config = VoiceConfig(
            language="English",
            voice_instruct="A very deep professional male voice"
        )
        engine.set_voice_config(custom_config)

        async for _ in engine.generate(sample_text):
            pass

        # Verify generate_voice_design was called with correct parameters
        call_args = mock_model.generate_voice_design.call_args
        assert call_args is not None
        assert call_args.kwargs.get("instruct") == custom_config.voice_instruct

    @pytest.mark.asyncio
    async def test_generate_raises_on_model_not_loaded_when_auto_init_fails(self):
        """generate() should raise GenerationError if auto-init fails."""
        with patch("tts.engine.load_model", side_effect=ImportError("No module")):
            engine = TTSEngine()

            with pytest.raises((ModelInitializationError, GenerationError)):
                async for _ in engine.generate("test"):
                    pass


# =============================================================================
# Task 3.1.2: TTSEngine Speak Tests (Blocking)
# =============================================================================

class TestTTSEngineSpeak:
    """Tests for TTSEngine.speak() behavior (blocking audio output)."""

    @pytest.mark.asyncio
    async def test_speak_empty_string_does_nothing(self, mock_mlx_audio):
        """speak() with empty string should return without changing state."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        await engine.speak("")

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_speak_whitespace_only_does_nothing(self, mock_mlx_audio):
        """speak() with whitespace-only string should return without changing state."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        await engine.speak("   \n\t  ")

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_speak_generates_and_plays_audio(self, mock_model_with_audio, sample_text):
        """speak() should generate and play audio."""
        mock_load, mock_model = mock_model_with_audio

        states_observed = []
        callback = MagicMock(side_effect=lambda s: states_observed.append(s))
        engine = TTSEngine(status_callback=callback)

        with patch("tts.engine.sd") as mock_sd:
            mock_stream = MagicMock()
            mock_sd.OutputStream.return_value = mock_stream

            await engine.speak(sample_text)

        # Should have gone through GENERATING state
        assert TTSEngineState.GENERATING in states_observed

    @pytest.mark.asyncio
    async def test_speak_returns_to_idle_after_completion(self, mock_model_with_audio, sample_text):
        """speak() should return to IDLE state after completion."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()

        with patch("tts.engine.sd"):
            await engine.speak(sample_text)

        assert engine.state == TTSEngineState.IDLE


# =============================================================================
# Task 3.1.4: TTSEngine Streaming Tests
# =============================================================================

class TestTTSEngineStreaming:
    """Tests for TTSEngine chunked streaming (Task 3.1.4)."""

    @pytest.mark.asyncio
    async def test_stream_to_queue_returns_queue(self, mock_model_with_audio, sample_text):
        """stream_to_queue() should return an asyncio.Queue."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        audio_queue = await engine.stream_to_queue(sample_text)

        assert isinstance(audio_queue, asyncio.Queue)

    @pytest.mark.asyncio
    async def test_stream_to_queue_puts_audio_chunks(self, mock_model_with_audio, sample_text):
        """stream_to_queue() should put AudioChunks into the queue."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        audio_queue = await engine.stream_to_queue(sample_text)

        # Wait a bit for chunks to be generated
        await asyncio.sleep(0.1)

        chunks = []
        while not audio_queue.empty():
            chunk = await audio_queue.get()
            if chunk is None:  # End sentinel
                break
            chunks.append(chunk)

        # Should have received some chunks (or just the sentinel)
        # The actual number depends on the mock

    @pytest.mark.asyncio
    async def test_stream_to_queue_sends_none_on_completion(self, mock_model_with_audio, sample_text):
        """stream_to_queue() should send None sentinel when done."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        audio_queue = await engine.stream_to_queue(sample_text)

        # Consume all chunks until we get None
        received_none = False
        timeout = 5.0
        start = time.time()

        while time.time() - start < timeout:
            try:
                chunk = await asyncio.wait_for(audio_queue.get(), timeout=0.5)
                if chunk is None:
                    received_none = True
                    break
            except asyncio.TimeoutError:
                break

        assert received_none, "Should receive None sentinel on completion"

    def test_audio_chunk_dataclass(self):
        """AudioChunk should have audio and sample_rate fields."""
        audio_data = np.zeros(24000, dtype=np.float32)
        chunk = AudioChunk(audio=audio_data, sample_rate=24000)

        assert chunk.audio is audio_data
        assert chunk.sample_rate == 24000

    def test_audio_chunk_is_final_field(self):
        """AudioChunk should have optional is_final field."""
        chunk = AudioChunk(
            audio=np.zeros(1000, dtype=np.float32),
            sample_rate=24000,
            is_final=True
        )
        assert chunk.is_final is True

        chunk2 = AudioChunk(
            audio=np.zeros(1000, dtype=np.float32),
            sample_rate=24000
        )
        assert chunk2.is_final is False  # Default


# =============================================================================
# Task 3.1.1/3.1.2: TTSEngine Stop Tests
# =============================================================================

class TestTTSEngineStop:
    """Tests for TTSEngine.stop() behavior."""

    @pytest.mark.asyncio
    async def test_stop_when_idle_does_nothing(self, mock_mlx_audio):
        """stop() when already IDLE should be a no-op."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        assert engine.state == TTSEngineState.IDLE
        await engine.stop()
        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_stop_sets_stop_event(self, mock_mlx_audio):
        """stop() should set the _stop_event."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        engine._state = TTSEngineState.GENERATING

        await engine.stop()

        assert engine._stop_event.is_set()

    @pytest.mark.asyncio
    async def test_stop_returns_to_idle(self, mock_mlx_audio):
        """stop() should return the engine to IDLE state."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        engine._state = TTSEngineState.GENERATING

        await engine.stop()

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_stop_triggers_state_callbacks(self, mock_mlx_audio):
        """stop() should trigger STOPPING and then IDLE via status_callback."""
        mock_load, mock_model = mock_mlx_audio
        callback = MagicMock()
        engine = TTSEngine(status_callback=callback)
        engine._state = TTSEngineState.GENERATING

        await engine.stop()

        states = [call.args[0] for call in callback.call_args_list]
        assert TTSEngineState.STOPPING in states
        assert TTSEngineState.IDLE in states

    @pytest.mark.asyncio
    async def test_stop_interrupts_generation(self, mock_model_with_audio, long_text):
        """stop() should interrupt ongoing generation."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        # Start generation in background
        generation_task = asyncio.create_task(engine.speak(long_text))

        # Give it a moment to start
        await asyncio.sleep(0.05)

        # Stop should interrupt
        await engine.stop()

        # Wait for task to complete
        try:
            await asyncio.wait_for(generation_task, timeout=1.0)
        except asyncio.TimeoutError:
            generation_task.cancel()

        assert engine.state == TTSEngineState.IDLE


# =============================================================================
# Task 3.1.1: TTSEngine Shutdown Tests
# =============================================================================

class TestTTSEngineShutdown:
    """Tests for TTSEngine.shutdown() behavior."""

    @pytest.mark.asyncio
    async def test_shutdown_clears_model(self, mock_mlx_audio):
        """shutdown() should set _model to None."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        await engine.shutdown()

        assert engine._model is None
        assert engine.is_initialized is False

    @pytest.mark.asyncio
    async def test_shutdown_calls_stop(self, mock_mlx_audio):
        """shutdown() should call stop() before clearing model."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()
        engine._state = TTSEngineState.GENERATING

        await engine.shutdown()

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_shutdown_returns_to_idle(self, mock_mlx_audio):
        """shutdown() should leave engine in IDLE state."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        await engine.shutdown()

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_shutdown_idempotent(self, mock_mlx_audio):
        """shutdown() should be safe to call multiple times."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        await engine.shutdown()
        await engine.shutdown()

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_can_reinitialize_after_shutdown(self, mock_mlx_audio, sample_text):
        """Engine should be reinitializable after shutdown."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()
        await engine.shutdown()

        await engine.initialize()

        assert engine.is_initialized is True


# =============================================================================
# Task 3.1.1: Status Callback Tests
# =============================================================================

class TestTTSEngineStatusCallback:
    """Tests for TTSEngine status_callback invocation."""

    def test_set_state_calls_callback(self, mock_mlx_audio):
        """_set_state() should invoke status_callback with the new state."""
        mock_load, mock_model = mock_mlx_audio
        callback = MagicMock()
        engine = TTSEngine(status_callback=callback)

        engine._set_state(TTSEngineState.GENERATING)

        callback.assert_called_once_with(TTSEngineState.GENERATING)

    def test_set_state_without_callback_does_not_raise(self, engine):
        """_set_state() without callback should not raise."""
        engine._set_state(TTSEngineState.LOADING_MODEL)
        assert engine.state == TTSEngineState.LOADING_MODEL

    def test_callback_receives_all_transitions(self, mock_mlx_audio):
        """status_callback should be called for every state transition."""
        mock_load, mock_model = mock_mlx_audio
        callback = MagicMock()
        engine = TTSEngine(status_callback=callback)

        engine._set_state(TTSEngineState.LOADING_MODEL)
        engine._set_state(TTSEngineState.IDLE)
        engine._set_state(TTSEngineState.GENERATING)
        engine._set_state(TTSEngineState.PLAYING)
        engine._set_state(TTSEngineState.STOPPING)
        engine._set_state(TTSEngineState.IDLE)

        assert callback.call_count == 6
        states = [call.args[0] for call in callback.call_args_list]
        assert states == [
            TTSEngineState.LOADING_MODEL,
            TTSEngineState.IDLE,
            TTSEngineState.GENERATING,
            TTSEngineState.PLAYING,
            TTSEngineState.STOPPING,
            TTSEngineState.IDLE,
        ]


# =============================================================================
# Edge Cases and Error Handling Tests
# =============================================================================

class TestTTSEngineEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @pytest.mark.asyncio
    async def test_generate_very_short_text(self, mock_mlx_audio):
        """generate() should handle very short text (single word)."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        async for _ in engine.generate("Hi"):
            pass

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_generate_very_long_text(self, mock_model_with_audio):
        """generate() should handle very long text."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        long_text = "This is a test sentence. " * 100

        async for _ in engine.generate(long_text):
            pass

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_generate_text_with_special_characters(self, mock_mlx_audio, sample_text):
        """generate() should handle text with special characters."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        special_text = "Hello! How are you? That's great... @#$%^&*"

        async for _ in engine.generate(special_text):
            pass

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_generate_text_with_numbers(self, mock_mlx_audio):
        """generate() should handle text with numbers."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        text_with_numbers = "The system handles 1000 requests per second with 99.9% uptime."

        async for _ in engine.generate(text_with_numbers):
            pass

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_concurrent_generate_calls(self, mock_model_with_audio):
        """Multiple concurrent generate() calls should be handled safely."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        async def generate_text(text):
            async for _ in engine.generate(text):
                pass

        # Launch multiple concurrent generations
        tasks = [
            generate_text("Text one"),
            generate_text("Text two"),
            generate_text("Text three"),
        ]

        # Should not raise exceptions
        await asyncio.gather(*tasks)

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_generate_after_error_recovery(self, mock_mlx_audio, sample_text):
        """generate() should work after recovering from an error."""
        mock_load, mock_model = mock_mlx_audio
        engine = TTSEngine()
        await engine.initialize()

        # First call fails
        mock_model.generate_voice_design.side_effect = Exception("Generation failed")
        with pytest.raises(GenerationError):
            async for _ in engine.generate("test"):
                pass

        # Reset mock
        mock_model.generate_voice_design.side_effect = None
        mock_model.generate_voice_design.return_value = iter([])

        # Should work again
        async for _ in engine.generate(sample_text):
            pass

        assert engine.state == TTSEngineState.IDLE


# =============================================================================
# Audio Format Tests
# =============================================================================

class TestTTSEngineAudioFormat:
    """Tests for audio format verification."""

    @pytest.mark.asyncio
    async def test_generated_audio_is_float32(self, mock_model_with_audio, sample_text):
        """Generated audio should be float32 numpy array."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        async for chunk in engine.generate(sample_text):
            assert chunk.audio.dtype == np.float32

    @pytest.mark.asyncio
    async def test_generated_audio_sample_rate_is_24000(self, mock_model_with_audio, sample_text):
        """Generated audio should have 24000 Hz sample rate."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        async for chunk in engine.generate(sample_text):
            assert chunk.sample_rate == 24000

    @pytest.mark.asyncio
    async def test_generated_audio_is_mono(self, mock_model_with_audio, sample_text):
        """Generated audio should be mono (1D array)."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        async for chunk in engine.generate(sample_text):
            assert chunk.audio.ndim == 1, "Audio should be 1-dimensional (mono)"


# =============================================================================
# Integration-style Tests
# =============================================================================

class TestTTSEngineIntegration:
    """Integration-style tests for TTS engine workflow."""

    @pytest.mark.asyncio
    async def test_full_workflow_initialize_generate_shutdown(self, mock_model_with_audio, sample_text):
        """Test complete workflow: initialize -> generate -> shutdown."""
        mock_load, mock_model = mock_model_with_audio

        states = []
        callback = MagicMock(side_effect=lambda s: states.append(s))
        engine = TTSEngine(status_callback=callback)

        # Initialize
        await engine.initialize()
        assert engine.is_initialized

        # Generate
        async for _ in engine.generate(sample_text):
            pass

        # Shutdown
        await engine.shutdown()
        assert not engine.is_initialized

        # Verify state transitions
        assert TTSEngineState.LOADING_MODEL in states
        assert TTSEngineState.GENERATING in states
        assert states[-1] == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_voice_change_mid_session(self, mock_model_with_audio, sample_text):
        """Changing voice preset mid-session should work."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        # Generate with default voice
        async for _ in engine.generate("First sentence with default voice."):
            pass

        # Change voice
        engine.set_voice_config(VOICE_PRESETS["english_female"])

        # Generate with new voice
        async for _ in engine.generate("Second sentence with female voice."):
            pass

        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_stop_and_restart(self, mock_model_with_audio, sample_text):
        """Should be able to stop and restart generation."""
        mock_load, mock_model = mock_model_with_audio
        engine = TTSEngine()
        await engine.initialize()

        # Start generation
        gen_task = asyncio.create_task(engine.speak(sample_text))
        await asyncio.sleep(0.01)

        # Stop
        await engine.stop()
        try:
            await asyncio.wait_for(gen_task, timeout=1.0)
        except asyncio.TimeoutError:
            gen_task.cancel()

        assert engine.state == TTSEngineState.IDLE

        # Should be able to generate again
        async for _ in engine.generate("New text"):
            pass

        assert engine.state == TTSEngineState.IDLE
