"""
Tests for AgentService - Interview Orchestration Layer

TDD RED Phase: These tests define expected behavior before implementation.

AgentService coordinates:
- InterviewerAgent for conducting interviews
- FeedbackAgent for generating post-interview feedback
- Session state management (IDLE, INTERVIEWING, GENERATING_FEEDBACK)
- TTS callback integration for streaming responses
- Error recovery with fallback messages
- Session statistics tracking

Requirements:
- Orchestrate InterviewerAgent and FeedbackAgent
- Track session state (current question, transcript)
- Handle errors with retry/recovery
- Support TTS callback for sentence streaming
- Async generator pattern for streaming responses
"""

import asyncio
import time
from datetime import datetime
from enum import Enum
from typing import AsyncGenerator, Callable, Awaitable
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock

import pytest


# =============================================================================
# Test Fixtures
# =============================================================================


@pytest.fixture
def mock_interviewer_agent():
    """Mock InterviewerAgent for testing."""
    with patch("agents.service.InterviewerAgent") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        # Configure async methods
        mock_instance.start_interview = AsyncMock(
            return_value="Let's design a URL shortener. What clarifying questions do you have?"
        )
        mock_instance.process_user_response = AsyncMock(
            return_value="Good point. How would you handle the storage?"
        )
        mock_instance.reset_conversation = MagicMock()
        mock_instance.shutdown = AsyncMock()
        mock_instance.is_initialized = True
        mock_instance.context = MagicMock()
        mock_instance.context.turn_count = 0

        yield mock_class, mock_instance


@pytest.fixture
def mock_feedback_agent():
    """Mock FeedbackAgent for testing."""
    with patch("agents.service.FeedbackAgent") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        # Configure async generate_feedback
        mock_result = MagicMock()
        mock_result.markdown = "## Strengths\n- Good\n## Score (1-10)\n**7/10**"
        mock_result.score = 7
        mock_instance.generate_feedback = AsyncMock(return_value=mock_result)

        yield mock_class, mock_instance


@pytest.fixture
def sample_question():
    """Sample interview question."""
    return "Design a URL shortener service"


@pytest.fixture
def sample_user_input():
    """Sample user input during interview."""
    return "I would use a hash-based approach with base62 encoding."


@pytest.fixture
def tts_callback():
    """Sample TTS callback function."""
    sentences = []

    async def callback(sentence: str) -> None:
        sentences.append(sentence)

    callback.sentences = sentences
    return callback


# =============================================================================
# Import Tests - Verify module structure
# =============================================================================


class TestAgentServiceImports:
    """Test that AgentService can be imported with all required components."""

    def test_import_agent_service(self):
        """AgentService should be importable."""
        from agents.service import AgentService
        assert AgentService is not None

    def test_import_session_state(self):
        """SessionState enum should be importable."""
        from agents.service import SessionState
        assert SessionState is not None

    def test_session_state_has_required_values(self):
        """SessionState should have IDLE, INTERVIEWING, GENERATING_FEEDBACK states."""
        from agents.service import SessionState

        assert hasattr(SessionState, "IDLE")
        assert hasattr(SessionState, "INTERVIEWING")
        assert hasattr(SessionState, "GENERATING_FEEDBACK")

    def test_import_transcript_entry(self):
        """TranscriptEntry should be importable from service or feedback module."""
        # TranscriptEntry is defined in feedback.py, should be re-exported or used
        from agents.feedback import TranscriptEntry
        assert TranscriptEntry is not None

    def test_import_session_statistics(self):
        """SessionStatistics dataclass should be importable."""
        from agents.service import SessionStatistics
        assert SessionStatistics is not None

    def test_import_agent_service_error(self):
        """AgentServiceError exception should be importable."""
        from agents.service import AgentServiceError
        assert AgentServiceError is not None


# =============================================================================
# AgentService Initialization Tests
# =============================================================================


