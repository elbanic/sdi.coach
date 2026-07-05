// ApplicationModeTests.swift
// TDD RED Phase: Failing tests for ApplicationMode state transitions
//
// Task 5.3.5: ApplicationMode State Transitions - State machine for interview session
//
// Test framework: swift-testing (NOT XCTest)
// Feature: sdi.coach TUI Components

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 5.3.5: ApplicationMode State Machine Tests

@Suite("ApplicationMode Definition")
struct ApplicationModeDefinitionTests {

    @Test("ApplicationMode should have idle case")
    func testIdleCase() {
        let mode: ApplicationMode = .idle
        #expect(mode == .idle)
    }

    @Test("ApplicationMode should have interviewing case")
    func testInterviewingCase() {
        let mode: ApplicationMode = .interviewing
        #expect(mode == .interviewing)
    }

    @Test("ApplicationMode should have paused case")
    func testPausedCase() {
        let mode: ApplicationMode = .paused
        #expect(mode == .paused)
    }

    @Test("ApplicationMode should have feedback case")
    func testFeedbackCase() {
        let mode: ApplicationMode = .feedback
        #expect(mode == .feedback)
    }

    @Test("ApplicationMode should be Sendable")
    func testSendable() async {
        let mode: ApplicationMode = .idle

        await withTaskGroup(of: ApplicationMode.self) { group in
            group.addTask {
                return mode  // Should compile with Sendable
            }

            for await result in group {
                #expect(result == .idle)
            }
        }
    }

    @Test("ApplicationMode should be Equatable")
    func testEquatable() {
        #expect(ApplicationMode.idle == ApplicationMode.idle)
        #expect(ApplicationMode.interviewing == ApplicationMode.interviewing)
        #expect(ApplicationMode.idle != ApplicationMode.interviewing)
    }
}

@Suite("ApplicationMode State Transitions")
struct ApplicationModeStateTransitionsTests {

    // MARK: - From Idle State

    @Test("Idle should transition to interviewing on /start")
    func testIdleToInterviewingOnStart() {
        var stateMachine = ApplicationStateMachine()
        #expect(stateMachine.currentMode == .idle)

        let result = stateMachine.transition(on: .start)

        #expect(result == true)
        #expect(stateMachine.currentMode == .interviewing)
    }

    @Test("Idle should not transition on /pause")
    func testIdleNoPauseTransition() {
        var stateMachine = ApplicationStateMachine()
        #expect(stateMachine.currentMode == .idle)

        let result = stateMachine.transition(on: .pause)

        #expect(result == false)
        #expect(stateMachine.currentMode == .idle)
    }

    @Test("Idle should not transition on /end")
    func testIdleNoEndTransition() {
        var stateMachine = ApplicationStateMachine()
        #expect(stateMachine.currentMode == .idle)

        let result = stateMachine.transition(on: .end)

        #expect(result == false)
        #expect(stateMachine.currentMode == .idle)
    }

    @Test("Idle should not transition on /resume")
    func testIdleNoResumeTransition() {
        var stateMachine = ApplicationStateMachine()
        #expect(stateMachine.currentMode == .idle)

        let result = stateMachine.transition(on: .resume)

        #expect(result == false)
        #expect(stateMachine.currentMode == .idle)
    }

    // MARK: - From Interviewing State

    @Test("Interviewing should transition to paused on /pause")
    func testInterviewingToPausedOnPause() {
        var stateMachine = ApplicationStateMachine(initialMode: .interviewing)

        let result = stateMachine.transition(on: .pause)

        #expect(result == true)
        #expect(stateMachine.currentMode == .paused)
    }

    @Test("Interviewing should transition to feedback on /end")
    func testInterviewingToFeedbackOnEnd() {
        var stateMachine = ApplicationStateMachine(initialMode: .interviewing)

        let result = stateMachine.transition(on: .end)

        #expect(result == true)
        #expect(stateMachine.currentMode == .feedback)
    }

