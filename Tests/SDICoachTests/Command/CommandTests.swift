// CommandTests.swift
// Tests for Command enum
//
// Feature: Phase 5.1 Command System
// Task: 5.1.1 - Command enum implementation
//
// Requirements from PRD.md:
// - Command enum with cases: start(question:), pause, end, quit, unknown(input:)
// - Associated values for start (optional String) and unknown (String)
//
// Tests should FAIL initially - Command.swift does not exist yet.

import Testing
@testable import SDICoach

// MARK: - Command Enum Existence Tests

@Suite("Command Enum Definition")
struct CommandEnumDefinitionTests {

    @Test("Command enum exists and is accessible")
    func commandEnumExists() {
        // This test verifies the Command enum type exists
        // It will fail to compile until Command.swift is created
        let _: Command.Type = Command.self
    }

    @Test("Command has all required cases")
    func commandHasAllCases() {
        // Verify all cases can be instantiated
        let startWithQuestion: Command = .start(question: "Design a URL shortener")
        let startWithoutQuestion: Command = .start(question: nil)
        let pause: Command = .pause
        let end: Command = .end
        let quit: Command = .quit
        let unknown: Command = .unknown(input: "invalid")

        // These should not be equal to each other
        #expect(startWithQuestion != pause)
        #expect(startWithoutQuestion != end)
        #expect(pause != quit)
        #expect(end != unknown)
    }
}

// MARK: - Command Equality Tests

@Suite("Command Equality")
struct CommandEqualityTests {

    @Test("start commands with same question are equal")
    func startCommandsWithSameQuestionAreEqual() {
        let command1 = Command.start(question: "Design a cache")
        let command2 = Command.start(question: "Design a cache")
        #expect(command1 == command2)
    }

    @Test("start commands with different questions are not equal")
    func startCommandsWithDifferentQuestionsAreNotEqual() {
        let command1 = Command.start(question: "Design a cache")
        let command2 = Command.start(question: "Design a queue")
        #expect(command1 != command2)
    }

    @Test("start with nil question equals start with nil question")
    func startWithNilQuestionEqualsNil() {
        let command1 = Command.start(question: nil)
        let command2 = Command.start(question: nil)
        #expect(command1 == command2)
    }

    @Test("start with question is not equal to start without question")
    func startWithQuestionNotEqualToStartWithoutQuestion() {
        let command1 = Command.start(question: "Design a cache")
        let command2 = Command.start(question: nil)
        #expect(command1 != command2)
    }

    @Test("pause commands are equal")
    func pauseCommandsAreEqual() {
        let command1 = Command.pause
        let command2 = Command.pause
        #expect(command1 == command2)
    }

    @Test("end commands are equal")
    func endCommandsAreEqual() {
        let command1 = Command.end
        let command2 = Command.end
        #expect(command1 == command2)
    }

    @Test("quit commands are equal")
    func quitCommandsAreEqual() {
        let command1 = Command.quit
        let command2 = Command.quit
        #expect(command1 == command2)
    }

    @Test("unknown commands with same input are equal")
    func unknownCommandsWithSameInputAreEqual() {
        let command1 = Command.unknown(input: "foo")
        let command2 = Command.unknown(input: "foo")
        #expect(command1 == command2)
    }

    @Test("unknown commands with different inputs are not equal")
    func unknownCommandsWithDifferentInputsAreNotEqual() {
        let command1 = Command.unknown(input: "foo")
        let command2 = Command.unknown(input: "bar")
        #expect(command1 != command2)
    }

    @Test("different command types are not equal")
    func differentCommandTypesAreNotEqual() {
        let start = Command.start(question: nil)
        let pause = Command.pause
        let end = Command.end
        let quit = Command.quit
        let unknown = Command.unknown(input: "/start")

        #expect(start != pause)
        #expect(start != end)
        #expect(start != quit)
        #expect(start != unknown)
        #expect(pause != end)
        #expect(pause != quit)
        #expect(pause != unknown)
        #expect(end != quit)
        #expect(end != unknown)
        #expect(quit != unknown)
    }
}

// MARK: - Command Associated Value Tests

@Suite("Command Associated Values")
struct CommandAssociatedValueTests {

    @Test("start command stores question correctly")
    func startCommandStoresQuestion() {
        let question = "Design a distributed cache system"
        let command = Command.start(question: question)

        if case .start(let storedQuestion) = command {
            #expect(storedQuestion == question)
        } else {
            Issue.record("Expected .start case")
        }
    }

