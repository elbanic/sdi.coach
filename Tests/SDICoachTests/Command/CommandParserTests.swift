// CommandParserTests.swift
// Tests for CommandParser
//
// Feature: Phase 5.1 Command System
// Task: 5.1.2 - CommandParser implementation
//
// Requirements from PRD.md:
// - Parse commands from user input strings
// - Support formats:
//   - /start - start with no question
//   - /start "Design a URL shortener" - start with quoted question
//   - /start Design a URL shortener - start with unquoted question
//   - /pause - pause interview
//   - /end - end interview
//   - /quit or /q - quit application
//   - Any other input -> unknown(input:)
//
// Tests should FAIL initially - CommandParser.swift does not exist yet.

import Testing
@testable import SDICoach

// MARK: - CommandParser Existence Tests

@Suite("CommandParser Definition")
struct CommandParserDefinitionTests {

    @Test("CommandParser type exists")
    func commandParserTypeExists() {
        // This test verifies the CommandParser type exists
        let _: CommandParser.Type = CommandParser.self
    }

    @Test("CommandParser has parse method")
    func commandParserHasParseMethod() {
        // Verify parse method exists with correct signature
        let parser = CommandParser()
        let _: Command = parser.parse("/start")
    }
}

// MARK: - Start Command Parsing Tests

@Suite("Parse Start Command")
struct ParseStartCommandTests {

    let parser = CommandParser()

    @Test("parse /start without question")
    func parseStartWithoutQuestion() {
        let command = parser.parse("/start")
        #expect(command == .start(question: nil))
    }

    @Test("parse /start with quoted question")
    func parseStartWithQuotedQuestion() {
        let command = parser.parse("/start \"Design a URL shortener\"")
        #expect(command == .start(question: "Design a URL shortener"))
    }

    @Test("parse /start with unquoted question")
    func parseStartWithUnquotedQuestion() {
        let command = parser.parse("/start Design a URL shortener")
        #expect(command == .start(question: "Design a URL shortener"))
    }

    // Note: Single-quoted question test moved to "Quote Parsing" suite

    @Test("parse /start with empty quoted string")
    func parseStartWithEmptyQuotedString() {
        let command = parser.parse("/start \"\"")
        #expect(command == .start(question: nil))
    }

    @Test("parse /start with whitespace after command")
    func parseStartWithWhitespaceAfterCommand() {
        let command = parser.parse("/start   ")
        #expect(command == .start(question: nil))
    }

    @Test("parse /start with question containing quotes")
    func parseStartWithQuestionContainingQuotes() {
        let command = parser.parse("/start \"Design a 'cache' system\"")
        #expect(command == .start(question: "Design a 'cache' system"))
    }

    @Test("parse /start with multiword unquoted question")
    func parseStartWithMultiwordUnquotedQuestion() {
        let command = parser.parse("/start Design a distributed cache with Redis")
        #expect(command == .start(question: "Design a distributed cache with Redis"))
    }

    @Test("parse /start preserves leading/trailing spaces in quoted question")
    func parseStartPreservesSpacesInQuotedQuestion() {
        let command = parser.parse("/start \"  Design a cache  \"")
        #expect(command == .start(question: "  Design a cache  "))
    }

    @Test("parse /start trims unquoted question")
    func parseStartTrimsUnquotedQuestion() {
        let command = parser.parse("/start   Design a cache   ")
        #expect(command == .start(question: "Design a cache"))
    }
}

// MARK: - Pause Command Parsing Tests

@Suite("Parse Pause Command")
struct ParsePauseCommandTests {

    let parser = CommandParser()

    @Test("parse /pause")
    func parsePause() {
        let command = parser.parse("/pause")
        #expect(command == .pause)
    }

    @Test("parse /pause with trailing whitespace")
    func parsePauseWithTrailingWhitespace() {
        let command = parser.parse("/pause   ")
        #expect(command == .pause)
    }

    @Test("parse /pause with leading whitespace")
    func parsePauseWithLeadingWhitespace() {
        let command = parser.parse("  /pause")
        #expect(command == .pause)
    }