    @Test("Interviewing should not transition on /start")
    func testInterviewingNoStartTransition() {
        var stateMachine = ApplicationStateMachine(initialMode: .interviewing)

        let result = stateMachine.transition(on: .start)

        #expect(result == false)
        #expect(stateMachine.currentMode == .interviewing)
    }

    @Test("Interviewing should not transition on /resume")
    func testInterviewingNoResumeTransition() {
        var stateMachine = ApplicationStateMachine(initialMode: .interviewing)

        let result = stateMachine.transition(on: .resume)

        #expect(result == false)
        #expect(stateMachine.currentMode == .interviewing)
    }

    // MARK: - From Paused State

    @Test("Paused should transition to interviewing on /resume")
    func testPausedToInterviewingOnResume() {
        var stateMachine = ApplicationStateMachine(initialMode: .paused)

        let result = stateMachine.transition(on: .resume)

        #expect(result == true)
        #expect(stateMachine.currentMode == .interviewing)
    }

    @Test("Paused should transition to interviewing on /start (as resume)")
    func testPausedToInterviewingOnStart() {
        var stateMachine = ApplicationStateMachine(initialMode: .paused)

        // /start in paused state should act as resume
        let result = stateMachine.transition(on: .start)

        #expect(result == true)
        #expect(stateMachine.currentMode == .interviewing)
    }

    @Test("Paused should transition to feedback on /end")
    func testPausedToFeedbackOnEnd() {
        var stateMachine = ApplicationStateMachine(initialMode: .paused)

        let result = stateMachine.transition(on: .end)

        #expect(result == true)
        #expect(stateMachine.currentMode == .feedback)
    }

    @Test("Paused should not transition on /pause")
    func testPausedNoPauseTransition() {
        var stateMachine = ApplicationStateMachine(initialMode: .paused)

        let result = stateMachine.transition(on: .pause)

        #expect(result == false)
        #expect(stateMachine.currentMode == .paused)
    }

    // MARK: - From Feedback State

    @Test("Feedback should transition to idle after completion")
    func testFeedbackToIdleOnComplete() {
        var stateMachine = ApplicationStateMachine(initialMode: .feedback)

        let result = stateMachine.transition(on: .complete)

        #expect(result == true)
        #expect(stateMachine.currentMode == .idle)
    }

    @Test("Feedback should not transition on /start")
    func testFeedbackNoStartTransition() {
        var stateMachine = ApplicationStateMachine(initialMode: .feedback)

        let result = stateMachine.transition(on: .start)

        #expect(result == false)
        #expect(stateMachine.currentMode == .feedback)
    }

    @Test("Feedback should not transition on /pause")
    func testFeedbackNoPauseTransition() {
        var stateMachine = ApplicationStateMachine(initialMode: .feedback)

        let result = stateMachine.transition(on: .pause)

        #expect(result == false)
        #expect(stateMachine.currentMode == .feedback)
    }

    @Test("Feedback should not transition on /end")
    func testFeedbackNoEndTransition() {
        var stateMachine = ApplicationStateMachine(initialMode: .feedback)

        let result = stateMachine.transition(on: .end)

        #expect(result == false)
        #expect(stateMachine.currentMode == .feedback)
    }
}

@Suite("ApplicationMode Full Workflow")
struct ApplicationModeFullWorkflowTests {

    @Test("Complete interview workflow: idle -> interviewing -> paused -> interviewing -> feedback -> idle")
    func testCompleteWorkflow() {
        var stateMachine = ApplicationStateMachine()

        // Start from idle
        #expect(stateMachine.currentMode == .idle)

        // Start interview
        _ = stateMachine.transition(on: .start)
        #expect(stateMachine.currentMode == .interviewing)

        // Pause
        _ = stateMachine.transition(on: .pause)
        #expect(stateMachine.currentMode == .paused)

        // Resume
        _ = stateMachine.transition(on: .resume)
        #expect(stateMachine.currentMode == .interviewing)

        // End interview
        _ = stateMachine.transition(on: .end)
        #expect(stateMachine.currentMode == .feedback)

        // Complete feedback
        _ = stateMachine.transition(on: .complete)
        #expect(stateMachine.currentMode == .idle)
    }

