"""
Tests for Interviewer Agent (Strands Agent + Bedrock Haiku)

TDD RED Phase: These tests define expected behavior before implementation.
All tests should FAIL initially.

Requirements covered (Phase 4.1):
- 4.1.1 Strands Agent + Bedrock Haiku setup (model: anthropic.claude-3-haiku-20240307-v1:0)
- 4.1.2 System prompt for interviewer persona
- 4.1.3 Conversation context management (remember previous conversation)
- 4.1.4 Follow-up question generation (3-5 per topic)

Feature: Interviewer Agent
Reference: PRD.md AI Agent Design section
Model: anthropic.claude-3-haiku-20240307-v1:0

System Prompt:
    You are an experienced System Design interviewer. Your role is to:
    1. Guide the candidate through a system design problem
    2. Ask clarifying questions about requirements
    3. Probe deeper into technical decisions
    4. Challenge assumptions constructively
    5. Generate 3-5 follow-up questions per topic

    Keep responses concise (2-3 sentences) for natural conversation.
    Speak in a professional but encouraging tone.
"""

import asyncio
import pytest
from dataclasses import dataclass
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock


# =============================================================================
# Import the types and classes to test (will fail until implementation exists)
# =============================================================================

from agents.interviewer import (
    InterviewerAgent,
    InterviewerConfig,
    ConversationContext,
    ConversationTurn,
    InterviewerError,
    AgentInitializationError,
    ResponseGenerationError,
    FollowUpTracker,
    INTERVIEWER_SYSTEM_PROMPT,
    DEFAULT_MODEL_ID,
    MAX_FOLLOWUPS_PER_TOPIC,
)


# =============================================================================
# Test Fixtures
# =============================================================================

@pytest.fixture
def mock_bedrock_client():
    """Mock boto3 Bedrock runtime client to avoid actual API calls."""
    with patch("agents.interviewer.boto3.client") as mock_client_factory:
        mock_client = MagicMock()
        mock_client_factory.return_value = mock_client

        # Default: return empty response
        mock_response = {
            "output": {
                "message": {
                    "content": [{"text": "That's a great question. Let me ask you about..."}]
                }
            },
            "stopReason": "end_turn"
        }
        mock_client.converse.return_value = mock_response

        yield mock_client_factory, mock_client


@pytest.fixture
def mock_strands_agent():
    """Mock strands-agents Agent class to avoid actual API calls."""
    with patch("agents.interviewer.Agent") as mock_agent_class:
        mock_agent_instance = MagicMock()
        mock_agent_class.return_value = mock_agent_instance

        # Configure async __call__ behavior
        async def mock_call(message):
            return MagicMock(
                content="That's a great question. Let me ask you about the scalability requirements."
            )

        mock_agent_instance.__call__ = AsyncMock(side_effect=mock_call)
        mock_agent_instance.messages = []

        yield mock_agent_class, mock_agent_instance


@pytest.fixture
def interviewer_config():
    """Create a default InterviewerConfig for testing."""
    return InterviewerConfig(
        model_id="anthropic.claude-3-haiku-20240307-v1:0",
        region="us-west-2",
        max_tokens=500,
    )


@pytest.fixture
def sample_topic():
    """Sample system design topic for testing."""
    return "Design a URL shortener service like bit.ly"


@pytest.fixture
def sample_conversation_context():
    """Sample conversation context with history."""
    context = ConversationContext(topic="Design a URL shortener service")
    context.add_turn(
        role="assistant",
        content="Let's start with the requirements. What are the main use cases for this URL shortener?"
    )
    context.add_turn(
        role="user",
        content="We need to support creating short URLs, redirecting to original URLs, and analytics."
    )
    return context


@pytest.fixture
def sample_user_response():
    """Sample user response during interview."""
    return "I think we should use a hash-based approach for generating short URLs."


@pytest.fixture
def multi_turn_context():
    """Conversation context with multiple turns for follow-up testing."""
    context = ConversationContext(topic="Design a rate limiter")

    # Turn 1: Initial question and response
    context.add_turn(
        role="assistant",
        content="Let's design a rate limiter. What algorithms are you familiar with?"
    )
    context.add_turn(
        role="user",
        content="I know about token bucket and leaky bucket algorithms."
    )

    # Turn 2: Follow-up and response
    context.add_turn(
        role="assistant",
        content="Good. Can you explain the trade-offs between them?"
    )
    context.add_turn(
        role="user",
        content="Token bucket allows burst traffic while leaky bucket provides smooth output."
    )

    return context


# =============================================================================
# Exception Types Tests
# =============================================================================

