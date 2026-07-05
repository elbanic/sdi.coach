"""
Interviewer Agent - AI-powered System Design Interview conductor

Uses Strands Agent with Amazon Bedrock (Claude Sonnet 4.5) to conduct
natural, conversational system design interviews.

Tasks covered:
- 4.1.1: Strands Agent + Bedrock setup
- 4.1.2: System prompt for natural interviewer persona
- 4.1.3: Conversation context management
- 4.1.4: Adaptive follow-up question generation
"""

from __future__ import annotations

import asyncio
import logging
import os
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from strands import Agent
from strands.models import BedrockModel

# =============================================================================
# Module Constants
# =============================================================================

DEFAULT_MODEL_ID = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
DEFAULT_REGION = "us-west-2"
DEFAULT_MAX_TOKENS = 1024
MAX_FOLLOWUPS_PER_TOPIC = 10

INTERVIEWER_SYSTEM_PROMPT = """
You are an experienced System Design interviewer conducting a natural, conversational interview.

Your approach:
- Ask ONE thoughtful question at a time, then wait for the response
- Adapt your questions based on the candidate's answers
- Probe deeper when answers are vague or surface-level
- Challenge assumptions when appropriate
- Acknowledge good points before moving on

Interview style:
- Be conversational and natural, not robotic or formulaic
- Vary your question types: clarifying, technical deep-dive, trade-offs, edge cases
- NEVER use numbered lists in your responses
- Speak as you would in a real interview - like a senior engineer having a discussion

Flow guidance:
- Start with requirements clarification
- Move to high-level design
- Then dive into specific components
- Explore scalability and trade-offs
- Discuss failure handling and edge cases

Remember: This is a dialogue, not a checklist. React to what the candidate says.
"""

# =============================================================================
# Logger
# =============================================================================

logger = logging.getLogger(__name__)

# =============================================================================
# Exception Classes
# =============================================================================


class InterviewerError(Exception):
    """Base exception for all Interviewer-related errors."""
    pass


class AgentInitializationError(InterviewerError):
    """Raised when the agent fails to initialize."""
    pass


class ResponseGenerationError(InterviewerError):
    """Raised when response generation fails."""
    pass


# =============================================================================
# Configuration
# =============================================================================


@dataclass
class InterviewerConfig:
    """Configuration for InterviewerAgent.

    Attributes:
        model_id: Bedrock model identifier (default: Claude Sonnet 4.5)
        region: AWS region for Bedrock (default: us-west-2)
        max_tokens: Maximum tokens in response (default: 1024)
    """
    model_id: str = field(
        default_factory=lambda: os.environ.get("SDICOACH_INTERVIEWER_MODEL", DEFAULT_MODEL_ID)
    )
    region: str = field(
        default_factory=lambda: os.environ.get("AWS_REGION", DEFAULT_REGION)
    )
    max_tokens: int = DEFAULT_MAX_TOKENS


# =============================================================================
# Conversation Data Classes
# =============================================================================


@dataclass
class ConversationTurn:
    """Represents a single turn in the conversation.

    Attributes:
        role: Either 'user' or 'assistant'
        content: The message content
        timestamp: When this turn was created
    """
    role: str
    content: str
    timestamp: datetime = field(default_factory=datetime.now, compare=False)


class ConversationContext:
    """Manages conversation history and context for the interview.

    Tracks all turns in the conversation, the interview topic,
    and provides methods to serialize the conversation for LLM calls.
    """

    def __init__(self, topic: str = ""):
        """Initialize conversation context.

        Args:
            topic: The system design interview topic
        """
        self.topic = topic
        self._turns: list[ConversationTurn] = []

    @property
    def turns(self) -> list[ConversationTurn]:
        """Return all conversation turns."""
        return self._turns

    @property
    def turn_count(self) -> int:
        """Return the number of turns in the conversation."""
        return len(self._turns)

    def add_turn(self, role: str, content: str) -> None:
        """Add a new turn to the conversation.

        Args:
            role: Either 'user' or 'assistant'
            content: The message content
        """
        turn = ConversationTurn(role=role, content=content)
        self._turns.append(turn)

    def get_turns(self) -> list[ConversationTurn]:
        """Return all conversation turns."""
        return list(self._turns)

    def get_last_turn(self) -> ConversationTurn | None:
        """Return the most recent turn, or None if empty."""
        if not self._turns:
            return None
        return self._turns[-1]

    def clear(self) -> None:
        """Clear all turns but preserve the topic."""
        self._turns = []

    def to_messages(self) -> list[dict[str, str]]:
        """Convert conversation to LLM message format.

        Returns:
            List of message dictionaries with 'role' and 'content' keys
        """
        return [
            {"role": turn.role, "content": turn.content}
            for turn in self._turns
        ]


# =============================================================================
# Follow-up Tracking
# =============================================================================