    @Test("Direct end workflow: idle -> interviewing -> feedback -> idle")
    func testDirectEndWorkflow() {
        var stateMachine = ApplicationStateMachine()

        _ = stateMachine.transition(on: .start)
        _ = stateMachine.transition(on: .end)
        _ = stateMachine.transition(on: .complete)

        #expect(stateMachine.currentMode == .idle)
    }

    @Test("Paused end workflow: idle -> interviewing -> paused -> feedback -> idle")
    func testPausedEndWorkflow() {
        var stateMachine = ApplicationStateMachine()

        _ = stateMachine.transition(on: .start)
        _ = stateMachine.transition(on: .pause)
        _ = stateMachine.transition(on: .end)
        _ = stateMachine.transition(on: .complete)

        #expect(stateMachine.currentMode == .idle)
    }

    @Test("Multiple pause/resume cycles")
    func testMultiplePauseResumeCycles() {
        var stateMachine = ApplicationStateMachine()

        _ = stateMachine.transition(on: .start)

        for _ in 0..<5 {
            _ = stateMachine.transition(on: .pause)
            #expect(stateMachine.currentMode == .paused)

            _ = stateMachine.transition(on: .resume)
            #expect(stateMachine.currentMode == .interviewing)
        }

        _ = stateMachine.transition(on: .end)
        #expect(stateMachine.currentMode == .feedback)
    }
}

@Suite("ApplicationMode Transition Events")
struct ApplicationModeTransitionEventsTests {

    @Test("StateEvent should have start case")
    func testStartEvent() {
        let event: StateEvent = .start
        #expect(event == .start)
    }

    @Test("StateEvent should have pause case")
    func testPauseEvent() {
        let event: StateEvent = .pause
        #expect(event == .pause)
    }

    @Test("StateEvent should have resume case")
    func testResumeEvent() {
        let event: StateEvent = .resume
        #expect(event == .resume)
    }

    @Test("StateEvent should have end case")
    func testEndEvent() {
        let event: StateEvent = .end
        #expect(event == .end)
    }

    @Test("StateEvent should have complete case")
    func testCompleteEvent() {
        let event: StateEvent = .complete
        #expect(event == .complete)
    }

    @Test("StateEvent should be Sendable")
    func testEventSendable() async {
        let event: StateEvent = .start

        await withTaskGroup(of: StateEvent.self) { group in
            group.addTask {
                return event
            }

            for await result in group {
                #expect(result == .start)
            }
        }
    }
}

@Suite("ApplicationMode Transition Validation")
struct ApplicationModeTransitionValidationTests {

    @Test("canTransition should return true for valid transitions")
    func testCanTransitionValid() {
        let stateMachine = ApplicationStateMachine()

        #expect(stateMachine.canTransition(on: .start) == true)
        #expect(stateMachine.canTransition(on: .pause) == false)
    }

    @Test("canTransition should return false for invalid transitions")
    func testCanTransitionInvalid() {
        let stateMachine = ApplicationStateMachine()

        #expect(stateMachine.canTransition(on: .pause) == false)
        #expect(stateMachine.canTransition(on: .end) == false)
        #expect(stateMachine.canTransition(on: .resume) == false)
    }

    @Test("availableTransitions should return valid events for current state")
    func testAvailableTransitions() {
        var stateMachine = ApplicationStateMachine()

        // In idle state
        var available = stateMachine.availableTransitions()
        #expect(available.contains(.start))
        #expect(!available.contains(.pause))

        // In interviewing state
        _ = stateMachine.transition(on: .start)
        available = stateMachine.availableTransitions()
        #expect(available.contains(.pause))
        #expect(available.contains(.end))
        #expect(!available.contains(.start))

        // In paused state
        _ = stateMachine.transition(on: .pause)
        available = stateMachine.availableTransitions()
        #expect(available.contains(.resume) || available.contains(.start))
        #expect(available.contains(.end))
    }
}