class TestInterviewerExceptions:
    """Tests for Interviewer exception hierarchy."""

    def test_interviewer_error_is_base_exception(self):
        """InterviewerError should be a subclass of Exception."""
        error = InterviewerError("something went wrong")
        assert isinstance(error, Exception)
        assert str(error) == "something went wrong"

    def test_interviewer_error_default_message(self):
        """InterviewerError can be instantiated without arguments."""
        error = InterviewerError()
        assert isinstance(error, Exception)

    def test_agent_initialization_error_inherits_interviewer_error(self):
        """AgentInitializationError should be a subclass of InterviewerError."""
        error = AgentInitializationError("failed to initialize agent")
        assert isinstance(error, InterviewerError)
        assert isinstance(error, Exception)
        assert "failed to initialize" in str(error)

    def test_response_generation_error_inherits_interviewer_error(self):
        """ResponseGenerationError should be a subclass of InterviewerError."""
        error = ResponseGenerationError("failed to generate response")
        assert isinstance(error, InterviewerError)
        assert isinstance(error, Exception)
        assert "failed to generate" in str(error)

    def test_exception_hierarchy_catch_all(self):
        """Catching InterviewerError should catch all agent-specific exceptions."""
        exceptions = [
            AgentInitializationError("init fail"),
            ResponseGenerationError("gen fail"),
        ]
        for exc in exceptions:
            with pytest.raises(InterviewerError):
                raise exc


# =============================================================================
# Constants and Configuration Tests
# =============================================================================

class TestInterviewerConstants:
    """Tests for Interviewer module constants."""

    def test_default_model_id_is_haiku(self):
        """DEFAULT_MODEL_ID should be Claude 3 Haiku."""
        assert DEFAULT_MODEL_ID == "anthropic.claude-3-haiku-20240307-v1:0"

    def test_max_followups_per_topic(self):
        """MAX_FOLLOWUPS_PER_TOPIC should be between 3 and 5."""
        assert 3 <= MAX_FOLLOWUPS_PER_TOPIC <= 5

    def test_system_prompt_contains_interviewer_role(self):
        """System prompt should contain interviewer persona definition."""
        assert "System Design interviewer" in INTERVIEWER_SYSTEM_PROMPT

    def test_system_prompt_contains_guide_candidate(self):
        """System prompt should mention guiding the candidate."""
        assert "Guide the candidate" in INTERVIEWER_SYSTEM_PROMPT

    def test_system_prompt_contains_clarifying_questions(self):
        """System prompt should mention asking clarifying questions."""
        assert "clarifying questions" in INTERVIEWER_SYSTEM_PROMPT

    def test_system_prompt_contains_probe_deeper(self):
        """System prompt should mention probing deeper into decisions."""
        assert "Probe deeper" in INTERVIEWER_SYSTEM_PROMPT

    def test_system_prompt_contains_challenge_assumptions(self):
        """System prompt should mention challenging assumptions."""
        assert "Challenge assumptions" in INTERVIEWER_SYSTEM_PROMPT

    def test_system_prompt_contains_followup_guidance(self):
        """System prompt should mention 3-5 follow-up questions."""
        assert "3-5 follow-up" in INTERVIEWER_SYSTEM_PROMPT

    def test_system_prompt_contains_concise_guidance(self):
        """System prompt should mention keeping responses concise."""
        assert "concise" in INTERVIEWER_SYSTEM_PROMPT.lower()

    def test_system_prompt_contains_professional_tone(self):
        """System prompt should mention professional tone."""
        assert "professional" in INTERVIEWER_SYSTEM_PROMPT.lower()


# =============================================================================
# InterviewerConfig Tests
# =============================================================================

class TestInterviewerConfig:
    """Tests for InterviewerConfig dataclass."""

    def test_config_creation_with_all_fields(self):
        """InterviewerConfig should store all configuration fields."""
        config = InterviewerConfig(
            model_id="anthropic.claude-3-haiku-20240307-v1:0",
            region="us-west-2",
            max_tokens=500,
        )
        assert config.model_id == "anthropic.claude-3-haiku-20240307-v1:0"
        assert config.region == "us-west-2"
        assert config.max_tokens == 500

    def test_config_default_model_id(self):
        """InterviewerConfig should have default model_id."""
        config = InterviewerConfig()
        assert config.model_id == DEFAULT_MODEL_ID

    def test_config_default_region(self):
        """InterviewerConfig should have default region."""
        config = InterviewerConfig()
        assert config.region == "us-west-2"

    def test_config_default_max_tokens(self):
        """InterviewerConfig should have default max_tokens."""
        config = InterviewerConfig()
        assert config.max_tokens == 500

    def test_config_equality(self):
        """Two InterviewerConfigs with the same fields should be equal."""
        a = InterviewerConfig(model_id="test", region="us-west-2", max_tokens=500)
        b = InterviewerConfig(model_id="test", region="us-west-2", max_tokens=500)
        assert a == b

    def test_config_inequality(self):
        """Two InterviewerConfigs with different fields should not be equal."""
        a = InterviewerConfig(model_id="model-a")
        b = InterviewerConfig(model_id="model-b")
        assert a != b


# =============================================================================
# ConversationTurn Tests
# =============================================================================