class FollowUpTracker:
    """Tracks follow-up question counts per topic.

    Ensures we don't exceed the maximum number of follow-ups
    for any single topic (3-5 questions per topic).
    """

    def __init__(self, max_per_topic: int = MAX_FOLLOWUPS_PER_TOPIC):
        """Initialize the tracker.

        Args:
            max_per_topic: Maximum follow-ups allowed per topic
        """
        self.max_per_topic = max_per_topic
        self._counts: dict[str, int] = {}

    def get_count(self, topic: str) -> int:
        """Get current follow-up count for a topic.

        Args:
            topic: The topic to check

        Returns:
            Current count (0 if topic hasn't been tracked)
        """
        return self._counts.get(topic, 0)

    def increment(self, topic: str) -> None:
        """Increment the follow-up count for a topic.

        Args:
            topic: The topic to increment
        """
        self._counts[topic] = self._counts.get(topic, 0) + 1

    def can_followup(self, topic: str) -> bool:
        """Check if more follow-ups are allowed for a topic.

        Args:
            topic: The topic to check

        Returns:
            True if under the limit, False otherwise
        """
        return self.get_count(topic) < self.max_per_topic

    def reset_topic(self, topic: str) -> None:
        """Reset the count for a specific topic.

        Args:
            topic: The topic to reset
        """
        self._counts[topic] = 0

    def reset_all(self) -> None:
        """Reset all topic counts."""
        self._counts = {}

    def get_all_topics(self) -> list[str]:
        """Return all tracked topics.

        Returns:
            List of topic names that have been tracked
        """
        return list(self._counts.keys())


# =============================================================================
# InterviewerAgent
# =============================================================================