    @Test("parse /pause ignores extra arguments")
    func parsePauseIgnoresExtraArguments() {
        // /pause with extra text should still be pause
        // (arguments are ignored for pause command)
        let command = parser.parse("/pause extra stuff")
        #expect(command == .pause)
    }
}

// MARK: - End Command Parsing Tests

@Suite("Parse End Command")
struct ParseEndCommandTests {

    let parser = CommandParser()

    @Test("parse /end")
    func parseEnd() {
        let command = parser.parse("/end")
        #expect(command == .end)
    }

    @Test("parse /end with trailing whitespace")
    func parseEndWithTrailingWhitespace() {
        let command = parser.parse("/end   ")
        #expect(command == .end)
    }

    @Test("parse /end with leading whitespace")
    func parseEndWithLeadingWhitespace() {
        let command = parser.parse("  /end")
        #expect(command == .end)
    }

    @Test("parse /end ignores extra arguments")
    func parseEndIgnoresExtraArguments() {
        let command = parser.parse("/end now please")
        #expect(command == .end)
    }
}

// MARK: - Quit Command Parsing Tests

@Suite("Parse Quit Command")
struct ParseQuitCommandTests {

    let parser = CommandParser()

    @Test("parse /quit")
    func parseQuit() {
        let command = parser.parse("/quit")
        #expect(command == .quit)
    }

    @Test("parse /q (short form)")
    func parseQuitShortForm() {
        let command = parser.parse("/q")
        #expect(command == .quit)
    }

    @Test("parse /quit with trailing whitespace")
    func parseQuitWithTrailingWhitespace() {
        let command = parser.parse("/quit   ")
        #expect(command == .quit)
    }

    @Test("parse /quit with leading whitespace")
    func parseQuitWithLeadingWhitespace() {
        let command = parser.parse("  /quit")
        #expect(command == .quit)
    }

    @Test("parse /quit ignores extra arguments")
    func parseQuitIgnoresExtraArguments() {
        let command = parser.parse("/quit now")
        #expect(command == .quit)
    }

    // Note: /q short form whitespace/args tests removed as duplicates of /quit tests
}

// MARK: - Unknown Command Parsing Tests

@Suite("Parse Unknown Command")
struct ParseUnknownCommandTests {

    let parser = CommandParser()

    @Test("parse unknown slash command")
    func parseUnknownSlashCommand() {
        let command = parser.parse("/invalid")
        #expect(command == .unknown(input: "/invalid"))
    }

    @Test("parse regular text (no slash)")
    func parseRegularText() {
        let command = parser.parse("Hello world")
        #expect(command == .unknown(input: "Hello world"))
    }

    @Test("parse empty string")
    func parseEmptyString() {
        let command = parser.parse("")
        #expect(command == .unknown(input: ""))
    }

    @Test("parse whitespace only")
    func parseWhitespaceOnly() {
        let command = parser.parse("   ")
        #expect(command == .unknown(input: "   "))
    }

    @Test("parse unknown command preserves original input")
    func parseUnknownPreservesOriginalInput() {
        let originalInput = "  /unknown command with spaces  "
        let command = parser.parse(originalInput)
        #expect(command == .unknown(input: originalInput))
    }

    @Test("parse command-like text without slash prefix")
    func parseCommandLikeTextWithoutSlash() {
        let command = parser.parse("start something")
        #expect(command == .unknown(input: "start something"))
    }

    @Test("parse slash without command name")
    func parseSlashWithoutCommandName() {
        let command = parser.parse("/")
        #expect(command == .unknown(input: "/"))
    }

    @Test("parse slash with space only")
    func parseSlashWithSpaceOnly() {
        let command = parser.parse("/ ")
        #expect(command == .unknown(input: "/ "))
    }
}

// MARK: - Case Sensitivity Tests

@Suite("Case Sensitivity")
struct CaseSensitivityTests {

    let parser = CommandParser()

    @Test("parse /START (uppercase) is case insensitive")
    func parseStartUppercase() {
        let command = parser.parse("/START")
        #expect(command == .start(question: nil))
    }