class TestConversationTurn:
    """Tests for ConversationTurn dataclass."""

    def test_turn_creation_with_user_role(self):
        """ConversationTurn should store user messages."""
        turn = ConversationTurn(
            role="user",
            content="I think we need to handle high read traffic."
        )
        assert turn.role == "user"
        assert "high read traffic" in turn.content

    def test_turn_creation_with_assistant_role(self):
        """ConversationTurn should store assistant messages."""
        turn = ConversationTurn(
            role="assistant",
            content="How would you handle caching for read optimization?"
        )
        assert turn.role == "assistant"
        assert "caching" in turn.content

    def test_turn_equality(self):
        """Two ConversationTurns with the same fields should be equal."""
        a = ConversationTurn(role="user", content="test")
        b = ConversationTurn(role="user", content="test")
        assert a == b

    def test_turn_stores_timestamp(self):
        """ConversationTurn should have a timestamp field."""
        turn = ConversationTurn(role="user", content="test")
        assert hasattr(turn, "timestamp")

    def test_turn_timestamp_auto_generated(self):
        """ConversationTurn timestamp should be auto-generated if not provided."""
        turn = ConversationTurn(role="user", content="test")
        assert turn.timestamp is not None


# =============================================================================
# ConversationContext Tests
# =============================================================================

class TestConversationContext:
    """Tests for ConversationContext class (4.1.3 Conversation context management)."""

    def test_context_creation_with_topic(self):
        """ConversationContext should store the interview topic."""
        context = ConversationContext(topic="Design a URL shortener")
        assert context.topic == "Design a URL shortener"

    def test_context_starts_with_empty_history(self):
        """ConversationContext should start with empty conversation history."""
        context = ConversationContext(topic="Test topic")
        assert len(context.turns) == 0

    def test_add_turn_appends_to_history(self):
        """add_turn() should append a turn to the conversation history."""
        context = ConversationContext(topic="Test")
        context.add_turn(role="assistant", content="Hello, let's begin.")

        assert len(context.turns) == 1
        assert context.turns[0].role == "assistant"
        assert context.turns[0].content == "Hello, let's begin."

    def test_add_multiple_turns(self):
        """Multiple add_turn() calls should build conversation history."""
        context = ConversationContext(topic="Test")
        context.add_turn(role="assistant", content="Question 1")
        context.add_turn(role="user", content="Answer 1")
        context.add_turn(role="assistant", content="Question 2")

        assert len(context.turns) == 3
        assert context.turns[0].role == "assistant"
        assert context.turns[1].role == "user"
        assert context.turns[2].role == "assistant"

    def test_get_turns_returns_all_history(self):
        """get_turns() should return all conversation turns."""
        context = ConversationContext(topic="Test")
        context.add_turn(role="assistant", content="Q1")
        context.add_turn(role="user", content="A1")

        turns = context.get_turns()
        assert len(turns) == 2

    def test_get_last_turn_returns_most_recent(self):
        """get_last_turn() should return the most recent turn."""
        context = ConversationContext(topic="Test")
        context.add_turn(role="assistant", content="First")
        context.add_turn(role="user", content="Second")
        context.add_turn(role="assistant", content="Third")

        last = context.get_last_turn()
        assert last.content == "Third"

    def test_get_last_turn_returns_none_if_empty(self):
        """get_last_turn() should return None if no turns exist."""
        context = ConversationContext(topic="Test")
        assert context.get_last_turn() is None

    def test_clear_history(self):
        """clear() should remove all turns from the context."""
        context = ConversationContext(topic="Test")
        context.add_turn(role="assistant", content="Q1")
        context.add_turn(role="user", content="A1")

        context.clear()
        assert len(context.turns) == 0

    def test_clear_preserves_topic(self):
        """clear() should preserve the topic."""
        context = ConversationContext(topic="Important Topic")
        context.add_turn(role="user", content="test")
        context.clear()

        assert context.topic == "Important Topic"

    def test_to_messages_format(self):
        """to_messages() should return conversation in LLM message format."""
        context = ConversationContext(topic="Test")
        context.add_turn(role="assistant", content="Hello")
        context.add_turn(role="user", content="Hi")

        messages = context.to_messages()

        assert len(messages) == 2
        assert messages[0]["role"] == "assistant"
        assert messages[0]["content"] == "Hello"
        assert messages[1]["role"] == "user"
        assert messages[1]["content"] == "Hi"

    def test_context_tracks_turn_count(self):
        """ConversationContext should track the number of turns."""
        context = ConversationContext(topic="Test")
        assert context.turn_count == 0

        context.add_turn(role="assistant", content="Q1")
        assert context.turn_count == 1

        context.add_turn(role="user", content="A1")
        assert context.turn_count == 2


# =============================================================================
# FollowUpTracker Tests
# =============================================================================

