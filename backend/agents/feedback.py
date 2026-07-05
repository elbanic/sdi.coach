"""
Feedback Agent for SDI Coach

Provides comprehensive interview feedback using Strands Agent with Amazon Bedrock Claude Opus 4.6.
Analyzes interview transcripts and generates structured markdown feedback including:
- Strengths
- Areas for Improvement
- Detailed Feedback (requirements, design, trade-offs, scalability)
- Score (1-10)
- Recommendations

Environment Variables:
- SDICOACH_FEEDBACK_MODEL: Model ID (default: anthropic.claude-opus-4-6-v1)
- AWS_REGION: AWS region (default: us-west-2)
"""

import asyncio
import logging
import os
import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional

from strands import Agent
from strands.models import BedrockModel

# Configure module logger
logger = logging.getLogger(__name__)


# =============================================================================
# Constants
# =============================================================================

DEFAULT_MODEL_ID = "us.anthropic.claude-opus-4-6-v1"
DEFAULT_REGION = "us-west-2"

FEEDBACK_SYSTEM_PROMPT = """
You are a senior engineering manager providing interview feedback.
Analyze the candidate's system design interview transcript and provide:

## Strengths
- What the candidate did well
- Strong technical decisions

## Areas for Improvement
- Gaps in the design
- Missed considerations
- Communication issues

## Detailed Feedback

### Requirements Gathering
Evaluate how well the candidate gathered and clarified requirements.

### High-Level Design
Assess the quality of the overall system architecture.

### Deep Dive Quality
Rate the depth of technical discussion in specific areas.

### Trade-off Analysis
Evaluate the candidate's ability to discuss trade-offs between different approaches.

### Scalability Considerations
Assess awareness of scalability challenges and solutions.

## Score (1-10)
- Overall performance rating with justification
- Format: **X/10** followed by explanation

## Recommendations
- Specific study areas for improvement
- Actionable learning suggestions
"""


# =============================================================================
# Data Classes
# =============================================================================


@dataclass
class TranscriptEntry:
    """A single entry in the interview transcript."""

    timestamp: datetime
    source: str  # "interviewer" or "candidate"
    content: str


@dataclass
class FeedbackResult:
    """Result from the feedback agent."""

    markdown: str
    score: int
    strengths: list[str]
    areas_for_improvement: list[str]
    recommendations: list[str]
    generated_at: datetime = field(default_factory=datetime.now)


# =============================================================================
# Exceptions
# =============================================================================


class FeedbackGenerationError(Exception):
    """Raised when feedback generation fails."""

    pass


# =============================================================================
# Feedback Agent
# =============================================================================


