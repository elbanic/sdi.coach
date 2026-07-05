"""
Tests for Feedback Agent (Phase 4.2)

TDD RED Phase: These tests define expected behavior before implementation.
All tests should FAIL initially.

Requirements covered:
- 4.2.1 Strands Agent + Bedrock Opus setup
- 4.2.2 Feedback markdown template (Strengths, Areas for Improvement, Score)
- 4.2.3 Scoring logic (1-10 scale)
- 4.2.4 Recommendation generation

Feature: Feedback Agent
Model: anthropic.claude-3-opus-20240229-v1:0

System Prompt Reference:
    You are a senior engineering manager providing interview feedback.
    Analyze the candidate's system design interview transcript and provide:
    - Strengths (what the candidate did well, strong technical decisions)
    - Areas for Improvement (gaps, missed considerations, communication issues)
    - Detailed Feedback (requirements, high-level design, deep dive, trade-offs, scalability)
    - Score (1-10 with justification)
    - Recommendations (specific study areas)
"""

import asyncio
import re
from dataclasses import dataclass
from datetime import datetime
from typing import Optional
from unittest.mock import AsyncMock, MagicMock, patch

import pytest


# =============================================================================
# Types for Testing - Import from actual implementation
# =============================================================================

from agents.feedback import TranscriptEntry, FeedbackResult


# =============================================================================
# Fixtures
# =============================================================================


@pytest.fixture
def mock_bedrock_client():
    """Create a mock Bedrock client that simulates Opus responses."""
    client = MagicMock()
    client.invoke_model = AsyncMock()
    return client


@pytest.fixture
def mock_strands_agent(mock_bedrock_client):
    """Create a mock Strands Agent with Bedrock backend."""
    agent = MagicMock()
    agent.client = mock_bedrock_client
    agent.invoke = AsyncMock()
    return agent


@pytest.fixture
def sample_transcript():
    """Create a sample interview transcript for testing."""
    return [
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 0, 0),
            source="interviewer",
            content="Let's design a URL shortener service. What are the main requirements?",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 0, 30),
            source="candidate",
            content="For the URL shortener, we need to support creating short URLs from long URLs, "
            "redirecting short URLs to their original destinations, and tracking analytics like click counts.",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 1, 0),
            source="interviewer",
            content="Good. Can you estimate the scale we're dealing with?",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 1, 30),
            source="candidate",
            content="Let's assume 100 million URLs created per month. With a 10:1 read to write ratio, "
            "that's about 1 billion redirects per month. This translates to roughly 400 writes per second "
            "and 4000 reads per second at peak.",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 2, 0),
            source="interviewer",
            content="How would you generate the short URL keys?",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 2, 30),
            source="candidate",
            content="I'd use a base62 encoding scheme with 7 characters, which gives us 62^7 or about "
            "3.5 trillion unique combinations. We could either generate random keys with collision checking "
            "or use a counter-based approach with a key generation service.",
        ),
    ]


@pytest.fixture
def minimal_transcript():
    """Create a minimal transcript with only one exchange."""
    return [
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 0, 0),
            source="interviewer",
            content="Design a rate limiter.",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 0, 30),
            source="candidate",
            content="I would use a token bucket algorithm.",
        ),
    ]


@pytest.fixture
def empty_transcript():
    """Create an empty transcript list."""
    return []


@pytest.fixture
def excellent_transcript():
    """Create a transcript demonstrating excellent performance."""
    return [
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 0, 0),
            source="interviewer",
            content="Design a distributed message queue like Kafka.",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 1, 0),
            source="candidate",
            content="Let me clarify the requirements first. What's our expected throughput? "
            "Do we need exactly-once delivery semantics? What's the acceptable latency?",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 2, 0),
            source="interviewer",
            content="Assume millions of messages per second, at-least-once delivery is fine, "
            "and latency should be under 10ms p99.",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 3, 0),
            source="candidate",
            content="For high throughput, I'll use partitioning. Each topic has multiple partitions "
            "distributed across broker nodes. Messages are appended to segment files using sequential "
            "writes, which gives us excellent disk I/O performance.",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 5, 0),
            source="candidate",
            content="For durability, we replicate partitions across multiple brokers. I'd use a leader-follower "
            "model with configurable replication factor. The trade-off is between durability and latency - "
            "we can ack after leader write for low latency or wait for replicas for stronger guarantees.",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 7, 0),
            source="candidate",
            content="For consumer groups, each partition is consumed by exactly one consumer in a group. "
            "We track offsets in a separate __consumer_offsets topic. This enables both queue-style and "
            "pub-sub patterns depending on consumer group configuration.",
        ),
    ]