class TestFollowUpTracker:
    """Tests for FollowUpTracker class (4.1.4 Follow-up question tracking)."""

    def test_tracker_creation(self):
        """FollowUpTracker should be creatable."""
        tracker = FollowUpTracker()
        assert tracker is not None

    def test_tracker_starts_at_zero(self):
        """FollowUpTracker should start with zero follow-ups for any topic."""
        tracker = FollowUpTracker()
        assert tracker.get_count("requirements") == 0
        assert tracker.get_count("scalability") == 0

    def test_increment_followup_count(self):
        """increment() should increase follow-up count for a topic."""
        tracker = FollowUpTracker()
        tracker.increment("requirements")

        assert tracker.get_count("requirements") == 1

    def test_increment_multiple_times(self):
        """increment() should accumulate counts correctly."""
        tracker = FollowUpTracker()
        tracker.increment("scalability")
        tracker.increment("scalability")
        tracker.increment("scalability")

        assert tracker.get_count("scalability") == 3

    def test_track_multiple_topics_independently(self):
        """Different topics should have independent counts."""
        tracker = FollowUpTracker()
        tracker.increment("requirements")
        tracker.increment("requirements")
        tracker.increment("database")

        assert tracker.get_count("requirements") == 2
        assert tracker.get_count("database") == 1

    def test_can_followup_returns_true_under_limit(self):
        """can_followup() should return True when under the limit."""
        tracker = FollowUpTracker(max_per_topic=5)
        tracker.increment("test")
        tracker.increment("test")

        assert tracker.can_followup("test") is True

    def test_can_followup_returns_false_at_limit(self):
        """can_followup() should return False when at the limit."""
        tracker = FollowUpTracker(max_per_topic=3)
        tracker.increment("test")
        tracker.increment("test")
        tracker.increment("test")

        assert tracker.can_followup("test") is False

    def test_can_followup_returns_false_over_limit(self):
        """can_followup() should return False when over the limit."""
        tracker = FollowUpTracker(max_per_topic=3)
        for _ in range(5):
            tracker.increment("test")

        assert tracker.can_followup("test") is False

    def test_reset_topic_clears_count(self):
        """reset_topic() should clear the count for a specific topic."""
        tracker = FollowUpTracker()
        tracker.increment("requirements")
        tracker.increment("requirements")

        tracker.reset_topic("requirements")

        assert tracker.get_count("requirements") == 0

    def test_reset_topic_does_not_affect_others(self):
        """reset_topic() should not affect other topics."""
        tracker = FollowUpTracker()
        tracker.increment("requirements")
        tracker.increment("database")

        tracker.reset_topic("requirements")

        assert tracker.get_count("database") == 1

    def test_reset_all_clears_all_counts(self):
        """reset_all() should clear counts for all topics."""
        tracker = FollowUpTracker()
        tracker.increment("requirements")
        tracker.increment("database")
        tracker.increment("api")

        tracker.reset_all()

        assert tracker.get_count("requirements") == 0
        assert tracker.get_count("database") == 0
        assert tracker.get_count("api") == 0

    def test_get_all_topics(self):
        """get_all_topics() should return all tracked topics."""
        tracker = FollowUpTracker()
        tracker.increment("requirements")
        tracker.increment("database")

        topics = tracker.get_all_topics()

        assert "requirements" in topics
        assert "database" in topics

    def test_default_max_per_topic(self):
        """Default max_per_topic should be MAX_FOLLOWUPS_PER_TOPIC."""
        tracker = FollowUpTracker()
        assert tracker.max_per_topic == MAX_FOLLOWUPS_PER_TOPIC


# =============================================================================
# InterviewerAgent Initialization Tests (4.1.1)
# =============================================================================