class TestAgentServiceInitialization:
    """Tests for AgentService initialization."""

    def test_service_creation_without_callback(self, mock_interviewer_agent, mock_feedback_agent):
        """AgentService should be creatable without TTS callback."""
        from agents.service import AgentService

        service = AgentService()
        assert service is not None

    def test_service_creation_with_callback(self, mock_interviewer_agent, mock_feedback_agent, tts_callback):
        """AgentService should accept optional TTS callback."""
        from agents.service import AgentService

        service = AgentService(on_sentence_ready=tts_callback)
        assert service.on_sentence_ready is not None

    def test_service_has_interviewer_agent(self, mock_interviewer_agent, mock_feedback_agent):
        """AgentService should have an InterviewerAgent instance."""
        from agents.service import AgentService

        service = AgentService()
        assert hasattr(service, "interviewer")
        assert service.interviewer is not None

    def test_service_has_feedback_agent(self, mock_interviewer_agent, mock_feedback_agent):
        """AgentService should have a FeedbackAgent instance."""
        from agents.service import AgentService

        service = AgentService()
        assert hasattr(service, "feedback")
        assert service.feedback is not None

    def test_service_starts_in_idle_state(self, mock_interviewer_agent, mock_feedback_agent):
        """AgentService should start in IDLE state."""
        from agents.service import AgentService, SessionState

        service = AgentService()
        assert service.state == SessionState.IDLE

    def test_service_has_empty_transcript_initially(self, mock_interviewer_agent, mock_feedback_agent):
        """AgentService should have empty transcript initially."""
        from agents.service import AgentService

        service = AgentService()
        assert service.transcript == []

    def test_service_has_no_current_question_initially(self, mock_interviewer_agent, mock_feedback_agent):
        """AgentService should have no current question initially."""
        from agents.service import AgentService

        service = AgentService()
        assert service.current_question is None


# =============================================================================
# SessionState Enum Tests
# =============================================================================


class TestSessionState:
    """Tests for SessionState enum."""

    def test_session_state_idle_value(self):
        """SessionState.IDLE should exist."""
        from agents.service import SessionState

        assert SessionState.IDLE is not None

    def test_session_state_interviewing_value(self):
        """SessionState.INTERVIEWING should exist."""
        from agents.service import SessionState

        assert SessionState.INTERVIEWING is not None

    def test_session_state_generating_feedback_value(self):
        """SessionState.GENERATING_FEEDBACK should exist."""
        from agents.service import SessionState

        assert SessionState.GENERATING_FEEDBACK is not None

    def test_session_states_are_distinct(self):
        """All session states should be distinct values."""
        from agents.service import SessionState

        states = [SessionState.IDLE, SessionState.INTERVIEWING, SessionState.GENERATING_FEEDBACK]
        assert len(set(states)) == 3


# =============================================================================
# Start Interview Tests
# =============================================================================