@Suite("ApplicationMode Callbacks")
struct ApplicationModeCallbacksTests {

    @Test("State machine should notify on transition")
    func testNotifyOnTransition() {
        var stateMachine = ApplicationStateMachine()
        var transitionHistory: [(ApplicationMode, ApplicationMode)] = []

        stateMachine.onTransition { from, to in
            transitionHistory.append((from, to))
        }

        _ = stateMachine.transition(on: .start)
        _ = stateMachine.transition(on: .pause)

        #expect(transitionHistory.count == 2)
        #expect(transitionHistory[0].0 == .idle && transitionHistory[0].1 == .interviewing)
        #expect(transitionHistory[1].0 == .interviewing && transitionHistory[1].1 == .paused)
    }

    @Test("State machine should not notify on failed transition")
    func testNoNotifyOnFailedTransition() {
        var stateMachine = ApplicationStateMachine()
        var notificationCount = 0

        stateMachine.onTransition { _, _ in
            notificationCount += 1
        }

        // Try invalid transitions
        _ = stateMachine.transition(on: .pause)  // Invalid in idle
        _ = stateMachine.transition(on: .end)    // Invalid in idle

        #expect(notificationCount == 0)
    }

    @Test("State machine should support multiple callbacks")
    func testMultipleCallbacks() {
        var stateMachine = ApplicationStateMachine()
        var count1 = 0
        var count2 = 0

        stateMachine.onTransition { _, _ in count1 += 1 }
        stateMachine.onTransition { _, _ in count2 += 1 }

        _ = stateMachine.transition(on: .start)

        #expect(count1 == 1)
        #expect(count2 == 1)
    }
}

@Suite("ApplicationMode Thread Safety")
struct ApplicationModeThreadSafetyTests {

    @Test("State machine should be thread-safe for reads")
    func testThreadSafeReads() async {
        let stateMachine = ApplicationStateMachine(initialMode: .interviewing)

        await withTaskGroup(of: ApplicationMode.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    return stateMachine.currentMode
                }
            }

            var modes: [ApplicationMode] = []
            for await mode in group {
                modes.append(mode)
            }

            // All reads should return same value
            for mode in modes {
                #expect(mode == .interviewing)
            }
        }
    }

    @Test("State machine should be thread-safe for transitions")
    func testThreadSafeTransitions() async {
        var stateMachine = ApplicationStateMachine()
        _ = stateMachine.transition(on: .start)

        // Note: This test checks that concurrent transitions don't crash
        // The final state depends on which transitions succeed
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    return stateMachine.transition(on: .pause)
                }
            }
            for _ in 0..<5 {
                group.addTask {
                    return stateMachine.transition(on: .end)
                }
            }
        }

        // Should be in a valid state (paused or feedback)
        let validEndStates: [ApplicationMode] = [.paused, .feedback, .interviewing]
        #expect(validEndStates.contains(stateMachine.currentMode))
    }
}

@Suite("ApplicationMode Reset")
struct ApplicationModeResetTests {

    @Test("State machine should support reset to idle")
    func testResetToIdle() {
        var stateMachine = ApplicationStateMachine()

        _ = stateMachine.transition(on: .start)
        _ = stateMachine.transition(on: .pause)

        stateMachine.reset()

        #expect(stateMachine.currentMode == .idle)
    }

    @Test("Reset should work from any state")
    func testResetFromAnyState() {
        let states: [ApplicationMode] = [.idle, .interviewing, .paused, .feedback]

        for state in states {
            var stateMachine = ApplicationStateMachine(initialMode: state)
            stateMachine.reset()
            #expect(stateMachine.currentMode == .idle)
        }
    }
}
