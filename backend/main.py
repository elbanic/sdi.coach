#!/usr/bin/env python3
"""
sdi.coach Backend Server Entry Point

Task 7.1.2 [Python]: Backend server main (service initialization)
Task 7.1.3: Global error handling and signal handling

This module provides:
- Service initialization (IPC, Transcription, TTS, Agents)
- Server startup and event loop
- Environment variable loading and validation
- SIGTERM/SIGINT signal handling
- Graceful shutdown with resource cleanup
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import logging
import os
import random
import signal
import sys
import time
from dataclasses import dataclass
from typing import Optional

import numpy as np

# Import internal modules
from ipc.server import IPCServer
from ipc.protocol import (
    IPCMessage,
    MessageType,
    create_transcription_message,
    create_interview_question_message,
    create_interview_followup_message,
    create_feedback_response_message,
    create_tts_status_message,
    create_handshake_response,
    create_error_message,
    IPC_PROTOCOL_VERSION,
    is_version_compatible,
)
from transcription.service import TranscriptionService
from tts.engine import TTSEngine, VOICE_PRESETS
from agents.service import AgentService

# =============================================================================
# Configuration
# =============================================================================

@dataclass
class ServerConfig:
    """Server configuration loaded from environment variables."""
    socket_path: str
    log_level: str
    aws_region: str
    interviewer_model: str
    feedback_model: str
    tts_model: str
    debug: bool

    @classmethod
    def from_env(cls) -> "ServerConfig":
        """Load configuration from environment variables."""
        return cls(
            socket_path=os.getenv("SDICOACH_SOCKET_PATH", "/tmp/sdicoach.sock"),
            log_level=os.getenv("SDICOACH_LOG_LEVEL", "INFO"),
            aws_region=os.getenv("AWS_REGION", "us-west-2"),
            interviewer_model=os.getenv(
                "SDICOACH_INTERVIEWER_MODEL",
                "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
            ),
            feedback_model=os.getenv(
                "SDICOACH_FEEDBACK_MODEL",
                "us.anthropic.claude-opus-4-6-v1"
            ),
            tts_model=os.getenv(
                "SDICOACH_TTS_MODEL",
                "mlx-community/Qwen2.5-TTS-0.5B-4bit"
            ),
            debug=os.getenv("SDICOACH_DEBUG", "").lower() in ("1", "true", "yes"),
        )

    def validate(self) -> list[str]:
        """Validate configuration and return list of errors."""
        errors = []

        # Check AWS credentials: either AWS_PROFILE or explicit keys
        has_profile = bool(os.getenv("AWS_PROFILE"))
        has_keys = bool(os.getenv("AWS_ACCESS_KEY_ID")) and bool(os.getenv("AWS_SECRET_ACCESS_KEY"))
        if not has_profile and not has_keys:
            errors.append(
                "AWS credentials not configured. "
                "Set AWS_PROFILE or both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
            )

        return errors


# =============================================================================
# Logging Setup
# =============================================================================

def setup_logging(config: ServerConfig) -> logging.Logger:
    """Configure logging based on configuration."""
    level = getattr(logging, config.log_level.upper(), logging.INFO)

    # Configure root logger
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Get logger for this module
    logger = logging.getLogger("sdicoach.main")

    if config.debug:
        logger.setLevel(logging.DEBUG)
        logging.getLogger("sdicoach").setLevel(logging.DEBUG)

    return logger


# =============================================================================
# Backend Server
# =============================================================================

class SDICoachBackend:
    """Main backend server class that coordinates all services.

    Manages:
    - IPC Server for CLI communication
    - Transcription Service for STT
    - TTS Service for text-to-speech
    - Agent Service for AI interview/feedback
    """

    def __init__(self, config: ServerConfig, logger: logging.Logger):
        self.config = config
        self.logger = logger

        # Services (initialized lazily)
        self._ipc_server: Optional[IPCServer] = None
        self._transcription: Optional[TranscriptionService] = None
        self._tts_engine: Optional[TTSEngine] = None
        self._agents: Optional[AgentService] = None

        # State
        self._running = False
        self._shutdown_event = asyncio.Event()
        self._tts_was_stopped = False  # Track if TTS was interrupted by user

    # =========================================================================
    # Service Properties
    # =========================================================================

    @property
    def ipc_server(self) -> IPCServer:
        if self._ipc_server is None:
            self._ipc_server = IPCServer(socket_path=self.config.socket_path)
        return self._ipc_server

    @property
    def transcription(self) -> TranscriptionService:
        if self._transcription is None:
            self._transcription = TranscriptionService(
                on_transcription=self._on_transcription
            )
        return self._transcription

    @property
    def tts_engine(self) -> TTSEngine:
        if self._tts_engine is None:
            self._tts_engine = TTSEngine(status_callback=self._on_tts_status)
        return self._tts_engine

    @property
    def agents(self) -> AgentService:
        if self._agents is None:
            self._agents = AgentService(
                on_sentence_ready=None
            )
        return self._agents

    # =========================================================================
    # Initialization
    # =========================================================================

    async def initialize(self) -> None:
        """Initialize all services."""
        self.logger.info("Initializing sdi.coach backend services...")

        # Register IPC message handlers
        self._register_handlers()

        self.logger.info("Backend services initialized")

    def _register_handlers(self) -> None:
        """Register handlers for all IPC message types."""
        server = self.ipc_server

        # Client → Backend messages
        server.register_handler(MessageType.HANDSHAKE_REQUEST, self._handle_handshake)
        server.register_handler(MessageType.AUDIO_DATA, self._handle_audio_data)
        server.register_handler(MessageType.INTERVIEW_START, self._handle_interview_start)
        server.register_handler(MessageType.INTERVIEW_RESPONSE, self._handle_interview_response)
        server.register_handler(MessageType.INTERVIEW_END, self._handle_interview_end)
        server.register_handler(MessageType.FEEDBACK_REQUEST, self._handle_feedback_request)
        server.register_handler(MessageType.TTS_SPEAK, self._handle_tts_speak)
        server.register_handler(MessageType.TTS_STOP, self._handle_tts_stop)
        server.register_handler(MessageType.INTERVIEW_TIME_UP, self._handle_interview_time_up)

    # =========================================================================
    # IPC Message Handlers
    # =========================================================================

    async def _handle_handshake(self, message: IPCMessage) -> None:
        """Handle handshake request from CLI."""
        client_version = message.payload.get("version", "")

        # Check version compatibility
        accepted = is_version_compatible(client_version)

        self.logger.info(
            f"Handshake request: client={client_version}, "
            f"server={IPC_PROTOCOL_VERSION}, accepted={accepted}"
        )

        # Send handshake response
        response = create_handshake_response(
            accepted=accepted,
            server_version=IPC_PROTOCOL_VERSION,
            message_id=message.message_id,
        )
        await self.ipc_server.send_message(response)

    async def _handle_audio_data(self, message: IPCMessage) -> None:
        """Handle incoming audio data from CLI."""
        audio_base64 = message.payload.get("audio_base64", "")
        sample_rate = message.payload.get("sample_rate", 16000)

        self.logger.debug(f"Received audio_data: {len(audio_base64)} bytes base64")

        if not audio_base64:
            self.logger.warning("Received empty audio data")
            return

        try:
            # Decode base64 audio
            audio_bytes = base64.b64decode(audio_base64)

            # Convert bytes to float samples (16-bit PCM)
            audio_int16 = np.frombuffer(audio_bytes, dtype=np.int16)
            audio_float = audio_int16.astype(np.float32) / 32768.0
            samples = audio_float.tolist()

            # Debug: check audio level (RMS)
            if len(audio_float) > 0:
                rms = np.sqrt(np.mean(audio_float ** 2))
                if rms > 0.01:  # Only log if there's actual audio
                    self.logger.debug(f"Audio RMS: {rms:.4f}, samples: {len(samples)}")

            # Process through transcription service
            await self.transcription.process_audio(samples, time.time())

        except Exception as e:
            self.logger.error(f"Error processing audio data: {e}", exc_info=True)

    async def _handle_interview_start(self, message: IPCMessage) -> None:
        """Handle interview start request."""
        question = message.payload.get("question", "")

        if not question:
            self.logger.warning("Received interview start with empty question")
            return

        self.logger.info(f"Starting interview: {question}")

        # Select random voice for this interview session
        voice_preset = random.choice(list(VOICE_PRESETS.keys()))
        self.tts_engine.set_voice_config(VOICE_PRESETS[voice_preset])
        self.logger.info(f"Selected voice: {voice_preset}")

        try:
            # Start transcription service
            await self.transcription.start()

            # Start interview with agents
            self.logger.debug("Starting agent interview...")
            async for response_text in self.agents.start_interview(question):
                self.logger.debug(f"Got response from agent: {response_text[:50]}...")

                # Pause transcription to avoid GPU conflict
                if self._transcription is not None:
                    self._transcription.pause()

                # Reset stop flag before TTS
                self._tts_was_stopped = False

                # Notify that TTS is preparing/speaking
                status_msg = create_tts_status_message(status="speaking")
                await self.ipc_server.send_message(status_msg)

                # Send transcript and play TTS
                await self._speak_with_transcript(
                    text=response_text,
                    message_id=message.message_id,
                    is_question=True,
                )

                # Resume transcription
                if self._transcription is not None:
                    self._transcription.resume()

                # Notify that microphone is now active (only if not interrupted)
                if not self._tts_was_stopped:
                    status_msg = create_tts_status_message(status="completed")
                    await self.ipc_server.send_message(status_msg)

            self.logger.info("Interview started successfully")

        except Exception as e:
            self.logger.error(f"Error starting interview: {e}", exc_info=True)
            # Send error message to CLI
            error_msg = create_error_message(
                error="interview_start_failed",
                message=str(e),
                message_id=message.message_id,
            )
            await self.ipc_server.send_message(error_msg)

    async def _handle_interview_response(self, message: IPCMessage) -> None:
        """Handle user's interview response."""
        response_text = message.payload.get("response", "")

        if not response_text:
            self.logger.warning("Received empty interview response")
            return

        self.logger.debug(f"Processing user response: {response_text[:50]}...")

        try:
            # Process user response through agent
            async for followup_text in self.agents.process_user_response(response_text):
                self.logger.debug(f"Got followup from agent: {followup_text[:50]}...")

                # Pause transcription to avoid GPU conflict
                if self._transcription is not None:
                    self._transcription.pause()

                # Reset stop flag before TTS
                self._tts_was_stopped = False

                # Notify that TTS is preparing/speaking
                status_msg = create_tts_status_message(status="speaking")
                await self.ipc_server.send_message(status_msg)

                # Send transcript and play TTS
                await self._speak_with_transcript(
                    text=followup_text,
                    message_id=message.message_id,
                    is_question=False,
                )

                # Resume transcription
                if self._transcription is not None:
                    self._transcription.resume()

                # Notify that microphone is now active (only if not interrupted)
                if not self._tts_was_stopped:
                    status_msg = create_tts_status_message(status="completed")
                    await self.ipc_server.send_message(status_msg)

            self.logger.info("Followup processed successfully")

        except Exception as e:
            self.logger.error(f"Error processing interview response: {e}", exc_info=True)
            # Send error message to CLI
            error_msg = create_error_message(
                error="interview_response_failed",
                message=str(e),
                message_id=message.message_id,
            )
            await self.ipc_server.send_message(error_msg)

    async def _handle_interview_end(self, message: IPCMessage) -> None:
        """Handle interview end request."""
        self.logger.info("Ending interview session")

        try:
            # Stop TTS if playing
            if self._tts_engine is not None:
                await self._tts_engine.stop()

            # Stop transcription
            await self.transcription.stop()

        except Exception as e:
            self.logger.error(f"Error ending interview: {e}", exc_info=True)

    async def _handle_interview_time_up(self, message: IPCMessage) -> None:
        """Handle interview time up signal from CLI.

        When the 30-minute timer ends, generate a natural wrap-up statement
        from the interviewer and send it to CLI via TTS.
        """
        self.logger.info("Interview time is up, generating wrap-up statement")

        try:
            # Generate wrap-up through agent service
            async for wrap_up_text in self.agents.wrap_up():
                self.logger.debug(f"Got wrap-up from agent: {wrap_up_text[:50]}...")

                # Pause transcription to avoid GPU conflict
                if self._transcription is not None:
                    self._transcription.pause()

                # Reset stop flag before TTS
                self._tts_was_stopped = False

                # Notify that TTS is preparing/speaking
                status_msg = create_tts_status_message(status="speaking")
                await self.ipc_server.send_message(status_msg)

                # Send transcript and play TTS (as followup message type)
                await self._speak_with_transcript(
                    text=wrap_up_text,
                    message_id=message.message_id,
                    is_question=False,  # Use followup type for wrap-up
                )

                # Resume transcription
                if self._transcription is not None:
                    self._transcription.resume()

                # Notify that wrap-up is complete (only if not interrupted)
                if not self._tts_was_stopped:
                    status_msg = create_tts_status_message(status="completed")
                    await self.ipc_server.send_message(status_msg)

            self.logger.info("Interview wrap-up completed")

        except Exception as e:
            self.logger.error(f"Error generating wrap-up: {e}", exc_info=True)
            # Send error message to CLI
            error_msg = create_error_message(
                error="interview_time_up_failed",
                message=str(e),
                message_id=message.message_id,
            )
            await self.ipc_server.send_message(error_msg)

    async def _handle_feedback_request(self, message: IPCMessage) -> None:
        """Handle feedback request."""
        transcript = message.payload.get("transcript", [])

        self.logger.info("Generating interview feedback with %d transcript entries...", len(transcript))

        try:
            # Generate feedback through agent using Swift's transcript
            feedback_markdown = await self.agents.end_interview(transcript=transcript)

            # Send feedback response
            response = create_feedback_response_message(
                markdown=feedback_markdown,
                message_id=message.message_id,
            )
            await self.ipc_server.send_message(response)

        except Exception as e:
            self.logger.error(f"Error generating feedback: {e}", exc_info=True)
            # Send error message to CLI
            error_msg = create_error_message(
                error="feedback_generation_failed",
                message=str(e),
                message_id=message.message_id,
            )
            await self.ipc_server.send_message(error_msg)

    async def _handle_tts_speak(self, message: IPCMessage) -> None:
        """Handle TTS speak request."""
        text = message.payload.get("text", "")

        if not text:
            self.logger.warning("Received TTS request with empty text")
            return

        self.logger.debug(f"TTS speak: {text[:50]}...")

        try:
            self._tts_was_stopped = False
            status = create_tts_status_message(status="speaking", progress=0.0)
            await self.ipc_server.send_message(status)
            await self.tts_engine.speak(text)
            if not self._tts_was_stopped:
                status = create_tts_status_message(status="completed", progress=1.0)
                await self.ipc_server.send_message(status)
        except Exception as e:
            self.logger.error(f"TTS error: {e}")
            status = create_tts_status_message(status="error")
            await self.ipc_server.send_message(status)

    async def _handle_tts_stop(self, message: IPCMessage) -> None:
        """Handle TTS stop request (user pressed Enter to skip)."""
        self.logger.info("TTS stop requested by user")
        self._tts_was_stopped = True

        try:
            # Stop TTS engine
            if self._tts_engine is not None:
                await self._tts_engine.stop()

            # Resume transcription (was paused during TTS)
            if self._transcription is not None:
                self._transcription.resume()

            # Send stopped status
            status = create_tts_status_message(status="stopped")
            await self.ipc_server.send_message(status)

            self.logger.info("TTS stopped, transcription resumed")

        except Exception as e:
            self.logger.error(f"Error stopping TTS: {e}", exc_info=True)

    # =========================================================================
    # TTS Pipeline Helper
    # =========================================================================

    async def _speak_with_transcript(
        self,
        text: str,
        message_id: Optional[str],
        is_question: bool,
    ) -> None:
        """Play TTS and send transcript when audio starts.

        Sends the transcript when audio playback actually begins (after buffering),
        so the user sees the text at the same time they hear it.

        Args:
            text: Full text to speak.
            message_id: Message ID for IPC messages.
            is_question: True for interview_question, False for interview_followup.
        """
        if not text or not text.strip():
            return

        self.logger.info(f"TTS with transcript ({len(text)} chars)")

        async def on_playback_start():
            """Send transcript when audio starts playing."""
            self.logger.info("Audio started, sending transcript")
            if is_question:
                msg = create_interview_question_message(
                    question=text,
                    message_id=message_id,
                )
            else:
                msg = create_interview_followup_message(
                    question=text,
                    message_id=message_id,
                )
            await self.ipc_server.send_message(msg)

        # Play TTS - transcript sent when playback starts
        await self.tts_engine.speak_streamed(text, on_playback_start=on_playback_start)

        self.logger.info("TTS complete")

    # =========================================================================
    # Service Callbacks
    # =========================================================================

    async def _on_transcription(self, result) -> None:
        """Callback when transcription is available."""
        if not result.text:
            return

        self.logger.debug(f"Transcription: {result.text}")

        # Send transcription to CLI (CLI handles aggregation)
        message = create_transcription_message(
            text=result.text,
            is_final=True,  # Always true for simple chunk-based approach
        )

        try:
            await self.ipc_server.send_message(message)
        except Exception as e:
            self.logger.error(f"Error sending transcription: {e}", exc_info=True)

    def _on_tts_status(self, status) -> None:
        """Callback when TTS status changes."""
        self.logger.debug(f"TTS status: {status}")

    # =========================================================================
    # Server Lifecycle
    # =========================================================================

    async def start(self) -> None:
        """Start the backend server."""
        self.logger.info(f"Starting sdi.coach backend server...")
        self.logger.info(f"Socket path: {self.config.socket_path}")

        self._running = True

        # Start IPC server (this blocks until shutdown)
        await self.ipc_server.start()

    async def shutdown(self) -> None:
        """Gracefully shutdown all services."""
        if not self._running:
            return

        self.logger.info("Shutting down sdi.coach backend...")
        self._running = False

        # Stop IPC server
        if self._ipc_server is not None:
            await self._ipc_server.stop()

        # Stop transcription
        if self._transcription is not None:
            await self._transcription.stop()

        # Stop TTS engine
        if self._tts_engine is not None:
            await self._tts_engine.shutdown()

        # Stop agents
        if self._agents is not None:
            await self._agents.shutdown()

        self.logger.info("Backend shutdown complete")


