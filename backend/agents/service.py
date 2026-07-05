"""
Agent Service - Interview Orchestration Layer

Coordinates InterviewerAgent and FeedbackAgent for complete interview sessions.
Manages session state, transcript recording, and TTS callback integration.

Features:
- Session state management (IDLE, INTERVIEWING, GENERATING_FEEDBACK)
- Transcript recording with timestamps
- TTS callback integration for streaming responses
- Error recovery with fallback messages
- Session statistics tracking
- Graceful shutdown

Example:
    service = AgentService(on_sentence_ready=tts_callback)

    async for sentence in service.start_interview("Design a URL shortener"):
        await tts_engine.speak(sentence)

    async for sentence in service.process_user_response("I would use hashing..."):
        await tts_engine.speak(sentence)

    feedback = await service.end_interview()
    print(feedback)
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum, auto
from typing import AsyncGenerator, Awaitable, Callable, Optional

from .feedback import FeedbackAgent, TranscriptEntry
from .interviewer import InterviewerAgent

# =============================================================================
# Module Logger
# =============================================================================

logger = logging.getLogger(__name__)

# =============================================================================
# Exceptions
# =============================================================================


class AgentServiceError(Exception):
    """Base exception for AgentService errors."""
    pass


class InvalidStateError(AgentServiceError):
    """Raised when operation is invalid for current state."""
    pass


class InterviewNotStartedError(AgentServiceError):
    """Raised when trying to operate on non-existent interview."""
    pass


# =============================================================================
# Session State
# =============================================================================


class SessionState(Enum):
    """State of the interview session."""
    IDLE = auto()
    INTERVIEWING = auto()
    GENERATING_FEEDBACK = auto()


# =============================================================================
# Session Statistics
# =============================================================================


@dataclass
class SessionStatistics:
    """Statistics for the current/last interview session.

    Attributes:
        question: The interview question
        turn_count: Number of conversation turns
        duration_seconds: Session duration in seconds
        start_time: When the session started
    """
    question: str | None = None
    turn_count: int = 0
    duration_seconds: float = 0.0
    start_time: datetime | None = None


# =============================================================================
# Agent Service
# =============================================================================


class AgentService:
    """Orchestrates interview agents and manages session state.

    Coordinates InterviewerAgent for conducting interviews and FeedbackAgent
    for generating post-interview feedback. Supports TTS callback integration
    for streaming responses.

    Attributes:
        interviewer: InterviewerAgent instance
        feedback: FeedbackAgent instance
        state: Current session state
        current_question: Active interview question
        on_sentence_ready: Optional TTS callback
    """

    def __init__(
        self,
        on_sentence_ready: Callable[[str], Awaitable[None]] | None = None,
    ):
        """Initialize the agent service.

        Args:
            on_sentence_ready: Optional async callback for each complete sentence.
                              Called when a sentence is ready for TTS.
        """
        self.interviewer = InterviewerAgent()
        self.feedback = FeedbackAgent()
        self.on_sentence_ready = on_sentence_ready

        self._current_question: str | None = None
        self._transcript: list[TranscriptEntry] = []
        self._state: SessionState = SessionState.IDLE
        self._start_time: datetime | None = None
        self._lock = asyncio.Lock()

        logger.info("AgentService initialized")

    # =========================================================================
    # Properties
    # =========================================================================

    @property
    def state(self) -> SessionState:
        """Get current session state."""
        return self._state

    @property
    def current_question(self) -> str | None:
        """Get current interview question."""
        return self._current_question

    @property
    def transcript(self) -> list[TranscriptEntry]:
        """Get a copy of the current transcript."""
        return list(self._transcript)

    @property
    def statistics(self) -> SessionStatistics:
        """Get session statistics."""
        duration = 0.0
        if self._start_time:
            duration = (datetime.now() - self._start_time).total_seconds()

        return SessionStatistics(
            question=self._current_question,
            turn_count=len([t for t in self._transcript if t.source == "user"]),
            duration_seconds=duration,
            start_time=self._start_time,
        )

    # =========================================================================
    # Interview Lifecycle
    # =========================================================================

    async def start_interview(self, question: str) -> AsyncGenerator[str, None]:
        """Start a new interview session.

        Yields sentences for TTS as they become available.

        Args:
            question: The system design question to discuss

        Yields:
            str: Each sentence of the opening statement

        Raises:
            AgentServiceError: If failed to start interview
        """
        logger.info("Starting interview with question: %s", question)

        async with self._lock:
            # Reset state for new interview
            self._current_question = question
            self._transcript = []
            self._start_time = datetime.now()
            self._state = SessionState.INTERVIEWING

            # Reset interviewer conversation
            self.interviewer.reset_conversation()

        try:
            # Initialize interviewer and generate opening via LLM
            if not self.interviewer.is_initialized:
                await self.interviewer.initialize()

            # Generate opening statement via LLM
            opening = await self.interviewer.start_interview(question)

            # Record the opening in transcript
            self._transcript.append(TranscriptEntry(
                timestamp=datetime.now(),
                source="interviewer",
                content=opening,
            ))

            # Call TTS callback if provided
            if self.on_sentence_ready:
                try:
                    await self.on_sentence_ready(opening)
                except Exception as e:
                    logger.warning("TTS callback error (continuing): %s", e)

            yield opening

        except Exception as e:
            logger.error("Failed to start interview: %s", e)
            raise AgentServiceError(f"Failed to start interview: {e}") from e

    async def process_user_response(
        self,
        user_input: str,
    ) -> AsyncGenerator[str, None]:
        """Process user response and generate follow-up.

        Yields sentences for TTS as they become available.

        Args:
            user_input: The user's spoken/typed response

        Yields:
            str: Each sentence of the interviewer's follow-up

        Raises:
            InterviewNotStartedError: If no active interview
            AgentServiceError: If failed to process response
        """
        if self._state != SessionState.INTERVIEWING:
            raise InterviewNotStartedError(
                "No active interview. Call start_interview() first."
            )

        if not self._current_question:
            raise InterviewNotStartedError(
                "No active interview question."
            )

        logger.debug("Processing user response: %s...", user_input[:50] if len(user_input) > 50 else user_input)

        # Record user input in transcript
        self._transcript.append(TranscriptEntry(
            timestamp=datetime.now(),
            source="user",
            content=user_input,
        ))

        try:
            # Generate interviewer response (interviewer already initialized in start_interview)
            response = await self.interviewer.process_user_response(user_input)

            # Record interviewer response
            self._transcript.append(TranscriptEntry(
                timestamp=datetime.now(),
                source="interviewer",
                content=response,
            ))

            # Call TTS callback if provided
            if self.on_sentence_ready:
                try:
                    await self.on_sentence_ready(response)
                except Exception as e:
                    logger.warning("TTS callback error (continuing): %s", e)

            yield response

        except Exception as e:
            logger.error("Failed to process user response: %s", e)
            raise AgentServiceError(f"Failed to process user response: {e}") from e

    async def wrap_up(self) -> AsyncGenerator[str, None]:
        """Generate a wrap-up statement when interview time is up.

        Called by backend when receiving interview_time_up message.
        The interviewer naturally concludes the interview.

        Yields:
            str: The interviewer's closing statement

        Raises:
            InterviewNotStartedError: If no active interview
            AgentServiceError: If wrap-up generation fails
        """
        if self._state != SessionState.INTERVIEWING:
            raise InterviewNotStartedError(
                "No active interview. Cannot wrap up."
            )

        logger.info("Generating interview wrap-up (time's up)")

        try:
            # Generate wrap-up statement
            wrap_up_text = await self.interviewer.wrap_up_interview()

            # Record wrap-up in transcript
            self._transcript.append(TranscriptEntry(
                timestamp=datetime.now(),
                source="interviewer",
                content=wrap_up_text,
            ))

            # Call TTS callback if provided
            if self.on_sentence_ready:
                try:
                    await self.on_sentence_ready(wrap_up_text)
                except Exception as e:
                    logger.warning("TTS callback error (continuing): %s", e)

            yield wrap_up_text

        except Exception as e:
            logger.error("Failed to generate wrap-up: %s", e)
            raise AgentServiceError(f"Failed to generate wrap-up: {e}") from e

    async def end_interview(
        self,
        transcript: Optional[list[dict[str, str]]] = None,
    ) -> str:
        """End interview and generate feedback.

        Args:
            transcript: Optional transcript from Swift CLI. If provided, uses this
                       instead of internal transcript for consistency.

        Returns:
            str: Markdown formatted feedback

        Raises:
            InterviewNotStartedError: If no active interview
            AgentServiceError: If feedback generation fails
        """
        if self._state != SessionState.INTERVIEWING:
            raise InterviewNotStartedError(
                "No active interview to end."
            )

        # Use provided transcript or fall back to internal
        if transcript:
            # Convert Swift format to TranscriptEntry
            from datetime import datetime
            entries = [
                TranscriptEntry(
                    timestamp=datetime.now(),
                    source="interviewer" if t.get("role") in ("assistant", "interviewer") else "user",
                    content=t.get("content", ""),
                )
                for t in transcript
            ]
            logger.info("Using Swift transcript (%d entries)", len(entries))
        else:
            entries = self._transcript
            if not entries:
                raise InterviewNotStartedError(
                    "No active interview or empty transcript."
                )

        logger.info("Ending interview and generating feedback")

        self._state = SessionState.GENERATING_FEEDBACK

        try:
            # Generate feedback from transcript
            result = await self.feedback.generate_feedback(entries)

            if result.score > 0:
                logger.info("Feedback generated with score: %d/10", result.score)
            else:
                logger.info("Feedback generated")

            return result.markdown

        except Exception as e:
            logger.error("Failed to generate feedback: %s", e)
            raise AgentServiceError(f"Failed to generate feedback: {e}") from e

        finally:
            # Return to IDLE state
            self._state = SessionState.IDLE

    # =========================================================================
    # Internal Methods
    # =========================================================================

    async def _process_response(
        self,
        initial_prompt: str,
        is_opening: bool = False,
    ) -> AsyncGenerator[str, None]:
        """Process initial prompt and yield responses.

        Args:
            initial_prompt: The prompt to process
            is_opening: Whether this is the opening statement

        Yields:
            str: Each sentence from the response
        """
        try:
            # For opening, we use the initial prompt directly
            # and initialize the interviewer for future interactions

            if is_opening:
                # Record the opening in transcript
                self._transcript.append(TranscriptEntry(
                    timestamp=datetime.now(),
                    source="interviewer",
                    content=initial_prompt,
                ))

                # Call TTS callback if provided
                if self.on_sentence_ready:
                    try:
                        await self.on_sentence_ready(initial_prompt)
                    except Exception as e:
                        logger.warning("TTS callback error (continuing): %s", e)

                yield initial_prompt

        except Exception as e:
            logger.error("Failed to process response: %s", e)
            raise AgentServiceError(f"Failed to process response: {e}") from e

    # =========================================================================
    # Shutdown
    # =========================================================================

    async def shutdown(self) -> None:
        """Gracefully shutdown the service.

        Clears all state and shuts down underlying agents.
        Safe to call multiple times.
        """
        logger.info("Shutting down AgentService")

        # Clear state
        self._state = SessionState.IDLE
        self._current_question = None
        self._transcript = []
        self._start_time = None

        # Shutdown interviewer
        try:
            await self.interviewer.shutdown()
        except Exception as e:
            logger.warning("Error shutting down interviewer: %s", e)

        logger.info("AgentService shutdown complete")

    # =========================================================================
    # Optional: Context Manager Support
    # =========================================================================

    async def __aenter__(self) -> "AgentService":
        """Enter async context."""
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        """Exit async context and shutdown."""
        await self.shutdown()