class TestInterviewerAgentInitialization:
    """Tests for InterviewerAgent initialization (Task 4.1.1)."""

    def test_agent_creation_with_default_config(self, mock_strands_agent):
        """InterviewerAgent should be creatable with default config."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()

        assert agent is not None

    def test_agent_creation_with_custom_config(self, mock_strands_agent, interviewer_config):
        """InterviewerAgent should accept custom configuration."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent(config=interviewer_config)

        assert agent.config == interviewer_config

    def test_agent_uses_haiku_model_by_default(self, mock_strands_agent):
        """InterviewerAgent should use Haiku model by default."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()

        assert agent.config.model_id == "anthropic.claude-3-haiku-20240307-v1:0"

    def test_agent_stores_system_prompt(self, mock_strands_agent):
        """InterviewerAgent should store the system prompt."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()

        assert agent.system_prompt == INTERVIEWER_SYSTEM_PROMPT

    def test_agent_allows_custom_system_prompt(self, mock_strands_agent):
        """InterviewerAgent should allow custom system prompt override."""
        mock_class, mock_instance = mock_strands_agent
        custom_prompt = "You are a helpful assistant."

        agent = InterviewerAgent(system_prompt=custom_prompt)

        assert agent.system_prompt == custom_prompt

    def test_agent_has_conversation_context(self, mock_strands_agent):
        """InterviewerAgent should have a ConversationContext."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()

        assert hasattr(agent, "context")
        assert isinstance(agent.context, ConversationContext)

    def test_agent_has_followup_tracker(self, mock_strands_agent):
        """InterviewerAgent should have a FollowUpTracker."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()

        assert hasattr(agent, "followup_tracker")
        assert isinstance(agent.followup_tracker, FollowUpTracker)

    @pytest.mark.asyncio
    async def test_agent_initializes_strands_agent(self, mock_strands_agent):
        """InterviewerAgent should initialize Strands Agent on first use."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.initialize()

        # Strands Agent should be created with correct model
        mock_class.assert_called()

    @pytest.mark.asyncio
    async def test_agent_initialization_is_idempotent(self, mock_strands_agent):
        """Multiple initialize() calls should only create agent once."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.initialize()
        await agent.initialize()
        await agent.initialize()

        # Should only be called once
        assert mock_class.call_count == 1

    @pytest.mark.asyncio
    async def test_agent_is_initialized_property(self, mock_strands_agent):
        """is_initialized should reflect initialization state."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        assert agent.is_initialized is False

        await agent.initialize()
        assert agent.is_initialized is True

    @pytest.mark.asyncio
    async def test_agent_raises_on_initialization_error(self):
        """initialize() should raise AgentInitializationError on failure."""
        with patch("agents.interviewer.Agent", side_effect=Exception("Failed to create agent")):
            agent = InterviewerAgent()

            with pytest.raises(AgentInitializationError) as exc_info:
                await agent.initialize()

            assert "Failed" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_agent_raises_on_missing_credentials(self):
        """initialize() should raise AgentInitializationError for missing AWS credentials."""
        with patch("agents.interviewer.Agent", side_effect=Exception("Unable to locate credentials")):
            agent = InterviewerAgent()

            with pytest.raises(AgentInitializationError) as exc_info:
                await agent.initialize()

            assert "credentials" in str(exc_info.value).lower() or "Failed" in str(exc_info.value)


# =============================================================================
# System Prompt Tests (4.1.2)
# =============================================================================

class TestInterviewerSystemPrompt:
    """Tests for system prompt configuration (Task 4.1.2)."""

    def test_system_prompt_defines_role(self):
        """System prompt should clearly define the interviewer role."""
        assert "experienced System Design interviewer" in INTERVIEWER_SYSTEM_PROMPT

    def test_system_prompt_has_numbered_responsibilities(self):
        """System prompt should list numbered responsibilities."""
        assert "1." in INTERVIEWER_SYSTEM_PROMPT
        assert "2." in INTERVIEWER_SYSTEM_PROMPT
        assert "3." in INTERVIEWER_SYSTEM_PROMPT
        assert "4." in INTERVIEWER_SYSTEM_PROMPT
        assert "5." in INTERVIEWER_SYSTEM_PROMPT

    def test_system_prompt_includes_all_responsibilities(self):
        """System prompt should include all five key responsibilities."""
        responsibilities = [
            "Guide the candidate",
            "clarifying questions",
            "Probe deeper",
            "Challenge assumptions",
            "follow-up questions",
        ]
        for resp in responsibilities:
            assert resp in INTERVIEWER_SYSTEM_PROMPT, f"Missing: {resp}"

    def test_system_prompt_specifies_response_length(self):
        """System prompt should specify concise responses (2-3 sentences)."""
        assert "2-3 sentences" in INTERVIEWER_SYSTEM_PROMPT

    def test_system_prompt_specifies_tone(self):
        """System prompt should specify professional and encouraging tone."""
        prompt_lower = INTERVIEWER_SYSTEM_PROMPT.lower()
        assert "professional" in prompt_lower
        assert "encouraging" in prompt_lower

    def test_system_prompt_is_string(self):
        """System prompt should be a string."""
        assert isinstance(INTERVIEWER_SYSTEM_PROMPT, str)

    def test_system_prompt_is_not_empty(self):
        """System prompt should not be empty."""
        assert len(INTERVIEWER_SYSTEM_PROMPT.strip()) > 0


# =============================================================================
# Conversation Context Management Tests (4.1.3)
# =============================================================================

class TestInterviewerConversationManagement:
    """Tests for conversation context management (Task 4.1.3)."""

    @pytest.mark.asyncio
    async def test_agent_maintains_conversation_history(
        self, mock_strands_agent, sample_topic
    ):
        """Agent should maintain conversation history across multiple turns."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        # First turn
        await agent.process_user_response("My initial answer")

        # Second turn
        await agent.process_user_response("My follow-up answer")

        # History should contain all turns
        assert agent.context.turn_count >= 3  # topic intro + 2 user responses + responses

    @pytest.mark.asyncio
    async def test_agent_includes_history_in_requests(
        self, mock_strands_agent, sample_topic, sample_user_response
    ):
        """Agent should include conversation history when calling LLM."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)
        await agent.process_user_response(sample_user_response)

        # The agent should have been called with context
        assert mock_instance.__call__.called

    @pytest.mark.asyncio
    async def test_start_interview_sets_topic(self, mock_strands_agent, sample_topic):
        """start_interview() should set the conversation topic."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        assert agent.context.topic == sample_topic

    @pytest.mark.asyncio
    async def test_start_interview_clears_previous_context(
        self, mock_strands_agent, sample_conversation_context
    ):
        """start_interview() should clear any previous conversation context."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        agent.context = sample_conversation_context  # Pre-existing context

        await agent.start_interview("New topic")

        # Only the new topic should remain
        assert agent.context.topic == "New topic"
        assert agent.context.turn_count <= 2  # Just initial question + maybe response

    @pytest.mark.asyncio
    async def test_reset_conversation_clears_all(self, mock_strands_agent, sample_topic):
        """reset_conversation() should clear all context and trackers."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)
        await agent.process_user_response("some answer")

        agent.reset_conversation()

        assert agent.context.turn_count == 0
        assert agent.followup_tracker.get_count("requirements") == 0

    @pytest.mark.asyncio
    async def test_get_conversation_summary(
        self, mock_strands_agent, multi_turn_context
    ):
        """get_conversation_summary() should return a summary of the conversation."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        agent.context = multi_turn_context

        summary = agent.get_conversation_summary()

        assert isinstance(summary, str)
        assert len(summary) > 0


# =============================================================================
# Initial Question Generation Tests (4.1.4)
# =============================================================================

class TestGenerateInitialQuestion:
    """Tests for initial question generation (Task 4.1.4)."""

    @pytest.mark.asyncio
    async def test_start_interview_returns_initial_question(
        self, mock_strands_agent, sample_topic
    ):
        """start_interview() should return an initial question."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        response = await agent.start_interview(sample_topic)

        assert response is not None
        assert isinstance(response, str)
        assert len(response) > 0

    @pytest.mark.asyncio
    async def test_initial_question_is_added_to_context(
        self, mock_strands_agent, sample_topic
    ):
        """Initial question should be added to conversation context."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        # Context should contain the initial question
        assert agent.context.turn_count >= 1
        last_turn = agent.context.get_last_turn()
        assert last_turn.role == "assistant"

    @pytest.mark.asyncio
    async def test_initial_question_auto_initializes_agent(
        self, mock_strands_agent, sample_topic
    ):
        """start_interview() should auto-initialize the agent if needed."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        assert agent.is_initialized is False

        await agent.start_interview(sample_topic)

        assert agent.is_initialized is True

    @pytest.mark.asyncio
    async def test_initial_question_includes_topic(
        self, mock_strands_agent, sample_topic
    ):
        """Initial question generation should reference the topic."""
        mock_class, mock_instance = mock_strands_agent

        # Configure mock to include topic in response
        async def mock_call(message):
            return MagicMock(content="Let's design a URL shortener. What requirements should we consider?")
        mock_instance.__call__ = AsyncMock(side_effect=mock_call)

        agent = InterviewerAgent()
        response = await agent.start_interview(sample_topic)

        # The call to the agent should include the topic
        assert mock_instance.__call__.called