# =============================================================================
# Signal Handling (Task 7.1.3)
# =============================================================================

def setup_signal_handlers(backend: SDICoachBackend, logger: logging.Logger) -> None:
    """Set up signal handlers for graceful shutdown."""
    loop = asyncio.get_event_loop()

    def signal_handler(sig: signal.Signals) -> None:
        logger.info(f"Received signal {sig.name}, initiating shutdown...")
        asyncio.create_task(backend.shutdown())

    # Register handlers for SIGTERM and SIGINT
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, signal_handler, sig)

    logger.debug("Signal handlers registered for SIGTERM and SIGINT")


# =============================================================================
# Main Entry Point
# =============================================================================

def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="sdi.coach Backend Server",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--socket", "-s",
        type=str,
        default=None,
        help="Unix socket path (default: /tmp/sdicoach.sock)",
    )

    parser.add_argument(
        "--debug", "-d",
        action="store_true",
        help="Enable debug logging",
    )

    parser.add_argument(
        "--version", "-v",
        action="version",
        version=f"sdi.coach backend v{IPC_PROTOCOL_VERSION}",
    )

    return parser.parse_args()


async def main() -> int:
    """Main entry point."""
    # Parse arguments
    args = parse_args()

    # Load configuration from environment
    config = ServerConfig.from_env()

    # Override with command line arguments
    if args.socket:
        config.socket_path = args.socket
    if args.debug:
        config.debug = True

    # Setup logging
    logger = setup_logging(config)

    # Print banner
    logger.info("=" * 50)
    logger.info("sdi.coach Backend Server")
    logger.info("=" * 50)

    # Validate configuration (warnings only)
    errors = config.validate()
    for error in errors:
        logger.warning(f"Configuration warning: {error}")

    # Create backend
    backend = SDICoachBackend(config, logger)

    # Initialize services
    await backend.initialize()

    # Setup signal handlers
    setup_signal_handlers(backend, logger)

    # Start server
    try:
        await backend.start()
        return 0
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        await backend.shutdown()
        return 0
    except Exception as e:
        logger.error(f"Server error: {e}")
        await backend.shutdown()
        return 1


if __name__ == "__main__":
    try:
        exit_code = asyncio.run(main())
        sys.exit(exit_code)
    except KeyboardInterrupt:
        sys.exit(0)