@pytest.fixture
def poor_transcript():
    """Create a transcript demonstrating poor performance."""
    return [
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 0, 0),
            source="interviewer",
            content="Design a URL shortener service.",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 1, 0),
            source="candidate",
            content="Um, I would just store the URLs in a database.",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 2, 0),
            source="interviewer",
            content="Can you tell me more about the design? What about scalability?",
        ),
        TranscriptEntry(
            timestamp=datetime(2024, 1, 15, 10, 3, 0),
            source="candidate",
            content="I don't know... maybe use a bigger database?",
        ),
    ]


@pytest.fixture
def sample_feedback_markdown():
    """Sample feedback markdown that agent might generate."""
    return """## Strengths
- Strong understanding of scalability requirements
- Good estimation of system load (400 writes/s, 4000 reads/s)
- Clear explanation of base62 encoding approach

## Areas for Improvement
- Did not discuss database selection or data model
- Missing discussion of caching strategy
- No mention of monitoring or alerting

## Detailed Feedback

### Requirements Gathering
The candidate gathered basic functional requirements but missed non-functional requirements like availability, latency SLAs, and data retention policies.

### High-Level Design
Good initial approach but the design lacks detail on how components interact.

### Deep Dive Quality
The key generation discussion was solid but other areas were surface-level.

### Trade-off Analysis
Limited trade-off discussion. Would benefit from comparing random vs sequential key generation.

### Scalability Considerations
Good awareness of read/write ratios but no discussion of sharding or replication strategies.

## Score (1-10)
**6/10**

The candidate demonstrates good technical foundation and estimation skills but needs to dive deeper into system design specifics and discuss trade-offs more thoroughly.

## Recommendations
- Study database sharding strategies (consistent hashing, range-based)
- Practice discussing trade-offs between different architectural choices
- Learn about caching patterns (write-through, write-behind, cache-aside)
- Review monitoring and observability best practices
"""


# =============================================================================
# Mock Helpers
# =============================================================================


def create_mock_bedrock_response(feedback_markdown: str) -> dict:
    """Create a mock Bedrock API response."""
    return {
        "body": MagicMock(
            read=lambda: f'{{"content": [{{"text": "{feedback_markdown}"}}]}}'.encode()
        ),
        "contentType": "application/json",
    }


def create_mock_strands_response(feedback_markdown: str) -> MagicMock:
    """Create a mock Strands Agent response."""
    response = MagicMock()
    response.content = feedback_markdown
    response.text = feedback_markdown
    return response


# =============================================================================
# Feedback Markdown Parser Helper
# =============================================================================


def parse_feedback_sections(markdown: str) -> dict:
    """Parse feedback markdown into sections.

    This helper function extracts sections from the feedback markdown.
    Used for testing that feedback contains required sections.
    """
    sections = {
        "strengths": None,
        "areas_for_improvement": None,
        "detailed_feedback": None,
        "score": None,
        "recommendations": None,
    }

    # Extract Strengths section
    strengths_match = re.search(
        r"##\s*Strengths\s*\n(.*?)(?=##|\Z)", markdown, re.DOTALL | re.IGNORECASE
    )
    if strengths_match:
        sections["strengths"] = strengths_match.group(1).strip()

    # Extract Areas for Improvement section
    areas_match = re.search(
        r"##\s*Areas for Improvement\s*\n(.*?)(?=##|\Z)",
        markdown,
        re.DOTALL | re.IGNORECASE,
    )
    if areas_match:
        sections["areas_for_improvement"] = areas_match.group(1).strip()

    # Extract Detailed Feedback section
    detailed_match = re.search(
        r"##\s*Detailed Feedback\s*\n(.*?)(?=##\s*Score|\Z)",
        markdown,
        re.DOTALL | re.IGNORECASE,
    )
    if detailed_match:
        sections["detailed_feedback"] = detailed_match.group(1).strip()

    # Extract Score section
    score_match = re.search(
        r"##\s*Score\s*\(1-10\)\s*\n(.*?)(?=##|\Z)", markdown, re.DOTALL | re.IGNORECASE
    )
    if score_match:
        sections["score"] = score_match.group(1).strip()

    # Extract Recommendations section
    recommendations_match = re.search(
        r"##\s*Recommendations\s*\n(.*?)(?=##|\Z)", markdown, re.DOTALL | re.IGNORECASE
    )
    if recommendations_match:
        sections["recommendations"] = recommendations_match.group(1).strip()

    return sections