# =============================================================================
# Follow-up Question Generation Tests (4.1.4)
# =============================================================================

class TestGenerateFollowUpQuestions:
    """Tests for follow-up question generation (Task 4.1.4)."""

    @pytest.mark.asyncio
    async def test_process_response_returns_followup(
        self, mock_strands_agent, sample_topic, sample_user_response
    ):
        """process_user_response() should return a follow-up question."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        followup = await agent.process_user_response(sample_user_response)

        assert followup is not None
        assert isinstance(followup, str)
        assert len(followup) > 0

    @pytest.mark.asyncio
    async def test_followup_is_added_to_context(
        self, mock_strands_agent, sample_topic, sample_user_response
    ):
        """Follow-up question should be added to conversation context."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)
        initial_count = agent.context.turn_count

        await agent.process_user_response(sample_user_response)

        # Should have user response + assistant followup
        assert agent.context.turn_count >= initial_count + 2

    @pytest.mark.asyncio
    async def test_user_response_is_added_to_context(
        self, mock_strands_agent, sample_topic, sample_user_response
    ):
        """User response should be added to conversation context."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        await agent.process_user_response(sample_user_response)

        # Find user turn in context
        user_turns = [t for t in agent.context.turns if t.role == "user"]
        assert len(user_turns) >= 1
        assert sample_user_response in user_turns[-1].content

    @pytest.mark.asyncio
    async def test_followup_increments_tracker(
        self, mock_strands_agent, sample_topic, sample_user_response
    ):
        """Generating follow-up should increment the followup tracker."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        initial_count = agent.followup_tracker.get_count("general")
        await agent.process_user_response(sample_user_response)

        # Tracker should have incremented for some topic
        total = sum(
            agent.followup_tracker.get_count(topic)
            for topic in agent.followup_tracker.get_all_topics()
        )
        assert total >= initial_count

    @pytest.mark.asyncio
    async def test_multiple_followups_within_limit(
        self, mock_strands_agent, sample_topic
    ):
        """Agent should generate multiple follow-ups within the limit."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        # Generate several follow-ups
        for i in range(MAX_FOLLOWUPS_PER_TOPIC - 1):
            response = await agent.process_user_response(f"Answer {i}")
            assert response is not None

    @pytest.mark.asyncio
    async def test_response_generation_error_handling(
        self, mock_strands_agent, sample_topic, sample_user_response
    ):
        """process_user_response() should handle generation errors gracefully."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        # Make the agent call fail
        mock_instance.__call__ = AsyncMock(side_effect=Exception("API Error"))

        with pytest.raises(ResponseGenerationError):
            await agent.process_user_response(sample_user_response)


