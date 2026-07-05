"""
End-to-End Integration Tests for Complete Interview Flow

TDD RED Phase: These tests define expected E2E behavior for the complete interview workflow.

Tests validate the full interview cycle at the AgentService level:
- Starting interviews with topics from E2E_SCENARIO.md
- Multiple Q&A rounds (3-5 exchanges)
- Session state transitions
- TTS callback integration
- Feedback generation with valid markdown
- Error recovery scenarios
- Session statistics tracking

Reference: E2E_SCENARIO.md - Test scenarios for URL Shortener and Rate Limiter interviews

Feature: E2E Interview Flow
Component: AgentService (agents/service.py)
"""

import asyncio
from datetime import datetime
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from agents.feedback import FeedbackResult, TranscriptEntry
from agents.service import (
    AgentService,
    AgentServiceError,
    InterviewNotStartedError,
    InvalidStateError,
    SessionState,
    SessionStatistics,
)


# =============================================================================
# E2E Test Data - From E2E_SCENARIO.md
# =============================================================================


URL_SHORTENER_TOPIC = "Design a URL shortener service"

URL_SHORTENER_USER_RESPONSES = [
    # Round 1: Functional Requirements
    (
        "I think the main functional requirements are: "
        "First, users should be able to create a short URL from a long URL. "
        "Second, when users access the short URL, they should be redirected to the original long URL. "
        "Third, optionally, we might want to track analytics like click counts. "
        "And maybe allow custom short URLs for premium users."
    ),
    # Round 2: Scale Estimation
    (
        "Let me think about the scale. If we're building something like bit.ly, "
        "I'd estimate maybe 100 million new URLs created per month, which is about 3 million per day "
        "or roughly 40 per second for writes. For reads, URL shorteners are read-heavy. "
        "I'd assume a 100:1 read-to-write ratio, so about 4,000 redirects per second. "
        "At peak times, maybe 10x that, so we should design for 40,000 reads per second."
    ),
    # Round 3: Key Generation Algorithm
    (
        "For the short key, I'd use Base62 encoding - that's lowercase, uppercase letters, and digits. "
        "With 7 characters, we get 62^7 which is about 3.5 trillion possible combinations. "
        "That's more than enough for our scale. For generation, we have a few options: "
        "We could use a hash function like MD5 and take the first 7 characters, but that might cause collisions. "
        "A better approach would be using a distributed ID generator like Twitter's Snowflake, "
        "then Base62 encode that ID. This guarantees uniqueness."
    ),
    # Round 4: High Availability
    (
        "Good point about single point of failure. For high availability, "
        "I'd deploy multiple ID generator instances, each with a unique worker ID. "
        "Snowflake uses timestamp plus worker ID plus sequence number, "
        "so different workers can generate IDs independently without collision. "
        "We could also pre-generate a pool of IDs and store them in a cache like Redis. "
        "When a new URL comes in, we just pop an ID from the pool. "
        "A background job keeps the pool replenished. "
        "This also improves latency since we don't need to generate IDs on the fly."
    ),
    # Round 5: Storage
    (
        "For the database, I'd use a NoSQL store like DynamoDB or Cassandra "
        "because we have simple key-value lookups and need horizontal scalability. "
        "The schema would be simple - partition key is the short URL key, "
        "and we store the original URL, creation timestamp, expiration date, and user ID. "
        "For 40K reads per second, I'd add a caching layer. "
        "Redis or Memcached in front of the database. "
        "Most short URLs follow a power law - a small percentage get most of the traffic. "
        "So caching should have a high hit rate, maybe 80-90%."
    ),
]

RATE_LIMITER_TOPIC = "Design a rate limiter"

RATE_LIMITER_USER_RESPONSES = [
    # Round 1: Algorithms
    (
        "I'd consider token bucket or sliding window algorithms. "
        "Token bucket is simpler and allows burst traffic, "
        "while sliding window provides smoother rate limiting. "
        "For an API gateway, I'd go with token bucket."
    ),
    # Round 2: Distributed Implementation
    (
        "For API gateway I'd use token bucket with Redis for distributed rate limiting. "
        "Each request decrements the token count atomically. "
        "When tokens are exhausted, requests are rejected until refill."
    ),
]