class FeedbackAgent:
    """
    Agent for generating comprehensive interview feedback.

    Uses Strands Agent with Amazon Bedrock Claude Opus model for deep analysis
    of interview transcripts.

    Attributes:
        model_id: The Bedrock model ID to use
        region_name: AWS region for Bedrock API calls
        system_prompt: The system prompt for the agent
    """

    def __init__(
        self,
        model_id: Optional[str] = None,
        region_name: Optional[str] = None,
    ):
        """
        Initialize the Feedback Agent.

        Args:
            model_id: Bedrock model ID. Defaults to env var or Claude Opus.
            region_name: AWS region. Defaults to env var or us-west-2.
        """
        # Get configuration from environment or defaults
        self.model_id = model_id or os.getenv(
            "SDICOACH_FEEDBACK_MODEL", DEFAULT_MODEL_ID
        )
        self.region_name = region_name or os.getenv("AWS_REGION", DEFAULT_REGION)
        self.system_prompt = FEEDBACK_SYSTEM_PROMPT

        logger.info(
            f"Initializing FeedbackAgent with model={self.model_id}, region={self.region_name}"
        )

        # Initialize Bedrock model
        model = BedrockModel(
            model_id=self.model_id,
            region_name=self.region_name,
            temperature=0.3,  # Lower temperature for consistent feedback
        )

        # Initialize Strands Agent
        self._agent = Agent(
            model=model,
            system_prompt=self.system_prompt,
        )

    async def generate_feedback(
        self,
        transcript: list[TranscriptEntry],
    ) -> FeedbackResult:
        """
        Generate comprehensive feedback from interview transcript.

        Args:
            transcript: List of TranscriptEntry objects representing the interview.

        Returns:
            FeedbackResult with feedback markdown.

        Raises:
            ValueError: If transcript is empty.
            FeedbackGenerationError: If feedback generation fails.
        """
        # Validate input
        if not transcript:
            raise ValueError("Cannot generate feedback from empty transcript")

        logger.info(f"Generating feedback for transcript with {len(transcript)} entries")

        # Format transcript for the model
        formatted_transcript = self.format_transcript(transcript)

        try:
            # Invoke the model
            markdown_response = await self._invoke_model(formatted_transcript)

            # Try to extract score for logging (optional, don't fail if not found)
            score = self._extract_score(markdown_response)
            if score:
                logger.info(f"Generated feedback with score {score}/10")
            else:
                logger.info("Generated feedback (score not extracted)")

            return FeedbackResult(
                markdown=markdown_response,
                score=score or 0,
                strengths=[],
                areas_for_improvement=[],
                recommendations=[],
                generated_at=datetime.now(),
            )

        except asyncio.TimeoutError as e:
            logger.error(f"API timeout during feedback generation: {e}")
            raise FeedbackGenerationError(f"API timeout: {e}")
        except FeedbackGenerationError:
            raise
        except Exception as e:
            logger.error(f"Error generating feedback: {e}")
            raise FeedbackGenerationError(f"Failed to generate feedback: {e}")

    async def _invoke_model(self, prompt: str) -> str:
        """
        Invoke the underlying Strands agent with the given prompt.

        Args:
            prompt: The formatted transcript and instruction.

        Returns:
            The model's response text.
        """
        # Use synchronous invocation wrapped in asyncio
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None,
            lambda: self._agent(prompt),
        )

        # Extract text from response
        # Handle both object and dict responses from Bedrock/Strands
        if isinstance(response, dict):
            # Dict response format
            if "message" in response:
                content = response["message"].get("content", [])
                if content and isinstance(content, list):
                    return content[0].get("text", str(response))
            elif "content" in response:
                return response["content"]
            return str(response)
        elif hasattr(response, "message"):
            # Object response format - message could be object or dict
            message = response.message
            if isinstance(message, dict):
                content = message.get("content", [])
                if content and isinstance(content, list):
                    return content[0].get("text", str(response))
                return str(response)
            else:
                return message.content[0]["text"]
        elif hasattr(response, "content"):
            return response.content
        else:
            return str(response)

    def format_transcript(self, transcript: list[TranscriptEntry]) -> str:
        """
        Format transcript entries into a string for the model.

        Args:
            transcript: List of TranscriptEntry objects.

        Returns:
            Formatted string with timestamps and speaker labels.
        """
        lines = [
            "# Interview Transcript",
            "",
            "## Conversation:",
            "",
        ]

        for entry in transcript:
            # Format timestamp
            time_str = entry.timestamp.strftime("%H:%M:%S")

            # Format speaker label with emoji
            if entry.source == "interviewer":
                speaker = "Interviewer"
            else:
                speaker = "Candidate"

            lines.append(f"[{time_str}] **{speaker}**: {entry.content}")
            lines.append("")

        lines.append("---")
        lines.append("")
        lines.append("Please analyze this interview and provide detailed feedback.")

        return "\n".join(lines)

    def _parse_feedback(self, markdown: str) -> FeedbackResult:
        """
        Parse the model's markdown response into a FeedbackResult.

        Args:
            markdown: Raw markdown response from the model.

        Returns:
            FeedbackResult with parsed sections.

        Raises:
            FeedbackGenerationError: If required sections are missing or invalid.
        """
        # Extract sections
        strengths = self._extract_bullet_points(
            self._extract_section(markdown, "Strengths")
        )
        areas = self._extract_bullet_points(
            self._extract_section(markdown, "Areas for Improvement")
        )
        recommendations = self._extract_bullet_points(
            self._extract_section(markdown, "Recommendations")
        )

        # Extract and validate score - try multiple patterns
        score = None
        # Try different section name patterns
        for score_pattern in [r"Score\s*\(1-10\)", r"Score", r"Overall\s+Score", r"Rating"]:
            score_section = self._extract_section(markdown, score_pattern)
            if score_section:
                score = self._extract_score(score_section)
                if score is not None:
                    break

        # Fallback: search entire markdown for score pattern
        if score is None:
            score = self._extract_score(markdown)

        if score is None:
            logger.error("Failed to extract score from feedback")
            raise FeedbackGenerationError(
                "Invalid feedback: missing or invalid score section"
            )

        # Validate required sections exist (log warning but don't fail)
        if not self._has_required_sections(markdown):
            logger.warning("Some required sections may be missing, but proceeding with available content")

        return FeedbackResult(
            markdown=markdown,
            score=score,
            strengths=strengths,
            areas_for_improvement=areas,
            recommendations=recommendations,
            generated_at=datetime.now(),
        )

    def _extract_section(self, markdown: str, section_name: str) -> Optional[str]:
        """Extract content of a section from markdown."""
        # Match section header and content until next section or end
        pattern = rf"##\s*{section_name}\s*\n(.*?)(?=##|\Z)"
        match = re.search(pattern, markdown, re.DOTALL | re.IGNORECASE)

        if match:
            return match.group(1).strip()
        return None

    def _extract_bullet_points(self, section: Optional[str]) -> list[str]:
        """Extract bullet points from a section."""
        if not section:
            return []

        # Match lines starting with - or *
        bullets = re.findall(r"^[\-\*]\s*(.+)$", section, re.MULTILINE)
        return [b.strip() for b in bullets if b.strip()]

    def _extract_score(self, score_section: Optional[str]) -> Optional[int]:
        """Extract numeric score from score section."""
        if not score_section:
            return None

        # Try multiple patterns for score extraction
        patterns = [
            r"(\d+)\s*/\s*10",           # "6/10", "5 / 10"
            r"\*\*(\d+)/10\*\*",         # "**7/10**"
            r"Score[:\s]+(\d+)",         # "Score: 8", "Score 7"
            r"Rating[:\s]+(\d+)",        # "Rating: 8"
            r"(\d+)\s*out\s*of\s*10",    # "7 out of 10"
        ]

        for pattern in patterns:
            match = re.search(pattern, score_section, re.IGNORECASE)
            if match:
                score = int(match.group(1))
                # Validate range
                if 1 <= score <= 10:
                    return score

        return None

    def _has_required_sections(self, markdown: str) -> bool:
        """Check if markdown contains all required sections."""
        required_patterns = [
            r"##\s*Strengths",
            r"##\s*Areas\s+(for\s+)?Improvement",
            r"##\s*Detailed\s+Feedback",
            r"##\s*(Score|Rating|Overall\s+Score)",  # More flexible score pattern
            r"##\s*Recommendations",
        ]

        for pattern in required_patterns:
            if not re.search(pattern, markdown, re.IGNORECASE):
                logger.warning(f"Missing required section: {pattern}")
                return False

        return True

    async def save_feedback(self, result: FeedbackResult, filepath: str) -> None:
        """
        Save feedback result to a markdown file.

        Args:
            result: The FeedbackResult to save.
            filepath: Path to the output file.
        """
        path = Path(filepath)

        # Ensure parent directory exists
        path.parent.mkdir(parents=True, exist_ok=True)

        # Add metadata header
        header = [
            f"# Interview Feedback",
            f"",
            f"**Generated**: {result.generated_at.strftime('%Y-%m-%d %H:%M:%S')}",
            f"**Score**: {result.score}/10",
            f"",
            f"---",
            f"",
        ]

        content = "\n".join(header) + result.markdown

        # Write to file
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            lambda: path.write_text(content),
        )

        logger.info(f"Saved feedback to {filepath}")