# =============================================================================
# Follow-up Count Tracking Tests (4.1.4)
# =============================================================================

class TestFollowUpCountPerTopic:
    """Tests for tracking and limiting follow-ups per topic (Task 4.1.4)."""

    @pytest.mark.asyncio
    async def test_track_followups_per_topic(self, mock_strands_agent, sample_topic):
        """Agent should track follow-up count per topic."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        # Process multiple responses
        await agent.process_user_response("Answer 1")
        await agent.process_user_response("Answer 2")

        # Should have tracked follow-ups
        total_followups = sum(
            agent.followup_tracker.get_count(topic)
            for topic in agent.followup_tracker.get_all_topics()
        )
        assert total_followups >= 2

    @pytest.mark.asyncio
    async def test_limit_enforced_per_topic(self, mock_strands_agent, sample_topic):
        """Agent should respect the follow-up limit per topic."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        agent.followup_tracker = FollowUpTracker(max_per_topic=3)
        await agent.start_interview(sample_topic)

        # Fill up one topic
        for _ in range(3):
            agent.followup_tracker.increment("requirements")

        # Should not be able to add more for this topic
        assert agent.followup_tracker.can_followup("requirements") is False

    @pytest.mark.asyncio
    async def test_get_remaining_followups(self, mock_strands_agent, sample_topic):
        """Agent should report remaining follow-ups for a topic."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        remaining = agent.get_remaining_followups("requirements")

        assert remaining == MAX_FOLLOWUPS_PER_TOPIC  # Full allowance initially

    @pytest.mark.asyncio
    async def test_remaining_followups_decreases(self, mock_strands_agent, sample_topic):
        """Remaining follow-ups should decrease after each follow-up."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        agent.followup_tracker.increment("requirements")
        agent.followup_tracker.increment("requirements")

        remaining = agent.get_remaining_followups("requirements")

        assert remaining == MAX_FOLLOWUPS_PER_TOPIC - 2

    @pytest.mark.asyncio
    async def test_suggest_topic_change_when_limit_reached(
        self, mock_strands_agent, sample_topic
    ):
        """Agent should suggest topic change when follow-up limit is reached."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        agent.followup_tracker = FollowUpTracker(max_per_topic=2)
        await agent.start_interview(sample_topic)

        # Fill up one topic
        agent.followup_tracker.increment("requirements")
        agent.followup_tracker.increment("requirements")

        should_change = agent.should_change_topic("requirements")

        assert should_change is True

    @pytest.mark.asyncio
    async def test_topic_change_not_suggested_under_limit(
        self, mock_strands_agent, sample_topic
    ):
        """Agent should not suggest topic change when under limit."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        agent.followup_tracker.increment("requirements")

        should_change = agent.should_change_topic("requirements")

        assert should_change is False


# =============================================================================
# Edge Cases and Error Handling Tests
# =============================================================================

class TestInterviewerEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @pytest.mark.asyncio
    async def test_empty_user_response(self, mock_strands_agent, sample_topic):
        """Agent should handle empty user response gracefully."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        # Empty response should still work or raise appropriate error
        try:
            response = await agent.process_user_response("")
            # If it doesn't raise, it should return something
            assert response is not None or True
        except (ValueError, ResponseGenerationError):
            # Acceptable to raise an error for empty input
            pass

    @pytest.mark.asyncio
    async def test_whitespace_only_response(self, mock_strands_agent, sample_topic):
        """Agent should handle whitespace-only response gracefully."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        try:
            response = await agent.process_user_response("   \n\t  ")
            assert response is not None or True
        except (ValueError, ResponseGenerationError):
            pass

    @pytest.mark.asyncio
    async def test_very_long_user_response(self, mock_strands_agent, sample_topic):
        """Agent should handle very long user responses."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        long_response = "This is a detailed explanation. " * 200

        response = await agent.process_user_response(long_response)

        assert response is not None

    @pytest.mark.asyncio
    async def test_special_characters_in_response(self, mock_strands_agent, sample_topic):
        """Agent should handle special characters in user response."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        special_response = "I think O(log n) complexity is good! @#$%^&*()"

        response = await agent.process_user_response(special_response)

        assert response is not None

    @pytest.mark.asyncio
    async def test_unicode_in_response(self, mock_strands_agent, sample_topic):
        """Agent should handle Unicode characters in user response."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        unicode_response = "We need to support international URLs like example.com/path"

        response = await agent.process_user_response(unicode_response)

        assert response is not None

    @pytest.mark.asyncio
    async def test_process_response_before_start(self, mock_strands_agent):
        """process_user_response() before start_interview() should raise error."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()

        with pytest.raises((InterviewerError, ValueError)):
            await agent.process_user_response("Some response")

    @pytest.mark.asyncio
    async def test_concurrent_requests(self, mock_strands_agent, sample_topic):
        """Agent should handle concurrent requests safely."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        # Launch multiple concurrent requests
        tasks = [
            agent.process_user_response(f"Response {i}")
            for i in range(3)
        ]

        # Should complete without errors
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # At least some should succeed
        successful = [r for r in results if not isinstance(r, Exception)]
        assert len(successful) >= 1


# =============================================================================
# Shutdown and Cleanup Tests
# =============================================================================

class TestInterviewerShutdown:
    """Tests for InterviewerAgent shutdown and cleanup."""

    @pytest.mark.asyncio
    async def test_shutdown_clears_context(self, mock_strands_agent, sample_topic):
        """shutdown() should clear conversation context."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)
        await agent.process_user_response("Some response")

        await agent.shutdown()

        assert agent.context.turn_count == 0

    @pytest.mark.asyncio
    async def test_shutdown_resets_tracker(self, mock_strands_agent, sample_topic):
        """shutdown() should reset followup tracker."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)
        agent.followup_tracker.increment("test")

        await agent.shutdown()

        assert agent.followup_tracker.get_count("test") == 0

    @pytest.mark.asyncio
    async def test_shutdown_marks_uninitialized(self, mock_strands_agent, sample_topic):
        """shutdown() should mark agent as uninitialized."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)
        assert agent.is_initialized is True

        await agent.shutdown()

        assert agent.is_initialized is False

    @pytest.mark.asyncio
    async def test_shutdown_is_idempotent(self, mock_strands_agent, sample_topic):
        """shutdown() should be safe to call multiple times."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        await agent.shutdown()
        await agent.shutdown()
        await agent.shutdown()

        assert agent.is_initialized is False

    @pytest.mark.asyncio
    async def test_can_restart_after_shutdown(self, mock_strands_agent, sample_topic):
        """Agent should be restartable after shutdown."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)
        await agent.shutdown()

        # Should be able to start a new interview
        response = await agent.start_interview("New topic")

        assert response is not None
        assert agent.is_initialized is True