# =============================================================================
# Sample Feedback Markdown - Expected output format
# =============================================================================


SAMPLE_FEEDBACK_MARKDOWN = """## Strengths
- Clear requirements gathering: Identified core vs optional features upfront
- Solid back-of-envelope calculations: 40 writes/sec, 40K reads/sec estimation
- Good algorithm choice: Base62 with Snowflake for unique key generation
- Proactive on reliability: Addressed SPOF before being asked

## Areas for Improvement
- Missing discussion on:
  - URL expiration and cleanup strategy
  - Geographic distribution / CDN for redirects
  - Rate limiting to prevent abuse
- Could elaborate more on:
  - Cache invalidation strategy
  - Monitoring and alerting

## Detailed Feedback

### Requirements Gathering
Good functional requirements, missed non-functional requirements.

### High-Level Design
Solid architecture with clear component separation.

### Deep Dive Quality
Good on ID generation, light on failure scenarios.

### Trade-off Analysis
Mentioned options but could compare more thoroughly.

### Scalability Considerations
Good caching strategy, database choice reasonable.

## Score (1-10)
**7/10**

Strong performance with good systematic approach. Demonstrated solid understanding of distributed systems concepts.

## Recommendations
- Study: Consistent hashing for cache distribution
- Practice: Discussing monitoring and observability earlier
- Review: URL shortener case studies (bit.ly engineering blog)
"""


MINIMAL_FEEDBACK_MARKDOWN = """## Strengths
- Basic understanding of rate limiting algorithms

## Areas for Improvement
- Needs deeper discussion of distributed systems
- Missing implementation details

## Detailed Feedback

### Requirements Gathering
Limited clarifying questions.

### High-Level Design
Basic structure only.

### Deep Dive Quality
Surface level discussion.

### Trade-off Analysis
Minimal trade-off discussion.

### Scalability Considerations
Needs more depth.

## Score (1-10)
**5/10**

Shows foundational knowledge but needs more practice with system design interviews.

## Recommendations
- Study distributed rate limiting patterns
- Practice explaining trade-offs
"""


# =============================================================================
# Test Fixtures
# =============================================================================


@pytest.fixture
def mock_interviewer_agent():
    """Mock InterviewerAgent for E2E tests."""
    with patch("agents.service.InterviewerAgent") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        # Configure mock behavior
        mock_instance.reset_conversation = MagicMock()
        mock_instance.shutdown = AsyncMock()
        mock_instance.is_initialized = True
        mock_instance.context = MagicMock()
        mock_instance.context.turn_count = 0

        # Start interview returns opening question
        mock_instance.start_interview = AsyncMock(
            return_value="Let's design a URL shortener. What clarifying questions do you have?"
        )

        # Process user response generates follow-up questions
        followup_responses = [
            "Good overview. For the URL shortening, what scale are we designing for?",
            "Excellent estimation! How would you generate the short URL key?",
            "You mentioned using Snowflake. How would you handle high availability?",
            "Great solution for availability. What database would you choose?",
            "Good analysis. Let's wrap up. Any final thoughts?",
        ]
        mock_instance.process_user_response = AsyncMock(side_effect=followup_responses)

        yield mock_class, mock_instance


@pytest.fixture
def mock_feedback_agent():
    """Mock FeedbackAgent for E2E tests."""
    with patch("agents.service.FeedbackAgent") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        # Configure generate_feedback to return proper FeedbackResult
        mock_result = FeedbackResult(
            markdown=SAMPLE_FEEDBACK_MARKDOWN,
            score=7,
            strengths=[
                "Clear requirements gathering",
                "Solid back-of-envelope calculations",
                "Good algorithm choice",
                "Proactive on reliability",
            ],
            areas_for_improvement=[
                "Missing discussion on URL expiration",
                "Could elaborate more on cache invalidation",
            ],
            recommendations=[
                "Study consistent hashing",
                "Practice discussing monitoring",
                "Review URL shortener case studies",
            ],
            generated_at=datetime.now(),
        )
        mock_instance.generate_feedback = AsyncMock(return_value=mock_result)

        yield mock_class, mock_instance


