# sdi.coach E2E Test Scenario

## Overview

This document provides end-to-end test scenarios to validate the complete interview flow.

---

## Scenario 1: URL Shortener System Design Interview

### Test Configuration

| Setting | Value |
|---------|-------|
| Duration | ~5 minutes |
| Topic | URL Shortener Service |
| Q&A Rounds | 5 exchanges |
| Expected Output | `feedback_*.md` file |

---

### Full Interaction Script

```
================================================================================
                        sdi.coach Test Script
                    "Design a URL Shortener Service"
================================================================================

[START COMMAND]
> /start "Design a URL shortener service"

--------------------------------------------------------------------------------
[AI Interviewer - Initial Question]
--------------------------------------------------------------------------------

🧑‍💼 [30:00] Great! Let's design a URL shortener service like bit.ly or tinyurl.
   Before we dive into the design, I'd like to understand the requirements better.
   What do you think are the core functional requirements for this system?

--------------------------------------------------------------------------------
[User Response 1] - Speak into microphone, then /answer, then type /answer to submit
--------------------------------------------------------------------------------

🎙️ [29:20] I think the main functional requirements are:
            First, users should be able to create a short URL from a long URL.
            Second, when users access the short URL, they should be redirected to
            the original long URL.
            Third, optionally, we might want to track analytics like click counts.
            And maybe allow custom short URLs for premium users.
                                                                  

--------------------------------------------------------------------------------
[AI Interviewer - Follow-up 1: Scale]
--------------------------------------------------------------------------------

🧑‍💼 [29:00] Good overview. You mentioned analytics and custom URLs as optional
         features. Let's focus on the core first. For the URL shortening, what scale
         are we designing for? How many URLs do you expect to be created per day,
         and what's the read-to-write ratio you'd assume?

--------------------------------------------------------------------------------
[User Response 2] - Speak into microphone, then /answer
--------------------------------------------------------------------------------

🎙️ [28:10] Let me think about the scale. If we're building something like
            bit.ly, I'd estimate maybe 100 million new URLs created per month,
            which is about 3 million per day or roughly 40 per second.

🎙️ [27:30] For reads, URL shorteners are read-heavy. I'd assume a 100:1 read
            to write ratio, so about 4,000 redirects per second. At peak times,
            maybe 10x that, so we should design for 40,000 reads per second.

--------------------------------------------------------------------------------
[AI Interviewer - Follow-up 2: Algorithm]
--------------------------------------------------------------------------------

🧑‍💼 [00:01:35] Excellent estimation! You've established 40 writes/sec and up to
   40K reads/sec at peak. Now, let's talk about the URL shortening algorithm.
   How would you generate the short URL key? What length would you choose and why?

--------------------------------------------------------------------------------
[User Response 3] - Speak into microphone, then /answer
--------------------------------------------------------------------------------

...

--------------------------------------------------------------------------------
[AI Interviewer - Follow-up 3: High Availability]
--------------------------------------------------------------------------------

🧑‍💼 [00:02:30] You mentioned using Snowflake for ID generation. That's a solid
   choice. But what happens if our ID generator becomes a single point of failure?
   How would you handle high availability for the key generation service?

--------------------------------------------------------------------------------
[User Response 4] - Speak into microphone, then /answer
--------------------------------------------------------------------------------

...

--------------------------------------------------------------------------------
[AI Interviewer - Follow-up 4: Storage]
--------------------------------------------------------------------------------

🧑‍💼 [00:03:25] Great solution for availability. Now let's discuss the storage layer.
   Given the read-heavy workload of 40K reads per second, what database would you
   choose and how would you structure the schema?

--------------------------------------------------------------------------------
[User Response 5] - Speak into microphone, then /answer
--------------------------------------------------------------------------------

...

--------------------------------------------------------------------------------
[END COMMAND]
--------------------------------------------------------------------------------

> /end

--------------------------------------------------------------------------------
[AI Interviewer - Wrap Up]
--------------------------------------------------------------------------------

🧑‍💼 [00:04:15] Great job! We covered requirements, scale estimation, URL generation,
   high availability, and storage design. Let me generate your feedback report.

================================================================================
                         Generating Feedback...
================================================================================

📝 Saving feedback to: ./feedback_2024-02-07_url-shortener.md

================================================================================
```

---

### Expected Feedback Output

**File**: `feedback_2024-02-07_url-shortener.md`