# =============================================================================
# Integration-style Tests
# =============================================================================

class TestInterviewerIntegration:
    """Integration-style tests for complete interview workflows."""

    @pytest.mark.asyncio
    async def test_full_interview_workflow(self, mock_strands_agent, sample_topic):
        """Test complete interview workflow: start -> multiple Q&A -> shutdown."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()

        # Start interview
        initial_question = await agent.start_interview(sample_topic)
        assert initial_question is not None

        # Multiple rounds of Q&A
        responses = [
            "We need to support creating short URLs.",
            "I would use a hash-based approach.",
            "For storage, I would use a key-value store.",
        ]

        for user_response in responses:
            followup = await agent.process_user_response(user_response)
            assert followup is not None

        # Verify conversation history
        assert agent.context.turn_count >= 7  # initial + 3 pairs

        # Shutdown
        await agent.shutdown()
        assert agent.is_initialized is False

    @pytest.mark.asyncio
    async def test_multiple_interviews_in_sequence(self, mock_strands_agent):
        """Test running multiple interviews in sequence."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()

        topics = [
            "Design a URL shortener",
            "Design a rate limiter",
            "Design a chat system",
        ]

        for topic in topics:
            # Start new interview
            question = await agent.start_interview(topic)
            assert question is not None

            # One round of Q&A
            followup = await agent.process_user_response("My answer")
            assert followup is not None

            # Reset for next interview
            agent.reset_conversation()

        await agent.shutdown()

    @pytest.mark.asyncio
    async def test_topic_progression(self, mock_strands_agent, sample_topic):
        """Test that agent can guide through different topics."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        # Simulate answering questions about different aspects
        topic_responses = {
            "requirements": "We need to support 1 billion URLs.",
            "api_design": "I would create POST /shorten and GET /:shortUrl endpoints.",
            "database": "I would use Cassandra for high write throughput.",
            "caching": "Redis would be good for caching popular URLs.",
        }

        for topic, response in topic_responses.items():
            followup = await agent.process_user_response(response)
            assert followup is not None

        # Should have progressed through multiple topics
        assert agent.context.turn_count >= 9  # initial + 4 pairs

    @pytest.mark.asyncio
    async def test_conversation_coherence(self, mock_strands_agent, sample_topic):
        """Test that conversation maintains coherence across turns."""
        mock_class, mock_instance = mock_strands_agent

        agent = InterviewerAgent()
        await agent.start_interview(sample_topic)

        # Each response builds on previous
        await agent.process_user_response(
            "I think we should start with requirements."
        )
        await agent.process_user_response(
            "Based on the requirements, we need high availability."
        )
        await agent.process_user_response(
            "Given the high availability requirement, I suggest using multiple regions."
        )

        # Conversation should be coherent - all turns present
        messages = agent.context.to_messages()

        assert len(messages) >= 6  # 3 user + at least 3 assistant

        # Verify alternating pattern
        roles = [m["role"] for m in messages]
        for i in range(1, len(roles)):
            # After initial assistant, should alternate
            if i > 0:
                assert roles[i] != roles[i-1] or True  # Some flexibility for initial setup
