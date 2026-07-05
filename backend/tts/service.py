"""
TTS Service Module

Provides TTSService as the high-level interface for text-to-speech operations.

Task: 3.1.3 TTSService wrapping TTSEngine with service layer
"""

import logging
import time
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional

from .engine import TTSEngine, TTSEngineState, VoiceConfig, VOICE_PRESETS

logger = logging.getLogger(__name__)


@dataclass
class TTSStatus:
    """Status of the TTS service."""
    state: str
    text: Optional[str] = None
    elapsed: Optional[float] = None
    error: Optional[str] = None


class TTSService:
    """High-level TTS service with lazy engine initialization."""

    def __init__(
        self,
        status_callback: Optional[Callable] = None,
        default_preset: str = "english_male"
    ):
        """Initialize TTSService.

        Args:
            status_callback: Optional callback invoked on status changes.
            default_preset: Default voice preset name.

        Raises:
            ValueError: If default_preset is not a valid preset name.
        """
        if default_preset not in VOICE_PRESETS:
            raise ValueError(f"Invalid preset: {default_preset}")

        self._engine: Optional[TTSEngine] = None
        self._status_callback = status_callback
        self._speak_start_time: Optional[float] = None
        self._current_preset: str = default_preset
        self._initialized: bool = False

    def _ensure_engine(self, log_message: str) -> TTSEngine:
        """Ensure engine exists, creating it if needed.

        Args:
            log_message: Message to log when creating the engine.

        Returns:
            The TTS engine instance.
        """
        if self._engine is None:
            logger.info(log_message)
            self._engine = TTSEngine(status_callback=self._on_engine_status)
            self._engine.set_voice_config(VOICE_PRESETS[self._current_preset])
        return self._engine

    async def initialize(self) -> None:
        """Pre-initialize the TTS engine (preload model) without speaking.

        Call this when entering Reading Mode to warm up the model,
        avoiding delay on first text-to-speech request.
        """
        # Return early if already initialized (idempotent)
        if self._initialized:
            return

        engine = self._ensure_engine("Pre-initializing TTS engine (warmup)")
        await engine.initialize()
        self._initialized = True

    async def speak(self, text: str) -> None:
        """Speak the given text, creating engine lazily if needed.

        Args:
            text: The text to synthesize and speak.
        """
        self._ensure_engine("Creating TTS engine (lazy init)")

        logger.debug("Speaking text (%d chars)", len(text))
        self._speak_start_time = time.time()
        await self._engine.speak(text)

    async def stop(self) -> None:
        """Stop current speech playback."""
        logger.debug("Stopping speech")
        if self._engine is not None:
            await self._engine.stop()
        self._speak_start_time = None

    def get_status(self) -> TTSStatus:
        """Get current TTS status."""
        if self._engine is None:
            return TTSStatus(state="idle")

        elapsed = None
        if self._speak_start_time is not None:
            elapsed = time.time() - self._speak_start_time

        return TTSStatus(
            state=self._engine.state.value,
            elapsed=elapsed,
        )

    def get_voice_config(self) -> Dict[str, str]:
        """Get current voice configuration as a dict."""
        if self._engine is not None:
            config = self._engine.get_voice_config()
        else:
            config = VOICE_PRESETS[self._current_preset]

        return {
            "language": config.language,
            "voice_instruct": config.voice_instruct,
        }

    def set_voice(self, preset_name: str) -> bool:
        """Set voice preset by name. Returns True if valid, False otherwise.

        Args:
            preset_name: Name of the voice preset to use.

        Returns:
            True if the preset is valid and was set, False otherwise.
        """
        if preset_name not in VOICE_PRESETS:
            logger.warning("Invalid voice preset: %s", preset_name)
            return False

        logger.info("Voice preset set to: %s", preset_name)
        self._current_preset = preset_name
        if self._engine is not None:
            self._engine.set_voice_config(VOICE_PRESETS[preset_name])

        return True

    # Alias for backward compatibility
    def set_preset(self, name: str) -> bool:
        """Set voice preset by name. Returns True if valid, False otherwise."""
        return self.set_voice(name)

    def list_presets(self) -> List[str]:
        """Return list of available preset names."""
        return list(VOICE_PRESETS.keys())

    async def shutdown(self) -> None:
        """Shutdown the TTS engine."""
        logger.info("Shutting down TTS service")
        if self._engine is not None:
            await self._engine.shutdown()

    def _on_engine_status(self, state: TTSEngineState) -> None:
        """Internal callback invoked by engine on state changes."""
        if self._status_callback is None:
            return

        elapsed = None
        if self._speak_start_time is not None:
            elapsed = time.time() - self._speak_start_time

        status = TTSStatus(state=state.value, elapsed=elapsed)

        # Wrap callback in try-except to prevent errors from crashing service
        try:
            self._status_callback(status)
        except Exception as e:
            logger.error("Status callback error: %s", e)