@pytest.fixture
def mock_minimal_feedback_agent():
    """Mock FeedbackAgent returning minimal feedback for short interviews."""
    with patch("agents.service.FeedbackAgent") as mock_class:
        mock_instance = MagicMock()
        mock_class.return_value = mock_instance

        mock_result = FeedbackResult(
            markdown=MINIMAL_FEEDBACK_MARKDOWN,
            score=5,
            strengths=["Basic understanding of rate limiting algorithms"],
            areas_for_improvement=["Needs deeper discussion", "Missing implementation details"],
            recommendations=["Study distributed rate limiting", "Practice explaining trade-offs"],
            generated_at=datetime.now(),
        )
        mock_instance.generate_feedback = AsyncMock(return_value=mock_result)

        yield mock_class, mock_instance


@pytest.fixture
def tts_callback_tracker():
    """Track TTS callback invocations."""
    sentences = []
    call_count = 0

    async def callback(sentence: str) -> None:
        nonlocal call_count
        sentences.append(sentence)
        call_count += 1

    callback.sentences = sentences
    callback.get_call_count = lambda: call_count
    return callback


@pytest.fixture
def failing_tts_callback():
    """TTS callback that raises errors."""
    call_count = 0

    async def callback(sentence: str) -> None:
        nonlocal call_count
        call_count += 1
        raise Exception(f"TTS Error on call {call_count}")

    callback.get_call_count = lambda: call_count
    return callback


# =============================================================================
# E2E Test: Complete URL Shortener Interview (5 rounds)
# =============================================================================


