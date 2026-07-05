# AI Agents module
"""
AI Agents for SDI Coach - Interview and Feedback agents using Strands + Bedrock.
"""

from .interviewer import (
    InterviewerAgent,
    InterviewerConfig,
    ConversationContext,
    ConversationTurn,
    FollowUpTracker,
    InterviewerError,
    AgentInitializationError,
    ResponseGenerationError,
    INTERVIEWER_SYSTEM_PROMPT,
    DEFAULT_MODEL_ID,
    MAX_FOLLOWUPS_PER_TOPIC,
)

from .feedback import (
    FeedbackAgent,
    FeedbackResult,
    TranscriptEntry,
    FeedbackGenerationError,
    FEEDBACK_SYSTEM_PROMPT,
)

from .service import (
    AgentService,
    SessionState,
    SessionStatistics,
    AgentServiceError,
    InvalidStateError,
    InterviewNotStartedError,
)

__all__ = [
    # Interviewer Agent
    "InterviewerAgent",
    "InterviewerConfig",
    "ConversationContext",
    "ConversationTurn",
    "FollowUpTracker",
    "InterviewerError",
    "AgentInitializationError",
    "ResponseGenerationError",
    "INTERVIEWER_SYSTEM_PROMPT",
    "DEFAULT_MODEL_ID",
    "MAX_FOLLOWUPS_PER_TOPIC",
    # Feedback Agent
    "FeedbackAgent",
    "FeedbackResult",
    "TranscriptEntry",
    "FeedbackGenerationError",
    "FEEDBACK_SYSTEM_PROMPT",
    # Agent Service
    "AgentService",
    "SessionState",
    "SessionStatistics",
    "AgentServiceError",
    "InvalidStateError",
    "InterviewNotStartedError",
]