    @Test("parse /Start (mixed case) is case insensitive")
    func parseStartMixedCase() {
        let command = parser.parse("/Start")
        #expect(command == .start(question: nil))
    }

    @Test("parse /PAUSE (uppercase) is case insensitive")
    func parsePauseUppercase() {
        let command = parser.parse("/PAUSE")
        #expect(command == .pause)
    }

    @Test("parse /END (uppercase) is case insensitive")
    func parseEndUppercase() {
        let command = parser.parse("/END")
        #expect(command == .end)
    }

    @Test("parse /QUIT (uppercase) is case insensitive")
    func parseQuitUppercase() {
        let command = parser.parse("/QUIT")
        #expect(command == .quit)
    }

    @Test("parse /Q (uppercase short form) is case insensitive")
    func parseQuitShortFormUppercase() {
        let command = parser.parse("/Q")
        #expect(command == .quit)
    }

    @Test("parse /sTaRt (random case) is case insensitive")
    func parseStartRandomCase() {
        let command = parser.parse("/sTaRt Design a cache")
        #expect(command == .start(question: "Design a cache"))
    }
}

// MARK: - Edge Cases Tests

@Suite("CommandParser Edge Cases")
struct CommandParserEdgeCaseTests {

    let parser = CommandParser()

    @Test("parse command with tab characters")
    func parseCommandWithTabs() {
        let command = parser.parse("/start\tDesign a cache")
        #expect(command == .start(question: "Design a cache"))
    }

    @Test("parse command with newline should handle gracefully")
    func parseCommandWithNewline() {
        // A newline in input should probably be treated as unknown
        let command = parser.parse("/start\nDesign")
        // The behavior here depends on implementation choice
        // Either: treat as start with question containing newline
        // Or: treat as unknown due to unexpected newline
        // We'll expect it treats only first line as command
        if case .start(let question) = command {
            // Acceptable: newline is part of question
            #expect(question?.contains("\n") == true || question == nil)
        } else if case .unknown = command {
            // Also acceptable: treated as invalid due to newline
        } else {
            Issue.record("Unexpected command type")
        }
    }

    @Test("parse very long input")
    func parseVeryLongInput() {
        let longQuestion = String(repeating: "x", count: 10000)
        let command = parser.parse("/start \(longQuestion)")
        if case .start(let question) = command {
            #expect(question == longQuestion)
        } else {
            Issue.record("Expected .start case")
        }
    }

    @Test("parse unicode command argument")
    func parseUnicodeCommandArgument() {
        let command = parser.parse("/start URL")
        #expect(command == .start(question: "URL"))
    }

    @Test("parse emoji in command argument")
    func parseEmojiInCommandArgument() {
        let command = parser.parse("/start Design a system")
        if case .start(let question) = command {
            #expect(question?.contains("system") == true)
        } else {
            Issue.record("Expected .start case")
        }
    }

    @Test("parse command with multiple spaces between parts")
    func parseCommandWithMultipleSpaces() {
        let command = parser.parse("/start    Design    a    cache")
        // Multiple spaces between words should be normalized or preserved
        if case .start(let question) = command {
            #expect(question != nil)
            #expect(question!.contains("Design"))
            #expect(question!.contains("cache"))
        } else {
            Issue.record("Expected .start case")
        }
    }

    @Test("parse command with unclosed quote")
    func parseCommandWithUnclosedQuote() {
        let command = parser.parse("/start \"Design a cache")
        // Unclosed quote: either treat rest as question or return unknown
        // Implementation should handle this gracefully
        if case .start(let question) = command {
            // If treated as question, it should include the text after quote
            #expect(question?.contains("Design") == true)
        } else if case .unknown = command {
            // Treating as unknown is also acceptable
        } else {
            Issue.record("Unexpected command type")
        }
    }

    @Test("parse /startnow (no space) should be unknown")
    func parseStartNoSpace() {
        // /startnow is not the same as /start now
        let command = parser.parse("/startnow")
        #expect(command == .unknown(input: "/startnow"))
    }