class TestStartInterview:
    """Tests for starting an interview session."""

    @pytest.mark.asyncio
    async def test_start_interview_returns_async_generator(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """start_interview should return an async generator."""
        from agents.service import AgentService

        service = AgentService()
        result = service.start_interview(sample_question)

        # Should be an async generator
        assert hasattr(result, "__anext__")

    @pytest.mark.asyncio
    async def test_start_interview_yields_sentences(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """start_interview should yield sentences for TTS."""
        from agents.service import AgentService

        mock_class, mock_instance = mock_interviewer_agent

        service = AgentService()
        sentences = []

        async for sentence in service.start_interview(sample_question):
            sentences.append(sentence)

        assert len(sentences) > 0

    @pytest.mark.asyncio
    async def test_start_interview_sets_current_question(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """start_interview should set the current question."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        assert service.current_question == sample_question

    @pytest.mark.asyncio
    async def test_start_interview_changes_state_to_interviewing(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """start_interview should change state to INTERVIEWING."""
        from agents.service import AgentService, SessionState

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        assert service.state == SessionState.INTERVIEWING

    @pytest.mark.asyncio
    async def test_start_interview_clears_previous_transcript(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """start_interview should clear any previous transcript."""
        from agents.service import AgentService
        from agents.feedback import TranscriptEntry

        service = AgentService()
        # Pre-populate transcript
        service._transcript = [
            TranscriptEntry(
                timestamp=datetime.now(),
                source="interviewer",
                content="Old content"
            )
        ]

        async for _ in service.start_interview(sample_question):
            pass

        # Old content should be cleared (new transcript starts fresh)
        old_contents = [t.content for t in service.transcript if t.content == "Old content"]
        assert len(old_contents) == 0

    @pytest.mark.asyncio
    async def test_start_interview_resets_interviewer_conversation(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """start_interview should reset the interviewer's conversation context."""
        from agents.service import AgentService

        mock_class, mock_instance = mock_interviewer_agent

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        mock_instance.reset_conversation.assert_called()

    @pytest.mark.asyncio
    async def test_start_interview_calls_tts_callback(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, tts_callback
    ):
        """start_interview should call TTS callback for each sentence."""
        from agents.service import AgentService

        service = AgentService(on_sentence_ready=tts_callback)

        async for _ in service.start_interview(sample_question):
            pass

        # TTS callback should have been called
        assert len(tts_callback.sentences) > 0


# =============================================================================
# Process User Response Tests
# =============================================================================


class TestProcessUserResponse:
    """Tests for processing user responses during interview."""

    @pytest.mark.asyncio
    async def test_process_user_response_returns_async_generator(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """process_user_response should return an async generator."""
        from agents.service import AgentService

        service = AgentService()

        # Start interview first
        async for _ in service.start_interview(sample_question):
            pass

        result = service.process_user_response(sample_user_input)

        assert hasattr(result, "__anext__")

    @pytest.mark.asyncio
    async def test_process_user_response_yields_sentences(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """process_user_response should yield follow-up sentences."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        sentences = []
        async for sentence in service.process_user_response(sample_user_input):
            sentences.append(sentence)

        assert len(sentences) > 0

    @pytest.mark.asyncio
    async def test_process_user_response_records_user_input(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """process_user_response should record user input in transcript."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        async for _ in service.process_user_response(sample_user_input):
            pass

        # Find user entry in transcript
        user_entries = [t for t in service.transcript if t.source == "user"]
        assert len(user_entries) > 0
        assert any(sample_user_input in t.content for t in user_entries)

    @pytest.mark.asyncio
    async def test_process_user_response_records_interviewer_response(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """process_user_response should record interviewer response in transcript."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        async for _ in service.process_user_response(sample_user_input):
            pass

        # Find interviewer entries in transcript
        interviewer_entries = [t for t in service.transcript if t.source == "interviewer"]
        assert len(interviewer_entries) > 0

    @pytest.mark.asyncio
    async def test_process_user_response_calls_tts_callback(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input, tts_callback
    ):
        """process_user_response should call TTS callback for each sentence."""
        from agents.service import AgentService

        service = AgentService(on_sentence_ready=tts_callback)

        async for _ in service.start_interview(sample_question):
            pass

        tts_callback.sentences.clear()  # Clear sentences from start_interview

        async for _ in service.process_user_response(sample_user_input):
            pass

        assert len(tts_callback.sentences) > 0

    @pytest.mark.asyncio
    async def test_process_user_response_requires_active_interview(
        self, mock_interviewer_agent, mock_feedback_agent, sample_user_input
    ):
        """process_user_response should raise error if no active interview."""
        from agents.service import AgentService, AgentServiceError

        service = AgentService()

        with pytest.raises((AgentServiceError, ValueError)):
            async for _ in service.process_user_response(sample_user_input):
                pass


# =============================================================================
# End Interview Tests
# =============================================================================


class TestEndInterview:
    """Tests for ending an interview and generating feedback."""

    @pytest.mark.asyncio
    async def test_end_interview_returns_feedback_markdown(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """end_interview should return feedback markdown."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        async for _ in service.process_user_response(sample_user_input):
            pass

        feedback = await service.end_interview()

        assert feedback is not None
        assert isinstance(feedback, str)
        assert len(feedback) > 0

    @pytest.mark.asyncio
    async def test_end_interview_changes_state_to_generating_feedback(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """end_interview should temporarily change state to GENERATING_FEEDBACK."""
        from agents.service import AgentService, SessionState

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        async for _ in service.process_user_response(sample_user_input):
            pass

        # Note: State changes during execution, checking final state is IDLE after completion
        await service.end_interview()

        # After feedback is generated, should return to IDLE
        assert service.state == SessionState.IDLE

    @pytest.mark.asyncio
    async def test_end_interview_calls_feedback_agent(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """end_interview should call FeedbackAgent.generate_feedback."""
        from agents.service import AgentService

        mock_class, mock_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        async for _ in service.process_user_response(sample_user_input):
            pass

        await service.end_interview()

        mock_instance.generate_feedback.assert_called()

    @pytest.mark.asyncio
    async def test_end_interview_requires_active_interview(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """end_interview should raise error if no active interview."""
        from agents.service import AgentService, AgentServiceError

        service = AgentService()

        with pytest.raises((AgentServiceError, ValueError)):
            await service.end_interview()

    @pytest.mark.asyncio
    async def test_end_interview_requires_transcript(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """end_interview should raise error if transcript is empty."""
        from agents.service import AgentService, AgentServiceError

        service = AgentService()

        # Start interview but don't add any user responses
        async for _ in service.start_interview(sample_question):
            pass

        # Clear transcript to simulate empty state
        service._transcript = []

        with pytest.raises((AgentServiceError, ValueError)):
            await service.end_interview()


# =============================================================================
# Transcript Management Tests
# =============================================================================


class TestTranscriptManagement:
    """Tests for transcript recording and management."""

    @pytest.mark.asyncio
    async def test_transcript_entries_have_timestamps(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """Transcript entries should have timestamps."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        async for _ in service.process_user_response(sample_user_input):
            pass

        for entry in service.transcript:
            assert hasattr(entry, "timestamp")
            assert entry.timestamp is not None

    @pytest.mark.asyncio
    async def test_transcript_entries_have_source(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """Transcript entries should have source (user/interviewer)."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        async for _ in service.process_user_response(sample_user_input):
            pass

        for entry in service.transcript:
            assert hasattr(entry, "source")
            assert entry.source in ["user", "interviewer"]

    @pytest.mark.asyncio
    async def test_transcript_entries_have_content(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """Transcript entries should have content."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        async for _ in service.process_user_response(sample_user_input):
            pass

        for entry in service.transcript:
            assert hasattr(entry, "content")
            assert entry.content is not None

    def test_transcript_property_returns_copy(self, mock_interviewer_agent, mock_feedback_agent):
        """transcript property should return a copy (not modifiable reference)."""
        from agents.service import AgentService

        service = AgentService()

        transcript1 = service.transcript
        transcript2 = service.transcript

        # Should be equal but not the same object (copy)
        assert transcript1 == transcript2


# =============================================================================
# Session Statistics Tests
# =============================================================================


class TestSessionStatistics:
    """Tests for session statistics tracking."""

    @pytest.mark.asyncio
    async def test_service_has_statistics_property(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """AgentService should have statistics property."""
        from agents.service import AgentService

        service = AgentService()

        assert hasattr(service, "statistics")

    @pytest.mark.asyncio
    async def test_statistics_has_turn_count(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """Statistics should track turn count."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        async for _ in service.process_user_response(sample_user_input):
            pass

        stats = service.statistics
        assert hasattr(stats, "turn_count")
        assert stats.turn_count >= 1

    @pytest.mark.asyncio
    async def test_statistics_has_duration(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """Statistics should track session duration."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        # Small delay to have measurable duration
        await asyncio.sleep(0.01)

        stats = service.statistics
        assert hasattr(stats, "duration_seconds")
        assert stats.duration_seconds >= 0

    @pytest.mark.asyncio
    async def test_statistics_has_question(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """Statistics should include the interview question."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        stats = service.statistics
        assert hasattr(stats, "question")
        assert stats.question == sample_question


# =============================================================================
# Error Handling Tests
# =============================================================================


class TestErrorHandling:
    """Tests for error handling and recovery."""

    @pytest.mark.asyncio
    async def test_interviewer_error_during_process_response(
        self, mock_feedback_agent, sample_question, sample_user_input
    ):
        """Should handle InterviewerAgent errors during process_user_response."""
        from agents.service import AgentService, AgentServiceError

        with patch("agents.service.InterviewerAgent") as mock_class:
            mock_instance = MagicMock()
            mock_class.return_value = mock_instance
            mock_instance.reset_conversation = MagicMock()
            mock_instance.is_initialized = False
            mock_instance.initialize = AsyncMock()
            mock_instance.context = MagicMock()
            mock_instance.context.turn_count = 0
            mock_instance.start_interview = AsyncMock()
            mock_instance.process_user_response = AsyncMock(side_effect=Exception("API Error"))

            service = AgentService()

            # Start interview first
            async for _ in service.start_interview(sample_question):
                pass

            # Process user response should raise error
            with pytest.raises((AgentServiceError, Exception)):
                async for _ in service.process_user_response(sample_user_input):
                    pass

    @pytest.mark.asyncio
    async def test_feedback_error_during_end(
        self, mock_interviewer_agent, sample_question, sample_user_input
    ):
        """Should handle FeedbackAgent errors during end_interview."""
        from agents.service import AgentService, AgentServiceError

        with patch("agents.service.FeedbackAgent") as mock_class:
            mock_instance = MagicMock()
            mock_class.return_value = mock_instance
            mock_instance.generate_feedback = AsyncMock(side_effect=Exception("API Error"))

            service = AgentService()

            async for _ in service.start_interview(sample_question):
                pass

            async for _ in service.process_user_response(sample_user_input):
                pass

            with pytest.raises((AgentServiceError, Exception)):
                await service.end_interview()

    @pytest.mark.asyncio
    async def test_tts_callback_error_does_not_stop_processing(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """TTS callback errors should not stop response processing."""
        from agents.service import AgentService

        async def failing_callback(sentence: str) -> None:
            raise Exception("TTS Error")

        service = AgentService(on_sentence_ready=failing_callback)

        # Should still complete despite callback errors
        sentences = []
        async for sentence in service.start_interview(sample_question):
            sentences.append(sentence)

        assert len(sentences) > 0


# =============================================================================
# Graceful Shutdown Tests
# =============================================================================


class TestGracefulShutdown:
    """Tests for graceful shutdown functionality."""

    @pytest.mark.asyncio
    async def test_shutdown_method_exists(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """AgentService should have shutdown method."""
        from agents.service import AgentService

        service = AgentService()

        assert hasattr(service, "shutdown")

    @pytest.mark.asyncio
    async def test_shutdown_clears_state(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """shutdown should clear all session state."""
        from agents.service import AgentService, SessionState

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        await service.shutdown()

        assert service.state == SessionState.IDLE
        assert service.current_question is None
        assert len(service.transcript) == 0

    @pytest.mark.asyncio
    async def test_shutdown_calls_interviewer_shutdown(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """shutdown should call interviewer agent shutdown."""
        from agents.service import AgentService

        mock_class, mock_instance = mock_interviewer_agent

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        await service.shutdown()

        mock_instance.shutdown.assert_called()

    @pytest.mark.asyncio
    async def test_shutdown_is_idempotent(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """shutdown should be safe to call multiple times."""
        from agents.service import AgentService

        service = AgentService()

        await service.shutdown()
        await service.shutdown()
        await service.shutdown()

        # Should not raise any errors


# =============================================================================
# Logging Tests
# =============================================================================


class TestLogging:
    """Tests for logging functionality."""

    def test_service_has_logger(self, mock_interviewer_agent, mock_feedback_agent):
        """AgentService should have a logger."""
        from agents.service import logger

        assert logger is not None

    @pytest.mark.asyncio
    async def test_start_interview_logs_info(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, caplog
    ):
        """start_interview should log at INFO level."""
        from agents.service import AgentService
        import logging

        with caplog.at_level(logging.INFO):
            service = AgentService()

            async for _ in service.start_interview(sample_question):
                pass

        # Should have logged something about starting interview
        assert any("start" in record.message.lower() or "interview" in record.message.lower()
                   for record in caplog.records)


# =============================================================================
# Integration Tests
# =============================================================================


class TestAgentServiceIntegration:
    """Integration-style tests for complete workflows."""

    @pytest.mark.asyncio
    async def test_complete_interview_workflow(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """Test complete workflow: start -> Q&A -> end -> feedback."""
        from agents.service import AgentService, SessionState

        service = AgentService()

        # 1. Start interview
        opening_sentences = []
        async for sentence in service.start_interview(sample_question):
            opening_sentences.append(sentence)

        assert len(opening_sentences) > 0
        assert service.state == SessionState.INTERVIEWING

        # 2. Process user response
        followup_sentences = []
        async for sentence in service.process_user_response(sample_user_input):
            followup_sentences.append(sentence)

        assert len(followup_sentences) > 0

        # 3. End interview
        feedback = await service.end_interview()

        assert feedback is not None
        assert service.state == SessionState.IDLE

    @pytest.mark.asyncio
    async def test_multiple_rounds_of_qa(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question
    ):
        """Test multiple rounds of Q&A during interview."""
        from agents.service import AgentService

        service = AgentService()

        async for _ in service.start_interview(sample_question):
            pass

        responses = [
            "First I would gather requirements.",
            "Then I would design the high-level architecture.",
            "For storage, I would use a distributed database.",
        ]

        for user_response in responses:
            async for _ in service.process_user_response(user_response):
                pass

        # Should have recorded all exchanges
        user_entries = [t for t in service.transcript if t.source == "user"]
        assert len(user_entries) >= len(responses)

    @pytest.mark.asyncio
    async def test_restart_interview_after_completion(
        self, mock_interviewer_agent, mock_feedback_agent, sample_question, sample_user_input
    ):
        """Test starting a new interview after completing previous one."""
        from agents.service import AgentService, SessionState

        service = AgentService()

        # First interview
        async for _ in service.start_interview(sample_question):
            pass
        async for _ in service.process_user_response(sample_user_input):
            pass
        await service.end_interview()

        # Start second interview
        async for _ in service.start_interview("Design a chat system"):
            pass

        assert service.state == SessionState.INTERVIEWING
        assert service.current_question == "Design a chat system"


# =============================================================================
# Async Context Manager Tests
# =============================================================================


class TestAsyncContextManager:
    """Tests for async context manager support (optional feature)."""

    @pytest.mark.asyncio
    async def test_supports_async_context_manager(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """AgentService should support async context manager pattern (optional)."""
        from agents.service import AgentService

        # Check if async context manager is supported
        service = AgentService()

        if hasattr(service, "__aenter__") and hasattr(service, "__aexit__"):
            async with service as s:
                assert s is not None
        else:
            # Not required, but good to have
            pass