class InterviewerAgent:
    """AI-powered System Design Interview conductor.

    Uses Strands Agent with Amazon Bedrock (Claude 3 Haiku) to conduct
    interactive system design interviews with intelligent follow-up
    question generation.

    Example:
        agent = InterviewerAgent()
        question = await agent.start_interview("Design a URL shortener")
        followup = await agent.process_user_response("I would use hashing...")
        await agent.shutdown()
    """

    def __init__(
        self,
        config: InterviewerConfig | None = None,
        system_prompt: str | None = None,
    ):
        """Initialize the InterviewerAgent.

        Args:
            config: Agent configuration (uses defaults if None)
            system_prompt: Custom system prompt (uses default if None)
        """
        self.config = config or InterviewerConfig()
        self.system_prompt = system_prompt or INTERVIEWER_SYSTEM_PROMPT

        # Conversation management
        self.context = ConversationContext()
        self.followup_tracker = FollowUpTracker()

        # Agent state
        self._agent: Agent | None = None
        self._initialized = False
        self._lock = asyncio.Lock()

        logger.info(
            "InterviewerAgent created with model=%s, region=%s",
            self.config.model_id,
            self.config.region,
        )

    @property
    def is_initialized(self) -> bool:
        """Check if the agent has been initialized."""
        return self._initialized

    async def initialize(self) -> None:
        """Initialize the Strands Agent with Bedrock model.

        This is called automatically on first use but can be called
        explicitly for eager initialization.

        Raises:
            AgentInitializationError: If initialization fails
        """
        if self._initialized:
            return

        async with self._lock:
            if self._initialized:
                return

            try:
                logger.info("Initializing Strands Agent...")

                model = BedrockModel(
                    model_id=self.config.model_id,
                    region_name=self.config.region,
                    temperature=0.7,
                )

                self._agent = Agent(
                    model=model,
                    system_prompt=self.system_prompt,
                )

                self._initialized = True
                logger.info("Strands Agent initialized successfully")

            except Exception as e:
                logger.error("Failed to initialize agent: %s", e)
                raise AgentInitializationError(f"Failed to initialize agent: {e}") from e

    async def start_interview(self, topic: str) -> str:
        """Start a new interview session.

        Clears any previous context and generates an initial question
        based on the given topic.

        Args:
            topic: The system design problem to discuss

        Returns:
            Initial question from the interviewer

        Raises:
            AgentInitializationError: If agent fails to initialize
            ResponseGenerationError: If question generation fails
        """
        await self.initialize()

        # Reset context for new interview
        self.context = ConversationContext(topic=topic)
        self.followup_tracker.reset_all()

        logger.info("Starting interview with topic: %s", topic)

        try:
            # Generate initial question
            prompt = f"Let's begin a system design interview. The topic is: {topic}\n\nPlease introduce the problem and ask your first question."

            response = await self._call_agent(prompt)

            # Add assistant response to context
            self.context.add_turn(role="assistant", content=response)

            return response

        except InterviewerError:
            raise
        except Exception as e:
            logger.error("Failed to generate initial question: %s", e)
            raise ResponseGenerationError(f"Failed to generate initial question: {e}") from e

    async def process_user_response(self, user_response: str) -> str:
        """Process user's response and generate a follow-up question.

        Args:
            user_response: The user's answer to the previous question

        Returns:
            Follow-up question from the interviewer

        Raises:
            InterviewerError: If interview hasn't started
            ResponseGenerationError: If follow-up generation fails
        """
        if not self._initialized or self.context.turn_count == 0:
            raise InterviewerError("Interview has not been started. Call start_interview() first.")

        # Add user response to context
        self.context.add_turn(role="user", content=user_response)

        logger.debug("Processing user response: %s...", user_response[:50])

        try:
            # Build context-aware prompt
            messages = self.context.to_messages()

            # Generate follow-up
            response = await self._call_agent(user_response)

            # Add assistant response to context
            self.context.add_turn(role="assistant", content=response)

            # Track follow-up (use 'general' as default topic)
            self.followup_tracker.increment("general")

            return response

        except InterviewerError:
            raise
        except Exception as e:
            logger.error("Failed to generate follow-up: %s", e)
            raise ResponseGenerationError(f"Failed to generate follow-up: {e}") from e

    async def _call_agent(self, message: str) -> str:
        """Call the Strands agent with a message.

        Args:
            message: The message to send to the agent

        Returns:
            Agent's response text

        Raises:
            ResponseGenerationError: If the agent call fails
        """
        if self._agent is None:
            raise InterviewerError("Agent not initialized")

        try:
            # Use explicit __call__ for mock compatibility
            # In production, agent(message) == agent.__call__(message)
            if hasattr(self._agent, "__call__"):
                result = self._agent.__call__(message)
            else:
                result = self._agent(message)

            # Handle async result if needed
            if asyncio.iscoroutine(result):
                result = await result

            # Extract text from response
            if hasattr(result, "content"):
                return str(result.content)
            return str(result)

        except Exception as e:
            logger.error("Agent call failed: %s", e)
            raise ResponseGenerationError(f"Agent call failed: {e}") from e

    def reset_conversation(self) -> None:
        """Reset conversation context and trackers.

        Clears all conversation history and follow-up counts
        without shutting down the agent.
        """
        self.context.clear()
        self.followup_tracker.reset_all()
        logger.info("Conversation reset")

    def get_conversation_summary(self) -> str:
        """Get a summary of the current conversation.

        Returns:
            Human-readable summary of the conversation
        """
        turns = self.context.get_turns()
        if not turns:
            return "No conversation yet."

        summary_parts = [f"Topic: {self.context.topic}"]
        summary_parts.append(f"Turns: {len(turns)}")

        for turn in turns:
            prefix = "Q" if turn.role == "assistant" else "A"
            content_preview = turn.content[:100] + "..." if len(turn.content) > 100 else turn.content
            summary_parts.append(f"{prefix}: {content_preview}")

        return "\n".join(summary_parts)

    def get_remaining_followups(self, topic: str) -> int:
        """Get remaining follow-up allowance for a topic.

        Args:
            topic: The topic to check

        Returns:
            Number of follow-ups still allowed
        """
        return self.followup_tracker.max_per_topic - self.followup_tracker.get_count(topic)

    def should_change_topic(self, topic: str) -> bool:
        """Check if we should move to a different topic.

        Args:
            topic: The current topic

        Returns:
            True if follow-up limit is reached for this topic
        """
        return not self.followup_tracker.can_followup(topic)

    async def wrap_up_interview(self) -> str:
        """Generate a natural closing statement when time is up.

        Called when the 30-minute timer ends. The interviewer should:
        - Briefly acknowledge the time constraint
        - Summarize key points discussed
        - Thank the candidate
        - Keep it concise (2-3 sentences max)

        Returns:
            Natural closing statement from the interviewer

        Raises:
            InterviewerError: If interview hasn't started
            ResponseGenerationError: If wrap-up generation fails
        """
        if not self._initialized or self.context.turn_count == 0:
            raise InterviewerError("Interview has not been started. Call start_interview() first.")

        logger.info("Generating interview wrap-up statement")

        wrap_up_prompt = """The interview time has ended. Please naturally wrap up the interview:
- Briefly acknowledge the time constraint
- Summarize the key points discussed
- Thank the candidate
- Keep it concise (2-3 sentences max)

Do NOT ask any more questions. This is your closing statement."""

        try:
            response = await self._call_agent(wrap_up_prompt)

            # Add to context for completeness
            self.context.add_turn(role="assistant", content=response)

            return response

        except InterviewerError:
            raise
        except Exception as e:
            logger.error("Failed to generate wrap-up: %s", e)
            raise ResponseGenerationError(f"Failed to generate wrap-up: {e}") from e

    async def shutdown(self) -> None:
        """Shutdown the agent and clean up resources.

        Clears all state and marks the agent as uninitialized.
        Safe to call multiple times.
        """
        logger.info("Shutting down InterviewerAgent")

        self.context.clear()
        self.followup_tracker.reset_all()
        self._agent = None
        self._initialized = False

        logger.info("InterviewerAgent shutdown complete")