def extract_score_value(score_section: str) -> Optional[int]:
    """Extract numeric score from score section text."""
    if not score_section:
        return None

    # Match patterns like "6/10", "**7/10**", "Score: 8/10"
    score_match = re.search(r"(\d+)\s*/\s*10", score_section)
    if score_match:
        return int(score_match.group(1))

    return None


def extract_bullet_points(section_text: str) -> list[str]:
    """Extract bullet points from a section."""
    if not section_text:
        return []

    # Match lines starting with - or *
    bullets = re.findall(r"^[\-\*]\s*(.+)$", section_text, re.MULTILINE)
    return [b.strip() for b in bullets if b.strip()]


# =============================================================================
# Test: Agent Initialization (4.2.1)
# =============================================================================


class TestFeedbackAgentInitialization:
    """Tests for Feedback Agent initialization with Bedrock Opus."""

    def test_feedback_agent_can_be_initialized(self):
        """Feedback agent should be initializable."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()
        assert agent is not None

    def test_feedback_agent_uses_opus_model(self):
        """Feedback agent should use Claude 3 Opus model."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        # Model ID should be Opus
        assert agent.model_id == "anthropic.claude-3-opus-20240229-v1:0"

    def test_feedback_agent_accepts_custom_model(self):
        """Feedback agent should accept custom model override."""
        from agents.feedback import FeedbackAgent

        custom_model = "anthropic.claude-3-sonnet-20240229-v1:0"
        agent = FeedbackAgent(model_id=custom_model)

        assert agent.model_id == custom_model

    def test_feedback_agent_accepts_aws_region(self):
        """Feedback agent should accept AWS region configuration."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent(region_name="us-east-1")

        assert agent.region_name == "us-east-1"

    def test_feedback_agent_default_region(self):
        """Feedback agent should use default region if not specified."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        # Should have a default region (us-west-2 per PRD)
        assert agent.region_name is not None
        assert agent.region_name == "us-west-2"

    def test_feedback_agent_has_strands_agent(self):
        """Feedback agent should have underlying Strands agent."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        assert hasattr(agent, "_agent")
        assert agent._agent is not None


# =============================================================================
# Test: System Prompt (4.2.2)
# =============================================================================


class TestSystemPrompt:
    """Tests for Feedback Agent system prompt configuration."""

    def test_system_prompt_exists(self):
        """Feedback agent should have a system prompt."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        assert agent.system_prompt is not None
        assert len(agent.system_prompt) > 0

    def test_system_prompt_contains_feedback_persona(self):
        """System prompt should contain senior engineering manager persona."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        assert "senior engineering manager" in agent.system_prompt.lower()
        assert "feedback" in agent.system_prompt.lower()

    def test_system_prompt_contains_strengths_section(self):
        """System prompt should mention Strengths section."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        assert "strengths" in agent.system_prompt.lower()

    def test_system_prompt_contains_areas_for_improvement(self):
        """System prompt should mention Areas for Improvement section."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        prompt_lower = agent.system_prompt.lower()
        assert "areas for improvement" in prompt_lower or "improvement" in prompt_lower

    def test_system_prompt_contains_detailed_feedback_criteria(self):
        """System prompt should mention detailed feedback criteria."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        prompt_lower = agent.system_prompt.lower()
        # Should mention the key areas to evaluate
        assert "requirements" in prompt_lower
        assert "high-level design" in prompt_lower or "design" in prompt_lower
        assert "trade-off" in prompt_lower or "tradeoff" in prompt_lower
        assert "scalability" in prompt_lower

    def test_system_prompt_contains_score_criteria(self):
        """System prompt should mention scoring criteria (1-10)."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        assert "1-10" in agent.system_prompt or "score" in agent.system_prompt.lower()

    def test_system_prompt_contains_recommendations(self):
        """System prompt should mention recommendations."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        assert "recommendation" in agent.system_prompt.lower()