```markdown
# System Design Interview Feedback

## Topic: URL Shortener Service
## Date: 2024-02-07
## Duration: 4 minutes 15 seconds

---

## Strengths

- **Clear requirements gathering**: Identified core vs optional features upfront
- **Solid back-of-envelope calculations**: 40 writes/sec, 40K reads/sec estimation
- **Good algorithm choice**: Base62 with Snowflake for unique key generation
- **Proactive on reliability**: Addressed SPOF before being asked

---

## Areas for Improvement

- **Missing discussion on**:
  - URL expiration and cleanup strategy
  - Geographic distribution / CDN for redirects
  - Rate limiting to prevent abuse
- **Could elaborate more on**:
  - Cache invalidation strategy
  - Monitoring and alerting

---

## Detailed Feedback

| Category | Score | Notes |
|----------|-------|-------|
| Requirements Gathering | 8/10 | Good functional reqs, missed non-functional |
| High-Level Design | 8/10 | Solid architecture, clear component separation |
| Deep Dive | 7/10 | Good on ID generation, light on failure scenarios |
| Trade-off Analysis | 7/10 | Mentioned options but could compare more |
| Scalability | 8/10 | Good caching strategy, DB choice reasonable |
| Communication | 9/10 | Clear explanations, good structure |

---

## Overall Score: 7.8 / 10

**Summary**: Strong performance with good systematic approach. Demonstrated solid
understanding of distributed systems concepts. To improve, practice discussing
failure modes and recovery strategies in more depth.

---

## Recommendations

1. **Study**: Consistent hashing for cache distribution
2. **Practice**: Discussing monitoring and observability earlier
3. **Review**: URL shortener case studies (bit.ly engineering blog)
```

---

## Validation Checklist

### Functional Tests

| # | Test Case | Command | Expected Result | Pass |
|---|-----------|---------|-----------------|------|
| 1 | Start interview | `/start "Design a URL shortener"` | AI asks first question via TTS | ☐ |
| 2 | Voice input | Speak into mic | STT transcribes and displays | ☐ |
| 3 | Submit answer | `/answer` (or `/a`) | User response sent to AI | ☐ |
| 4 | AI follow-up | (automatic after /answer) | AI generates contextual follow-up | ☐ |
| 5 | Pause interview | `/pause` | Timer pauses, mic muted | ☐ |
| 6 | Resume interview | `/start` (while paused) | Timer resumes, mic active | ☐ |
| 7 | End interview | `/end` | Feedback generation starts | ☐ |
| 8 | Feedback output | (automatic) | Markdown file saved | ☐ |
| 9 | Quit application | `/quit` | Clean shutdown | ☐ |

### Non-Functional Tests

| # | Test Case | Expected Result | Pass |
|---|-----------|-----------------|------|
| 1 | 30-minute timer | Timer counts down, warns at 5 min | ☐ |
| 2 | TTS interruption | Speaking stops TTS playback | ☐ |
| 3 | Backend crash recovery | CLI shows error, allows restart | ☐ |
| 4 | Network disconnection | Graceful handling of Bedrock timeout | ☐ |

---

## Scenario 2: Distributed Cache Design (Short)

### Quick Test Script

```
> /start "Design a distributed cache like Redis"

🧑‍💼 What are the key requirements for this distributed cache system?

🎙️ We need to support GET, SET, DELETE operations with sub-
    millisecond latency. The cache should support multiple data types
    like strings, lists, and hashes. We need replication for high
    availability and partitioning for scalability.

> /answer

🧑‍💼 How would you handle data partitioning across multiple nodes?

🎙️ I'd use consistent hashing to distribute keys across nodes.
    This minimizes key redistribution when nodes are added or removed.
    We'd have virtual nodes to ensure even distribution, maybe 100 to
    200 virtual nodes per physical node.

> /answer

> /end
```

---

## Scenario 3: Rate Limiter Design (Minimal)

### Quick Test Script

```
> /start "Design a rate limiter"

🧑‍💼 What type of rate limiting algorithm would you consider for this system?

🎙️ I'd consider token bucket or sliding window algorithms. Token
    bucket is simpler and allows burst traffic, while sliding window
    provides smoother rate limiting. For an API gateway, I'd go with
    token bucket.

> /answer

> /end
```

---

## Test Environment Setup

### Prerequisites

```bash
# 1. AWS credentials configured
export AWS_REGION=us-west-2
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...

# 2. Microphone permissions granted
# System Preferences > Security & Privacy > Microphone > Terminal

# 3. Backend running
cd backend && source .venv/bin/activate && python main.py

# 4. Or use unified launcher
./scripts/sdi-coach --debug
```

### Debug Mode

```bash
# Run with verbose logging
./scripts/sdi-coach --debug

# Check logs
tail -f /tmp/sdicoach.log
```

---

## Notes

- **Interview Duration**: Default 30 minutes, can be configured
- **Follow-up Questions**: AI generates 3-5 follow-ups per topic
- **Interviewer Model**: Claude Sonnet 4.5 (fast, conversational)
- **Feedback Model**: Claude Opus 4.6 (deep analysis)
- **TTS Voice**: English, professional tone (Qwen3-TTS)
- **Workflow**: Speak → /answer → AI responds → repeat