    @Test("start command stores nil question correctly")
    func startCommandStoresNilQuestion() {
        let command = Command.start(question: nil)

        if case .start(let storedQuestion) = command {
            #expect(storedQuestion == nil)
        } else {
            Issue.record("Expected .start case")
        }
    }

    @Test("unknown command stores input correctly")
    func unknownCommandStoresInput() {
        let input = "some random input"
        let command = Command.unknown(input: input)

        if case .unknown(let storedInput) = command {
            #expect(storedInput == input)
        } else {
            Issue.record("Expected .unknown case")
        }
    }

    @Test("start command preserves unicode in question")
    func startCommandPreservesUnicode() {
        let question = "Design a URL shortener service"
        let command = Command.start(question: question)

        if case .start(let storedQuestion) = command {
            #expect(storedQuestion == question)
        } else {
            Issue.record("Expected .start case")
        }
    }

    @Test("unknown command preserves empty string")
    func unknownCommandPreservesEmptyString() {
        let command = Command.unknown(input: "")

        if case .unknown(let storedInput) = command {
            #expect(storedInput == "")
        } else {
            Issue.record("Expected .unknown case")
        }
    }

    @Test("start command preserves very long question")
    func startCommandPreservesLongQuestion() {
        let longQuestion = String(repeating: "Design ", count: 1000)
        let command = Command.start(question: longQuestion)

        if case .start(let storedQuestion) = command {
            #expect(storedQuestion == longQuestion)
        } else {
            Issue.record("Expected .start case")
        }
    }
}

// MARK: - Command Pattern Matching Tests

@Suite("Command Pattern Matching")
struct CommandPatternMatchingTests {

    @Test("switch exhaustively matches all cases")
    func switchExhaustivelyMatchesAllCases() {
        let commands: [Command] = [
            .start(question: "test"),
            .start(question: nil),
            .answer,
            .pause,
            .end,
            .quit,
            .unknown(input: "test")
        ]

        for command in commands {
            let matched: Bool
            switch command {
            case .start:
                matched = true
            case .answer:
                matched = true
            case .pause:
                matched = true
            case .end:
                matched = true
            case .quit:
                matched = true
            case .unknown:
                matched = true
            }
            #expect(matched == true, "Command \(command) should be matched")
        }
    }

    @Test("if-case-let extracts start question")
    func ifCaseLetExtractsStartQuestion() {
        let command = Command.start(question: "Design a cache")

        if case .start(let question) = command {
            #expect(question == "Design a cache")
        } else {
            Issue.record("Should match .start case")
        }
    }

    @Test("if-case-let extracts unknown input")
    func ifCaseLetExtractsUnknownInput() {
        let command = Command.unknown(input: "/invalid")

        if case .unknown(let input) = command {
            #expect(input == "/invalid")
        } else {
            Issue.record("Should match .unknown case")
        }
    }
}

// MARK: - Command Edge Cases

@Suite("Command Edge Cases")
struct CommandEdgeCaseTests {

    @Test("start with empty string question is different from nil")
    func startWithEmptyStringIsDifferentFromNil() {
        let withEmpty = Command.start(question: "")
        let withNil = Command.start(question: nil)
        #expect(withEmpty != withNil)
    }

    @Test("start with whitespace-only question is preserved")
    func startWithWhitespaceOnlyIsPreserved() {
        let whitespaceQuestion = "   \t\n  "
        let command = Command.start(question: whitespaceQuestion)

        if case .start(let question) = command {
            #expect(question == whitespaceQuestion)
        } else {
            Issue.record("Expected .start case")
        }
    }

    @Test("unknown with newlines is preserved")
    func unknownWithNewlinesIsPreserved() {
        let inputWithNewlines = "line1\nline2\nline3"
        let command = Command.unknown(input: inputWithNewlines)

        if case .unknown(let input) = command {
            #expect(input == inputWithNewlines)
        } else {
            Issue.record("Expected .unknown case")
        }
    }

    @Test("start with special characters is preserved")
    func startWithSpecialCharactersIsPreserved() {
        let specialQuestion = "Design @#$%^&*() system"
        let command = Command.start(question: specialQuestion)

        if case .start(let question) = command {
            #expect(question == specialQuestion)
        } else {
            Issue.record("Expected .start case")
        }
    }
}