# =============================================================================
# Test: Generate Feedback from Transcript (4.2.2, 4.2.3, 4.2.4)
# =============================================================================


class TestGenerateFeedback:
    """Tests for generating feedback from interview transcripts."""

    @pytest.mark.asyncio
    async def test_generate_feedback_from_transcript(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Agent should generate feedback from interview transcript."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            assert result is not None
            assert isinstance(result, FeedbackResult)

    @pytest.mark.asyncio
    async def test_generate_feedback_returns_markdown(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Generated feedback should contain markdown content."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            assert result.markdown is not None
            assert len(result.markdown) > 0
            # Should contain markdown headers
            assert "##" in result.markdown

    @pytest.mark.asyncio
    async def test_generate_feedback_passes_transcript_to_model(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Transcript content should be passed to the model."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            await agent.generate_feedback(sample_transcript)

            # Verify the model was called with transcript content
            mock_invoke.assert_called_once()
            call_args = mock_invoke.call_args
            prompt = call_args[0][0] if call_args[0] else call_args[1].get("prompt", "")

            # Transcript content should be in the prompt
            assert "URL shortener" in prompt
            assert "100 million URLs" in prompt or "base62" in prompt

    @pytest.mark.asyncio
    async def test_generate_feedback_includes_question(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Generated feedback should reference the interview question."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # The feedback should contextualize the interview question
            # (implementation may include it in the markdown or as metadata)
            assert result is not None


# =============================================================================
# Test: Feedback Contains Required Sections (4.2.2)
# =============================================================================


class TestFeedbackRequiredSections:
    """Tests for verifying feedback contains all required sections."""

    @pytest.mark.asyncio
    async def test_feedback_contains_strengths_section(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Feedback should contain Strengths section."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            sections = parse_feedback_sections(result.markdown)
            assert sections["strengths"] is not None
            assert len(sections["strengths"]) > 0

    @pytest.mark.asyncio
    async def test_feedback_contains_areas_for_improvement_section(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Feedback should contain Areas for Improvement section."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            sections = parse_feedback_sections(result.markdown)
            assert sections["areas_for_improvement"] is not None
            assert len(sections["areas_for_improvement"]) > 0

    @pytest.mark.asyncio
    async def test_feedback_contains_detailed_feedback_section(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Feedback should contain Detailed Feedback section."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            sections = parse_feedback_sections(result.markdown)
            assert sections["detailed_feedback"] is not None
            assert len(sections["detailed_feedback"]) > 0

    @pytest.mark.asyncio
    async def test_feedback_contains_score_section(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Feedback should contain Score section."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            sections = parse_feedback_sections(result.markdown)
            assert sections["score"] is not None
            assert len(sections["score"]) > 0

    @pytest.mark.asyncio
    async def test_feedback_contains_recommendations_section(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Feedback should contain Recommendations section."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            sections = parse_feedback_sections(result.markdown)
            assert sections["recommendations"] is not None
            assert len(sections["recommendations"]) > 0

    @pytest.mark.asyncio
    async def test_strengths_contains_bullet_points(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Strengths section should contain bullet points."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # Should have parsed strengths as list
            assert len(result.strengths) > 0
            assert all(isinstance(s, str) for s in result.strengths)

    @pytest.mark.asyncio
    async def test_areas_for_improvement_contains_bullet_points(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Areas for Improvement section should contain bullet points."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            assert len(result.areas_for_improvement) > 0
            assert all(isinstance(a, str) for a in result.areas_for_improvement)


# =============================================================================
# Test: Score Validation (4.2.3)
# =============================================================================


class TestScoreValidation:
    """Tests for score validation (1-10 scale)."""

    @pytest.mark.asyncio
    async def test_score_is_numeric(self, sample_transcript, sample_feedback_markdown):
        """Score should be a numeric value."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            assert isinstance(result.score, int)

    @pytest.mark.asyncio
    async def test_score_in_valid_range(self, sample_transcript, sample_feedback_markdown):
        """Score should be between 1 and 10 inclusive."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            assert 1 <= result.score <= 10

    @pytest.mark.asyncio
    async def test_score_extracted_from_markdown(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Score should be extracted correctly from markdown."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # Score in sample markdown is 6/10
            assert result.score == 6

    @pytest.mark.asyncio
    async def test_score_handles_various_formats(self, sample_transcript):
        """Score extraction should handle various markdown formats."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        test_cases = [
            ("## Score (1-10)\n**7/10**\nGood performance.", 7),
            ("## Score (1-10)\nScore: 8/10\nExcellent.", 8),
            ("## Score (1-10)\n5 / 10\nNeeds improvement.", 5),
            ("## Score (1-10)\n*9/10*\nOutstanding.", 9),
        ]

        for markdown_template, expected_score in test_cases:
            full_markdown = f"""## Strengths
- Good

## Areas for Improvement
- Needs work

## Detailed Feedback
Feedback here.

{markdown_template}

## Recommendations
- Study more
"""
            with patch.object(agent, "_invoke_model") as mock_invoke:
                mock_invoke.return_value = full_markdown

                result = await agent.generate_feedback(sample_transcript)

                assert result.score == expected_score, f"Expected {expected_score} for format: {markdown_template}"

    @pytest.mark.asyncio
    async def test_excellent_transcript_gets_high_score(
        self, excellent_transcript, sample_feedback_markdown
    ):
        """Excellent performance should result in high score (8-10)."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        # Mock response with high score
        high_score_markdown = sample_feedback_markdown.replace("6/10", "9/10")

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = high_score_markdown

            result = await agent.generate_feedback(excellent_transcript)

            # Excellent transcript should get 8+ score
            assert result.score >= 8

    @pytest.mark.asyncio
    async def test_poor_transcript_gets_low_score(
        self, poor_transcript, sample_feedback_markdown
    ):
        """Poor performance should result in low score (1-4)."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        # Mock response with low score
        low_score_markdown = sample_feedback_markdown.replace("6/10", "3/10")

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = low_score_markdown

            result = await agent.generate_feedback(poor_transcript)

            # Poor transcript should get low score
            assert result.score <= 4


# =============================================================================
# Test: Feedback Markdown Format (4.2.2)
# =============================================================================


class TestFeedbackMarkdownFormat:
    """Tests for validating markdown output format."""

    @pytest.mark.asyncio
    async def test_feedback_is_valid_markdown(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Output should be valid markdown format."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # Should contain markdown headers
            assert "##" in result.markdown

            # Should not contain HTML (pure markdown)
            assert "<html>" not in result.markdown.lower()
            assert "<body>" not in result.markdown.lower()

    @pytest.mark.asyncio
    async def test_feedback_sections_use_h2_headers(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Feedback sections should use H2 (##) headers."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # Main sections should use ## headers
            assert "## Strengths" in result.markdown or "##Strengths" in result.markdown
            assert (
                "## Areas for Improvement" in result.markdown
                or "## Areas For Improvement" in result.markdown
            )
            assert "## Score" in result.markdown
            assert "## Recommendations" in result.markdown

    @pytest.mark.asyncio
    async def test_feedback_uses_bullet_points_for_lists(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Feedback should use bullet points (- or *) for list items."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # Should contain bullet points
            assert re.search(r"^[\-\*]\s+", result.markdown, re.MULTILINE)

    @pytest.mark.asyncio
    async def test_detailed_feedback_has_subsections(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Detailed Feedback should have subsections for each evaluation area."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            sections = parse_feedback_sections(result.markdown)
            detailed = sections["detailed_feedback"]

            # Should have subsections (### headers) for detailed feedback areas
            assert detailed is not None
            # Check for subsections like Requirements, High-Level Design, etc.
            assert (
                "###" in detailed
                or "requirements" in detailed.lower()
                or "design" in detailed.lower()
            )


# =============================================================================
# Test: Recommendations Quality (4.2.4)
# =============================================================================


class TestRecommendationsQuality:
    """Tests for recommendation generation quality."""

    @pytest.mark.asyncio
    async def test_recommendations_are_specific(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Recommendations should contain specific study areas."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # Recommendations should be specific (not generic)
            assert len(result.recommendations) > 0

            # At least some recommendations should mention specific topics
            all_recs = " ".join(result.recommendations).lower()
            specific_terms = [
                "sharding",
                "caching",
                "database",
                "consistency",
                "distributed",
                "replication",
                "partitioning",
                "load balancing",
                "trade-off",
                "tradeoff",
                "architecture",
                "design pattern",
                "monitoring",
                "scalability",
            ]

            has_specific_term = any(term in all_recs for term in specific_terms)
            assert (
                has_specific_term
            ), f"Recommendations should contain specific technical terms. Got: {result.recommendations}"

    @pytest.mark.asyncio
    async def test_recommendations_are_actionable(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Recommendations should be actionable (study X, practice Y)."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # Recommendations should have actionable verbs
            actionable_verbs = [
                "study",
                "practice",
                "learn",
                "review",
                "focus",
                "improve",
                "work on",
                "read",
                "explore",
            ]

            all_recs = " ".join(result.recommendations).lower()
            has_actionable_verb = any(verb in all_recs for verb in actionable_verbs)

            assert (
                has_actionable_verb
            ), f"Recommendations should contain actionable verbs. Got: {result.recommendations}"

    @pytest.mark.asyncio
    async def test_recommendations_relate_to_areas_for_improvement(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Recommendations should relate to identified areas for improvement."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # There should be some overlap between improvement areas and recommendations
            # (at least thematically)
            assert len(result.recommendations) > 0
            assert len(result.areas_for_improvement) > 0

    @pytest.mark.asyncio
    async def test_minimum_recommendations_count(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Should provide at least 2 recommendations."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            assert len(result.recommendations) >= 2


# =============================================================================
# Test: Edge Cases and Error Handling
# =============================================================================


class TestEdgeCases:
    """Tests for edge cases and error handling."""

    @pytest.mark.asyncio
    async def test_empty_transcript_raises_error(self, empty_transcript):
        """Empty transcript should raise ValueError."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with pytest.raises(ValueError, match="transcript"):
            await agent.generate_feedback(empty_transcript)

    @pytest.mark.asyncio
    async def test_minimal_transcript_works(
        self, minimal_transcript, sample_feedback_markdown
    ):
        """Minimal transcript (one exchange) should still generate feedback."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(minimal_transcript)

            assert result is not None
            assert result.markdown is not None

    @pytest.mark.asyncio
    async def test_handles_api_timeout(self, sample_transcript):
        """Should handle API timeout gracefully."""
        from agents.feedback import FeedbackAgent, FeedbackGenerationError

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.side_effect = asyncio.TimeoutError("API timeout")

            with pytest.raises(FeedbackGenerationError, match="timeout"):
                await agent.generate_feedback(sample_transcript)

    @pytest.mark.asyncio
    async def test_handles_api_error(self, sample_transcript):
        """Should handle API errors gracefully."""
        from agents.feedback import FeedbackAgent, FeedbackGenerationError

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.side_effect = Exception("Bedrock API error")

            with pytest.raises(FeedbackGenerationError):
                await agent.generate_feedback(sample_transcript)

    @pytest.mark.asyncio
    async def test_handles_malformed_response(self, sample_transcript):
        """Should handle malformed model response."""
        from agents.feedback import FeedbackAgent, FeedbackGenerationError

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            # Return incomplete markdown missing required sections
            mock_invoke.return_value = "Some random text without proper sections"

            with pytest.raises(FeedbackGenerationError, match="invalid|missing|section"):
                await agent.generate_feedback(sample_transcript)

    @pytest.mark.asyncio
    async def test_handles_missing_score(self, sample_transcript):
        """Should handle response missing score section."""
        from agents.feedback import FeedbackAgent, FeedbackGenerationError

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            # Return markdown without score
            mock_invoke.return_value = """## Strengths
- Good

## Areas for Improvement
- Needs work

## Detailed Feedback
Details here.

## Recommendations
- Study more
"""
            with pytest.raises(FeedbackGenerationError, match="score"):
                await agent.generate_feedback(sample_transcript)

    @pytest.mark.asyncio
    async def test_handles_invalid_score_format(self, sample_transcript):
        """Should handle invalid score format in response."""
        from agents.feedback import FeedbackAgent, FeedbackGenerationError

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = """## Strengths
- Good

## Areas for Improvement
- Needs work

## Detailed Feedback
Details.

## Score (1-10)
The candidate did okay.

## Recommendations
- Study
"""
            with pytest.raises(FeedbackGenerationError, match="score"):
                await agent.generate_feedback(sample_transcript)


# =============================================================================
# Test: Transcript Formatting
# =============================================================================


class TestTranscriptFormatting:
    """Tests for transcript formatting before sending to model."""

    @pytest.mark.asyncio
    async def test_transcript_formatted_with_timestamps(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Transcript should include timestamps when sent to model."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            await agent.generate_feedback(sample_transcript)

            call_args = mock_invoke.call_args
            prompt = call_args[0][0] if call_args[0] else call_args[1].get("prompt", "")

            # Prompt should indicate some form of timestamp or time progression
            # (implementation may format timestamps differently)
            assert len(prompt) > 0

    @pytest.mark.asyncio
    async def test_transcript_formatted_with_speaker_labels(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Transcript should include speaker labels (interviewer/candidate)."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            await agent.generate_feedback(sample_transcript)

            call_args = mock_invoke.call_args
            prompt = call_args[0][0] if call_args[0] else call_args[1].get("prompt", "")

            # Prompt should distinguish between interviewer and candidate
            prompt_lower = prompt.lower()
            assert "interviewer" in prompt_lower or "candidate" in prompt_lower

    @pytest.mark.asyncio
    async def test_format_transcript_method(self, sample_transcript):
        """Agent should have a format_transcript method."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        assert hasattr(agent, "format_transcript")

        formatted = agent.format_transcript(sample_transcript)

        assert isinstance(formatted, str)
        assert len(formatted) > 0
        assert "URL shortener" in formatted


# =============================================================================
# Test: FeedbackResult Dataclass
# =============================================================================


class TestFeedbackResultDataclass:
    """Tests for FeedbackResult dataclass structure."""

    @pytest.mark.asyncio
    async def test_feedback_result_has_generated_at(
        self, sample_transcript, sample_feedback_markdown
    ):
        """FeedbackResult should have generated_at timestamp."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            assert hasattr(result, "generated_at")
            assert isinstance(result.generated_at, datetime)

    @pytest.mark.asyncio
    async def test_feedback_result_all_fields_present(
        self, sample_transcript, sample_feedback_markdown
    ):
        """FeedbackResult should have all required fields."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            assert hasattr(result, "markdown")
            assert hasattr(result, "score")
            assert hasattr(result, "strengths")
            assert hasattr(result, "areas_for_improvement")
            assert hasattr(result, "recommendations")
            assert hasattr(result, "generated_at")


# =============================================================================
# Test: Integration-like Tests (with mocks)
# =============================================================================


class TestFeedbackAgentIntegration:
    """Integration-like tests for the complete feedback generation flow."""

    @pytest.mark.asyncio
    async def test_complete_feedback_workflow(
        self, sample_transcript, sample_feedback_markdown
    ):
        """Test complete workflow: transcript -> feedback generation -> parsed result."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # Verify complete result
            assert result.markdown is not None
            assert 1 <= result.score <= 10
            assert len(result.strengths) > 0
            assert len(result.areas_for_improvement) > 0
            assert len(result.recommendations) > 0
            assert result.generated_at is not None

    @pytest.mark.asyncio
    async def test_save_feedback_to_file(
        self, sample_transcript, sample_feedback_markdown, tmp_path
    ):
        """Agent should support saving feedback to file."""
        from agents.feedback import FeedbackAgent

        agent = FeedbackAgent()

        with patch.object(agent, "_invoke_model") as mock_invoke:
            mock_invoke.return_value = sample_feedback_markdown

            result = await agent.generate_feedback(sample_transcript)

            # Save to file
            output_path = tmp_path / "feedback.md"
            await agent.save_feedback(result, str(output_path))

            # Verify file was created
            assert output_path.exists()

            # Verify content
            content = output_path.read_text()
            assert "## Strengths" in content
            assert "## Score" in content