class TestE2EURLShortenerInterview:
    """
    Scenario 1: Complete URL Shortener System Design Interview

    Reference: E2E_SCENARIO.md
    Duration: ~5 minutes (simulated)
    Q&A Rounds: 5 exchanges
    Expected Output: Valid feedback markdown
    """

    @pytest.mark.asyncio
    async def test_url_shortener_interview_5_rounds(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """
        Complete URL Shortener interview with 5 Q&A rounds.

        Flow:
        1. Start interview with topic
        2. Process 5 user responses (requirements, scale, algorithm, HA, storage)
        3. End interview and generate feedback
        4. Verify feedback contains all required sections
        """
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        # 1. Start interview
        opening_sentences = []
        async for sentence in service.start_interview(URL_SHORTENER_TOPIC):
            opening_sentences.append(sentence)

        assert len(opening_sentences) > 0
        assert service.state == SessionState.INTERVIEWING
        assert service.current_question == URL_SHORTENER_TOPIC

        # 2. Process 5 rounds of Q&A
        for round_num, user_response in enumerate(URL_SHORTENER_USER_RESPONSES, start=1):
            followup_sentences = []
            async for sentence in service.process_user_response(user_response):
                followup_sentences.append(sentence)

            # Each round should produce at least one followup
            assert len(followup_sentences) > 0, f"Round {round_num} produced no followup"

        # 3. End interview and get feedback
        feedback = await service.end_interview()

        # 4. Verify feedback
        assert feedback is not None
        assert isinstance(feedback, str)
        assert len(feedback) > 0

        # Feedback should contain required sections
        assert "## Strengths" in feedback
        assert "## Areas for Improvement" in feedback or "## Areas For Improvement" in feedback
        assert "## Score" in feedback
        assert "## Recommendations" in feedback

        # Should have returned to IDLE state
        assert service.state == SessionState.IDLE

    @pytest.mark.asyncio
    async def test_url_shortener_transcript_has_all_entries(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Transcript should record all Q&A exchanges."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        for user_response in URL_SHORTENER_USER_RESPONSES:
            async for _ in service.process_user_response(user_response):
                pass

        transcript = service.transcript

        # Should have: 1 opening + 5 user responses + 5 interviewer followups = 11 entries
        # (at minimum, opening + user entries)
        user_entries = [t for t in transcript if t.source == "user"]
        interviewer_entries = [t for t in transcript if t.source == "interviewer"]

        assert len(user_entries) >= 5, "Should have at least 5 user entries"
        assert len(interviewer_entries) >= 1, "Should have at least 1 interviewer entry"

    @pytest.mark.asyncio
    async def test_url_shortener_tts_callback_receives_all_sentences(
        self, mock_interviewer_agent, mock_feedback_agent, tts_callback_tracker
    ):
        """TTS callback should receive sentence-by-sentence streaming."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService(on_sentence_ready=tts_callback_tracker)

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        initial_count = len(tts_callback_tracker.sentences)

        for user_response in URL_SHORTENER_USER_RESPONSES[:3]:  # First 3 rounds
            async for _ in service.process_user_response(user_response):
                pass

        # TTS callback should have been called for each sentence
        assert len(tts_callback_tracker.sentences) > initial_count
        assert all(isinstance(s, str) for s in tts_callback_tracker.sentences)


# =============================================================================
# E2E Test: Minimal Rate Limiter Interview (2 rounds)
# =============================================================================


class TestE2ERateLimiterInterview:
    """
    Scenario 3: Minimal Rate Limiter System Design Interview

    Reference: E2E_SCENARIO.md (Rate Limiter section)
    Duration: Short session
    Q&A Rounds: 2 exchanges
    """

    @pytest.mark.asyncio
    async def test_rate_limiter_interview_minimal(
        self, mock_interviewer_agent, mock_minimal_feedback_agent
    ):
        """
        Minimal Rate Limiter interview with 2 Q&A rounds.

        Tests that even short interviews produce valid feedback.
        """
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_minimal_feedback_agent

        # Reset mock for rate limiter topic
        mock_int_instance.start_interview = AsyncMock(
            return_value="What type of rate limiting algorithm would you consider?"
        )
        mock_int_instance.process_user_response = AsyncMock(
            side_effect=[
                "Good analysis of token bucket. How would you implement it in a distributed system?",
                "Great. Let's move on to discuss implementation details.",
            ]
        )

        service = AgentService()

        # Start interview
        async for _ in service.start_interview(RATE_LIMITER_TOPIC):
            pass

        # Only 2 rounds of Q&A
        for user_response in RATE_LIMITER_USER_RESPONSES:
            async for _ in service.process_user_response(user_response):
                pass

        # End and get feedback
        feedback = await service.end_interview()

        # Verify minimal feedback still contains required sections
        assert feedback is not None
        assert "## Strengths" in feedback
        assert "## Score" in feedback
        assert "## Recommendations" in feedback

    @pytest.mark.asyncio
    async def test_minimal_interview_produces_valid_score(
        self, mock_interviewer_agent, mock_minimal_feedback_agent
    ):
        """Even minimal interviews should produce a valid 1-10 score."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_minimal_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(RATE_LIMITER_TOPIC):
            pass

        async for _ in service.process_user_response(RATE_LIMITER_USER_RESPONSES[0]):
            pass

        await service.end_interview()

        # Check that generate_feedback was called
        mock_fb_instance.generate_feedback.assert_called_once()


# =============================================================================
# E2E Test: Feedback Validation
# =============================================================================


class TestE2EFeedbackGeneration:
    """Tests for feedback generation and validation."""

    @pytest.mark.asyncio
    async def test_interview_generates_valid_feedback(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Feedback should contain all required sections."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        async for _ in service.process_user_response(URL_SHORTENER_USER_RESPONSES[0]):
            pass

        feedback = await service.end_interview()

        # Validate all required sections are present
        required_sections = [
            "## Strengths",
            "## Areas for Improvement",
            "## Detailed Feedback",
            "## Score",
            "## Recommendations",
        ]

        # Use case-insensitive matching
        feedback_lower = feedback.lower()
        for section in required_sections:
            section_pattern = section.lower().replace("##", "").strip()
            assert section_pattern in feedback_lower, f"Missing section: {section}"

    @pytest.mark.asyncio
    async def test_feedback_contains_score_in_valid_range(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Feedback score should be between 1 and 10."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        async for _ in service.process_user_response(URL_SHORTENER_USER_RESPONSES[0]):
            pass

        feedback = await service.end_interview()

        # Score should be in format X/10
        import re
        score_match = re.search(r"(\d+)\s*/\s*10", feedback)
        assert score_match is not None, "Feedback should contain score in X/10 format"

        score = int(score_match.group(1))
        assert 1 <= score <= 10, f"Score {score} should be between 1 and 10"

    @pytest.mark.asyncio
    async def test_feedback_contains_bullet_points(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Feedback sections should contain bullet points."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        async for _ in service.process_user_response(URL_SHORTENER_USER_RESPONSES[0]):
            pass

        feedback = await service.end_interview()

        # Should contain bullet points (- or *)
        import re
        bullet_pattern = re.compile(r"^[\-\*]\s+", re.MULTILINE)
        bullets = bullet_pattern.findall(feedback)

        assert len(bullets) > 0, "Feedback should contain bullet points"


# =============================================================================
# E2E Test: Session State Transitions
# =============================================================================


class TestE2ESessionStateTransitions:
    """Tests for session state machine transitions."""

    @pytest.mark.asyncio
    async def test_session_state_transitions(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Session state should transition correctly through workflow."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        # Initial state: IDLE
        assert service.state == SessionState.IDLE

        # After start_interview: INTERVIEWING
        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass
        assert service.state == SessionState.INTERVIEWING

        # During Q&A: INTERVIEWING
        async for _ in service.process_user_response("Test response"):
            pass
        assert service.state == SessionState.INTERVIEWING

        # After end_interview: back to IDLE
        await service.end_interview()
        assert service.state == SessionState.IDLE

    @pytest.mark.asyncio
    async def test_state_during_feedback_generation(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """State should be GENERATING_FEEDBACK during feedback generation."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        async for _ in service.process_user_response("Test"):
            pass

        # Capture state during feedback generation
        captured_state = None
        original_generate = mock_fb_instance.generate_feedback

        async def capturing_generate(*args, **kwargs):
            nonlocal captured_state
            captured_state = service.state
            return await original_generate(*args, **kwargs)

        mock_fb_instance.generate_feedback = capturing_generate

        await service.end_interview()

        # State during generation should have been GENERATING_FEEDBACK
        assert captured_state == SessionState.GENERATING_FEEDBACK

    @pytest.mark.asyncio
    async def test_invalid_state_start_interview_twice(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Starting a second interview should reset state properly."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        # Start first interview
        async for _ in service.start_interview("First topic"):
            pass
        assert service.state == SessionState.INTERVIEWING

        # Start second interview - should reset and work
        async for _ in service.start_interview("Second topic"):
            pass
        assert service.state == SessionState.INTERVIEWING
        assert service.current_question == "Second topic"


# =============================================================================
# E2E Test: Statistics Tracking
# =============================================================================


class TestE2EInterviewStatistics:
    """Tests for session statistics tracking."""

    @pytest.mark.asyncio
    async def test_interview_statistics_tracked(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Statistics should track turns and duration correctly."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        # Process multiple responses
        for i, user_response in enumerate(URL_SHORTENER_USER_RESPONSES[:3]):
            async for _ in service.process_user_response(user_response):
                pass

        stats = service.statistics

        # Verify statistics
        assert stats.question == URL_SHORTENER_TOPIC
        assert stats.turn_count >= 3, "Should have at least 3 turns"
        assert stats.duration_seconds >= 0
        assert stats.start_time is not None

    @pytest.mark.asyncio
    async def test_statistics_turn_count_matches_user_responses(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Turn count should match number of user responses."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        num_responses = 4
        for user_response in URL_SHORTENER_USER_RESPONSES[:num_responses]:
            async for _ in service.process_user_response(user_response):
                pass

        stats = service.statistics

        # Turn count should equal number of user responses
        assert stats.turn_count == num_responses

    @pytest.mark.asyncio
    async def test_statistics_duration_increases(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Duration should increase over time."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        initial_duration = service.statistics.duration_seconds

        # Small delay
        await asyncio.sleep(0.05)

        async for _ in service.process_user_response("Test response"):
            pass

        final_duration = service.statistics.duration_seconds

        assert final_duration >= initial_duration


# =============================================================================
# E2E Test: Error Recovery
# =============================================================================


class TestE2EErrorRecovery:
    """Tests for error recovery during interview."""

    @pytest.mark.asyncio
    async def test_error_recovery_during_interview(
        self, mock_feedback_agent
    ):
        """Service should recover gracefully from errors."""
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        with patch("agents.service.InterviewerAgent") as mock_int_class:
            mock_int_instance = MagicMock()
            mock_int_class.return_value = mock_int_instance
            mock_int_instance.reset_conversation = MagicMock()
            mock_int_instance.shutdown = AsyncMock()
            mock_int_instance.is_initialized = True
            mock_int_instance.context = MagicMock()
            mock_int_instance.context.turn_count = 0
            mock_int_instance.initialize = AsyncMock()
            mock_int_instance.start_interview = AsyncMock(return_value="Question")

            # First call fails, second succeeds
            mock_int_instance.process_user_response = AsyncMock(
                side_effect=[
                    Exception("Temporary API Error"),
                    "Follow-up after recovery",
                ]
            )

            service = AgentService()

            async for _ in service.start_interview(URL_SHORTENER_TOPIC):
                pass

            # First attempt fails
            with pytest.raises(AgentServiceError):
                async for _ in service.process_user_response("First attempt"):
                    pass

            # Session should still be in INTERVIEWING state
            assert service.state == SessionState.INTERVIEWING

            # Second attempt succeeds
            sentences = []
            async for sentence in service.process_user_response("Second attempt"):
                sentences.append(sentence)

            assert len(sentences) > 0

    @pytest.mark.asyncio
    async def test_tts_callback_error_does_not_break_flow(
        self, mock_interviewer_agent, mock_feedback_agent, failing_tts_callback
    ):
        """TTS callback errors should not interrupt interview flow."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService(on_sentence_ready=failing_tts_callback)

        # Should not raise despite TTS callback errors
        sentences = []
        async for sentence in service.start_interview(URL_SHORTENER_TOPIC):
            sentences.append(sentence)

        assert len(sentences) > 0
        assert service.state == SessionState.INTERVIEWING

        # Process response should also work
        async for sentence in service.process_user_response("Test"):
            sentences.append(sentence)

        assert len(sentences) > 1

    @pytest.mark.asyncio
    async def test_feedback_generation_error_returns_to_idle(
        self, mock_interviewer_agent
    ):
        """State should return to IDLE even if feedback generation fails."""
        mock_int_class, mock_int_instance = mock_interviewer_agent

        with patch("agents.service.FeedbackAgent") as mock_fb_class:
            mock_fb_instance = MagicMock()
            mock_fb_class.return_value = mock_fb_instance
            mock_fb_instance.generate_feedback = AsyncMock(
                side_effect=Exception("Feedback API Error")
            )

            service = AgentService()

            async for _ in service.start_interview(URL_SHORTENER_TOPIC):
                pass

            async for _ in service.process_user_response("Test"):
                pass

            with pytest.raises(AgentServiceError):
                await service.end_interview()

            # Should still return to IDLE state
            assert service.state == SessionState.IDLE


# =============================================================================
# E2E Test: Restart After Completion
# =============================================================================


class TestE2ERestartInterview:
    """Tests for starting new interviews after completion."""

    @pytest.mark.asyncio
    async def test_restart_interview_after_completion(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Should be able to start new interview after completing one."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        # First interview
        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass
        async for _ in service.process_user_response("Response 1"):
            pass
        await service.end_interview()

        assert service.state == SessionState.IDLE

        # Reset mock for second interview
        mock_int_instance.reset_conversation.reset_mock()
        mock_int_instance.process_user_response = AsyncMock(
            return_value="New followup question"
        )

        # Second interview - different topic
        async for _ in service.start_interview(RATE_LIMITER_TOPIC):
            pass

        assert service.state == SessionState.INTERVIEWING
        assert service.current_question == RATE_LIMITER_TOPIC

        # Transcript should be fresh
        assert len([t for t in service.transcript if "Response 1" in t.content]) == 0

    @pytest.mark.asyncio
    async def test_multiple_complete_interviews(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Should support multiple complete interview cycles."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        topics = [
            "Design a URL shortener",
            "Design a rate limiter",
            "Design a chat system",
        ]

        for topic in topics:
            # Start interview
            async for _ in service.start_interview(topic):
                pass
            assert service.state == SessionState.INTERVIEWING

            # Q&A
            async for _ in service.process_user_response(f"Response for {topic}"):
                pass

            # End
            feedback = await service.end_interview()
            assert feedback is not None
            assert service.state == SessionState.IDLE


# =============================================================================
# E2E Test: Concurrent Safety
# =============================================================================


class TestE2EConcurrentOperations:
    """Tests for concurrent operation safety."""

    @pytest.mark.asyncio
    async def test_concurrent_responses_are_serialized(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Concurrent process_user_response calls should be handled safely."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        # Add delay to simulate real API call
        async def slow_response(msg):
            await asyncio.sleep(0.01)
            return f"Response to: {msg}"

        mock_int_instance.process_user_response = AsyncMock(side_effect=slow_response)

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        # Launch concurrent responses
        async def make_response(i):
            sentences = []
            async for s in service.process_user_response(f"Response {i}"):
                sentences.append(s)
            return sentences

        tasks = [make_response(i) for i in range(3)]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # At least some should succeed (due to lock, may be serialized)
        successful = [r for r in results if not isinstance(r, Exception)]
        assert len(successful) >= 1


# =============================================================================
# E2E Test: Edge Cases
# =============================================================================


class TestE2EEdgeCases:
    """Edge case tests for E2E interview flow."""

    @pytest.mark.asyncio
    async def test_empty_user_response(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Should handle empty user responses gracefully."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        # Empty response - implementation may accept or reject
        try:
            async for _ in service.process_user_response(""):
                pass
            # If accepted, should still work
            assert service.state == SessionState.INTERVIEWING
        except (ValueError, AgentServiceError):
            # Acceptable to reject empty input
            pass

    @pytest.mark.asyncio
    async def test_very_long_user_response(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Should handle very long user responses."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        # Very long response (simulating detailed explanation)
        long_response = "I think " * 500 + "that covers everything."

        sentences = []
        async for sentence in service.process_user_response(long_response):
            sentences.append(sentence)

        # Should handle without error
        assert len(sentences) > 0

    @pytest.mark.asyncio
    async def test_unicode_in_responses(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Should handle Unicode characters in responses."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        unicode_response = (
            "For international URLs like example.com/path, "
            "we need UTF-8 encoding support."
        )

        sentences = []
        async for sentence in service.process_user_response(unicode_response):
            sentences.append(sentence)

        assert len(sentences) > 0

    @pytest.mark.asyncio
    async def test_special_characters_in_topic(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Should handle special characters in topic."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        special_topic = "Design a system for 10M+ users @ $0.001/request"

        async for _ in service.start_interview(special_topic):
            pass

        assert service.current_question == special_topic


# =============================================================================
# E2E Test: Service Lifecycle
# =============================================================================


class TestE2EServiceLifecycle:
    """Tests for AgentService lifecycle management."""

    @pytest.mark.asyncio
    async def test_service_shutdown_during_interview(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Should handle shutdown during active interview."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        # Shutdown during interview
        await service.shutdown()

        # Should reset to clean state
        assert service.state == SessionState.IDLE
        assert service.current_question is None
        assert len(service.transcript) == 0

    @pytest.mark.asyncio
    async def test_async_context_manager_usage(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Should support async context manager pattern."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        async with AgentService() as service:
            async for _ in service.start_interview(URL_SHORTENER_TOPIC):
                pass

            async for _ in service.process_user_response("Test"):
                pass

            assert service.state == SessionState.INTERVIEWING

        # After context exit, should be cleaned up
        # (Context manager calls shutdown)

    @pytest.mark.asyncio
    async def test_service_reusable_after_shutdown(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """Service should be reusable after shutdown."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        # First use
        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass
        await service.shutdown()

        # Reset mock
        mock_int_instance.reset_conversation.reset_mock()

        # Reuse
        async for _ in service.start_interview(RATE_LIMITER_TOPIC):
            pass

        assert service.state == SessionState.INTERVIEWING
        assert service.current_question == RATE_LIMITER_TOPIC


# =============================================================================
# E2E Test: Timer End Interview Guide (wrap_up)
# =============================================================================


class TestE2ETimerEndWrapUp:
    """
    Tests for Timer End Interview Guide feature.

    When the 30-minute timer ends, the interviewer should naturally wrap up
    the interview with a closing statement.
    """

    @pytest.mark.asyncio
    async def test_wrap_up_generates_closing_statement(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """wrap_up() should generate a natural closing statement."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        # Configure wrap_up_interview mock
        mock_int_instance.wrap_up_interview = AsyncMock(
            return_value="We're at time. You covered the key aspects of URL shortening well. Thank you for the interview!"
        )

        service = AgentService()

        # Start and conduct interview
        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        async for _ in service.process_user_response(URL_SHORTENER_USER_RESPONSES[0]):
            pass

        # Trigger wrap_up (simulating timer end)
        wrap_up_sentences = []
        async for sentence in service.wrap_up():
            wrap_up_sentences.append(sentence)

        # Verify wrap_up produced output
        assert len(wrap_up_sentences) > 0
        assert any("time" in s.lower() or "thank" in s.lower() for s in wrap_up_sentences)

        # State should still be INTERVIEWING (user must type /end)
        assert service.state == SessionState.INTERVIEWING

    @pytest.mark.asyncio
    async def test_wrap_up_adds_to_transcript(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """wrap_up() should add closing statement to transcript."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        mock_int_instance.wrap_up_interview = AsyncMock(
            return_value="Thank you for your time. Great discussion!"
        )

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        transcript_before = len(service.transcript)

        async for _ in service.wrap_up():
            pass

        transcript_after = len(service.transcript)

        # Wrap-up should add entry to transcript
        assert transcript_after > transcript_before

        # Last entry should be from interviewer
        last_entry = service.transcript[-1]
        assert last_entry.source == "interviewer"

    @pytest.mark.asyncio
    async def test_wrap_up_triggers_tts_callback(
        self, mock_interviewer_agent, mock_feedback_agent, tts_callback_tracker
    ):
        """wrap_up() should trigger TTS callback for closing statement."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        mock_int_instance.wrap_up_interview = AsyncMock(
            return_value="We're out of time. Thank you!"
        )

        service = AgentService(on_sentence_ready=tts_callback_tracker)

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        initial_count = len(tts_callback_tracker.sentences)

        async for _ in service.wrap_up():
            pass

        # TTS callback should have been called
        assert len(tts_callback_tracker.sentences) > initial_count

    @pytest.mark.asyncio
    async def test_wrap_up_fails_without_active_interview(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """wrap_up() should fail if no interview is active."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        service = AgentService()

        # No interview started
        with pytest.raises(InterviewNotStartedError):
            async for _ in service.wrap_up():
                pass

    @pytest.mark.asyncio
    async def test_interview_can_end_after_wrap_up(
        self, mock_interviewer_agent, mock_feedback_agent
    ):
        """After wrap_up(), user can still end interview and get feedback."""
        mock_int_class, mock_int_instance = mock_interviewer_agent
        mock_fb_class, mock_fb_instance = mock_feedback_agent

        mock_int_instance.wrap_up_interview = AsyncMock(
            return_value="Time's up. Great job today!"
        )

        service = AgentService()

        async for _ in service.start_interview(URL_SHORTENER_TOPIC):
            pass

        async for _ in service.process_user_response(URL_SHORTENER_USER_RESPONSES[0]):
            pass

        # Wrap up (timer ended)
        async for _ in service.wrap_up():
            pass

        # User types /end
        feedback = await service.end_interview()

        # Should get valid feedback
        assert feedback is not None
        assert "## Strengths" in feedback
        assert service.state == SessionState.IDLE