    @Test("parse /paused (similar but different) should be unknown")
    func parsePausedIsUnknown() {
        let command = parser.parse("/paused")
        #expect(command == .unknown(input: "/paused"))
    }

    @Test("parse /ending (similar but different) should be unknown")
    func parseEndingIsUnknown() {
        let command = parser.parse("/ending")
        #expect(command == .unknown(input: "/ending"))
    }

    @Test("parse /quitting (similar but different) should be unknown")
    func parseQuittingIsUnknown() {
        let command = parser.parse("/quitting")
        #expect(command == .unknown(input: "/quitting"))
    }
}

// MARK: - Static Parse Method Tests

@Suite("CommandParser Static Method")
struct CommandParserStaticMethodTests {

    @Test("static parse method exists and works")
    func staticParseMethodExists() {
        // Test that a static parse method also works (optional enhancement)
        // If not implemented, this can be marked as expected to fail
        let command = CommandParser.parse("/start")
        #expect(command == .start(question: nil))
    }
}

// MARK: - Whitespace Handling Tests

@Suite("Whitespace Handling")
struct WhitespaceHandlingTests {

    let parser = CommandParser()

    @Test("leading whitespace is trimmed for command detection")
    func leadingWhitespaceIsTrimmed() {
        let command = parser.parse("   /start Design a cache")
        #expect(command == .start(question: "Design a cache"))
    }

    @Test("trailing whitespace is trimmed for command detection")
    func trailingWhitespaceIsTrimmed() {
        let command = parser.parse("/pause   ")
        #expect(command == .pause)
    }

    @Test("both leading and trailing whitespace are handled")
    func bothLeadingAndTrailingWhitespaceAreHandled() {
        let command = parser.parse("   /end   ")
        #expect(command == .end)
    }

    @Test("mixed whitespace characters are handled")
    func mixedWhitespaceCharactersAreHandled() {
        let command = parser.parse(" \t /quit \t ")
        #expect(command == .quit)
    }
}

// MARK: - Quote Parsing Tests

@Suite("Quote Parsing")
struct QuoteParsingTests {

    let parser = CommandParser()

    @Test("double quotes are stripped from question")
    func doubleQuotesAreStripped() {
        let command = parser.parse("/start \"Design a cache\"")
        #expect(command == .start(question: "Design a cache"))
    }

    @Test("single quotes are stripped from question")
    func singleQuotesAreStripped() {
        let command = parser.parse("/start 'Design a cache'")
        #expect(command == .start(question: "Design a cache"))
    }

    @Test("nested quotes are preserved inside")
    func nestedQuotesArePreserved() {
        let command = parser.parse("/start \"Design a 'distributed' cache\"")
        #expect(command == .start(question: "Design a 'distributed' cache"))
    }

    @Test("escaped quotes inside quoted string")
    func escapedQuotesInsideQuotedString() {
        // Test escaped quotes: /start "Design a \"URL\" shortener"
        let command = parser.parse("/start \"Design a \\\"URL\\\" shortener\"")
        // Expected: either preserve escaped quotes or interpret them
        if case .start(let question) = command {
            // The question should contain the URL word
            #expect(question?.contains("URL") == true)
        } else {
            Issue.record("Expected .start case")
        }
    }
}

// MARK: - Command Description Tests (Optional Enhancement)

@Suite("Command Description")
struct CommandDescriptionTests {

    @Test("start command has meaningful description")
    func startCommandHasMeaningfulDescription() {
        let command = Command.start(question: "Design a cache")
        let description = String(describing: command)
        #expect(description.contains("start") || description.contains("Start"))
    }

    @Test("pause command has meaningful description")
    func pauseCommandHasMeaningfulDescription() {
        let command = Command.pause
        let description = String(describing: command)
        #expect(description.contains("pause") || description.contains("Pause"))
    }

    @Test("unknown command includes the input in description")
    func unknownCommandIncludesInputInDescription() {
        let command = Command.unknown(input: "/foo")
        let description = String(describing: command)
        #expect(description.contains("unknown") || description.contains("Unknown") || description.contains("/foo"))
    }
}
