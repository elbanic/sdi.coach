// SessionTimerTests.swift
// TDD RED Phase: Failing tests for SessionTimer (30-minute countdown)
//
// Task 6.1.2: SessionTimer - 30-minute countdown timer with callbacks
//
// Requirements:
// 1. SessionTimer initialization with durationSeconds (default 1800 = 30 minutes)
// 2. Timer control: start(), pause(), resume(), stop()
// 3. State management: remainingSeconds, isRunning, isPaused
// 4. Callbacks: onTick (per second), onComplete (when timer ends)
// 5. Time formatting: formattedTime as "MM:SS"
//
// Implementation Notes:
// - Use Swift Concurrency (async/await, Task)
// - Actor or @MainActor for thread safety
// - Do NOT use actual Timer.scheduledTimer for testability
// - Inject TimeProvider protocol for testability
//
// Test framework: swift-testing (NOT XCTest)
// Feature: sdi.coach Session Management

import Testing
import Foundation
@testable import SDICoach

// MARK: - Task 6.1.2: SessionTimer Initialization Tests

@Suite("SessionTimer Initialization")
struct SessionTimerInitializationTests {

    @Test("SessionTimer should be initializable with default duration")
    func testDefaultInitialization() async {
        let timer = await SessionTimer()

        let remainingSeconds = await timer.remainingSeconds
        #expect(remainingSeconds == 1800) // 30 minutes
    }

    @Test("SessionTimer should be initializable with custom duration")
    func testCustomDurationInitialization() async {
        let timer = await SessionTimer(durationSeconds: 600) // 10 minutes

        let remainingSeconds = await timer.remainingSeconds
        #expect(remainingSeconds == 600)
    }

    @Test("SessionTimer should accept zero duration")
    func testZeroDurationInitialization() async {
        let timer = await SessionTimer(durationSeconds: 0)

        let remainingSeconds = await timer.remainingSeconds
        #expect(remainingSeconds == 0)
    }

    @Test("SessionTimer should accept very large duration")
    func testLargeDurationInitialization() async {
        let timer = await SessionTimer(durationSeconds: 86400) // 24 hours

        let remainingSeconds = await timer.remainingSeconds
        #expect(remainingSeconds == 86400)
    }

    @Test("SessionTimer should start in not running state")
    func testInitialNotRunningState() async {
        let timer = await SessionTimer()

        let isRunning = await timer.isRunning
        #expect(isRunning == false)
    }

    @Test("SessionTimer should start in not paused state")
    func testInitialNotPausedState() async {
        let timer = await SessionTimer()

        let isPaused = await timer.isPaused
        #expect(isPaused == false)
    }

    @Test("SessionTimer should accept injected TimeProvider for testability")
    func testInjectableTimeProvider() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 1800, timeProvider: mockTimeProvider)

        let remainingSeconds = await timer.remainingSeconds
        #expect(remainingSeconds == 1800)
    }
}

// MARK: - Task 6.1.2: SessionTimer Start Tests

@Suite("SessionTimer Start")
struct SessionTimerStartTests {

    @Test("start should set isRunning to true")
    func testStartSetsIsRunning() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()

        let isRunning = await timer.isRunning
        #expect(isRunning == true)
    }

    @Test("start should set isPaused to false")
    func testStartSetsIsPausedFalse() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()

        let isPaused = await timer.isPaused
        #expect(isPaused == false)
    }

    @Test("start when already running should be idempotent")
    func testStartWhenAlreadyRunning() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        let remainingBefore = await timer.remainingSeconds

        await timer.start() // Second start

        let remainingAfter = await timer.remainingSeconds
        let isRunning = await timer.isRunning

        #expect(isRunning == true)
        #expect(remainingAfter == remainingBefore) // Should not reset
    }

    @Test("start should not reset remainingSeconds")
    func testStartDoesNotResetRemainingSeconds() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 100, timeProvider: mockTimeProvider)

        // Manually decrement time somehow (via tick simulation)
        await timer.start()
        await mockTimeProvider.advanceTime(by: 10)
        await timer.tick() // Simulate one tick

        let remaining = await timer.remainingSeconds
        #expect(remaining < 100)

        // Start again should not reset
        await timer.start()
        let remainingAfterRestart = await timer.remainingSeconds
        #expect(remainingAfterRestart < 100)
    }
}

// MARK: - Task 6.1.2: SessionTimer Pause Tests

@Suite("SessionTimer Pause")
struct SessionTimerPauseTests {

    @Test("pause should set isPaused to true when running")
    func testPauseSetsIsPaused() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.pause()

        let isPaused = await timer.isPaused
        #expect(isPaused == true)
    }

    @Test("pause should keep isRunning as true (paused but not stopped)")
    func testPauseKeepsIsRunningTrue() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.pause()

        let isRunning = await timer.isRunning
        #expect(isRunning == true)
    }

    @Test("pause when not running should be no-op")
    func testPauseWhenNotRunning() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.pause()

        let isPaused = await timer.isPaused
        let isRunning = await timer.isRunning

        #expect(isPaused == false)
        #expect(isRunning == false)
    }

    @Test("pause should stop decrementing remainingSeconds")
    func testPauseStopsDecrementing() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.pause()

        let remainingAtPause = await timer.remainingSeconds

        // Advance mock time
        await mockTimeProvider.advanceTime(by: 10)

        // Manually try to tick (should be ignored when paused)
        await timer.tick()

        let remainingAfterTick = await timer.remainingSeconds
        #expect(remainingAfterTick == remainingAtPause)
    }

    @Test("pause when already paused should be idempotent")
    func testPauseWhenAlreadyPaused() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.pause()
        let pausedOnce = await timer.isPaused

        await timer.pause()
        let pausedTwice = await timer.isPaused

        #expect(pausedOnce == true)
        #expect(pausedTwice == true)
    }
}

// MARK: - Task 6.1.2: SessionTimer Resume Tests

@Suite("SessionTimer Resume")
struct SessionTimerResumeTests {

    @Test("resume should set isPaused to false")
    func testResumeSetsIsPausedFalse() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.pause()
        await timer.resume()

        let isPaused = await timer.isPaused
        #expect(isPaused == false)
    }

    @Test("resume should keep isRunning as true")
    func testResumeKeepsIsRunningTrue() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.pause()
        await timer.resume()

        let isRunning = await timer.isRunning
        #expect(isRunning == true)
    }

    @Test("resume when not paused should be no-op")
    func testResumeWhenNotPaused() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        let isPausedBefore = await timer.isPaused

        await timer.resume()

        let isPausedAfter = await timer.isPaused
        #expect(isPausedBefore == false)
        #expect(isPausedAfter == false)
    }

    @Test("resume when not running should be no-op")
    func testResumeWhenNotRunning() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.resume()

        let isRunning = await timer.isRunning
        let isPaused = await timer.isPaused

        #expect(isRunning == false)
        #expect(isPaused == false)
    }

    @Test("resume should allow time to continue decrementing")
    func testResumeAllowsDecrementing() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.pause()

        let remainingAtPause = await timer.remainingSeconds

        await timer.resume()
        await mockTimeProvider.advanceTime(by: 5)
        await timer.tick()

        let remainingAfterResume = await timer.remainingSeconds
        #expect(remainingAfterResume < remainingAtPause)
    }
}

// MARK: - Task 6.1.2: SessionTimer Stop Tests

@Suite("SessionTimer Stop")
struct SessionTimerStopTests {

    @Test("stop should set isRunning to false")
    func testStopSetsIsRunningFalse() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.stop()

        let isRunning = await timer.isRunning
        #expect(isRunning == false)
    }

    @Test("stop should set isPaused to false")
    func testStopSetsIsPausedFalse() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.pause()
        await timer.stop()

        let isPaused = await timer.isPaused
        #expect(isPaused == false)
    }

    @Test("stop should preserve remainingSeconds")
    func testStopPreservesRemainingSeconds() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await mockTimeProvider.advanceTime(by: 20)
        await timer.tick()

        let remainingBeforeStop = await timer.remainingSeconds

        await timer.stop()

        let remainingAfterStop = await timer.remainingSeconds
        #expect(remainingAfterStop == remainingBeforeStop)
    }

    @Test("stop when not running should be no-op")
    func testStopWhenNotRunning() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.stop()

        let isRunning = await timer.isRunning
        let remainingSeconds = await timer.remainingSeconds

        #expect(isRunning == false)
        #expect(remainingSeconds == 60)
    }

    @Test("stop should cancel any pending tick tasks")
    func testStopCancelsPendingTasks() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.stop()

        // Advance time and try to tick
        await mockTimeProvider.advanceTime(by: 10)
        await timer.tick()

        let remainingSeconds = await timer.remainingSeconds
        #expect(remainingSeconds == 60) // Should not have changed
    }
}

// MARK: - Task 6.1.2: SessionTimer State Management Tests

@Suite("SessionTimer State Management")
struct SessionTimerStateManagementTests {

    @Test("remainingSeconds should decrement every tick")
    func testRemainingSecondsDecrements() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 100, timeProvider: mockTimeProvider)

        await timer.start()

        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        let remaining = await timer.remainingSeconds
        #expect(remaining == 99)
    }

    @Test("remainingSeconds should not go below zero")
    func testRemainingSecondsNotBelowZero() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 5, timeProvider: mockTimeProvider)

        await timer.start()

        // Tick more times than duration
        for _ in 0..<10 {
            await mockTimeProvider.advanceTime(by: 1)
            await timer.tick()
        }

        let remaining = await timer.remainingSeconds
        #expect(remaining == 0)
    }

    @Test("isRunning should be true after start and false after stop")
    func testIsRunningStateTransitions() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        let initialRunning = await timer.isRunning
        #expect(initialRunning == false)

        await timer.start()
        let runningAfterStart = await timer.isRunning
        #expect(runningAfterStart == true)

        await timer.stop()
        let runningAfterStop = await timer.isRunning
        #expect(runningAfterStop == false)
    }

    @Test("isPaused should be true only when paused during running")
    func testIsPausedStateTransitions() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        let initialPaused = await timer.isPaused
        #expect(initialPaused == false)

        await timer.start()
        let pausedAfterStart = await timer.isPaused
        #expect(pausedAfterStart == false)

        await timer.pause()
        let pausedAfterPause = await timer.isPaused
        #expect(pausedAfterPause == true)

        await timer.resume()
        let pausedAfterResume = await timer.isPaused
        #expect(pausedAfterResume == false)
    }

    @Test("state should be consistent after multiple operations")
    func testStateConsistency() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 100, timeProvider: mockTimeProvider)

        // Complex sequence of operations
        await timer.start()
        await mockTimeProvider.advanceTime(by: 10)
        await timer.tick()
        await timer.pause()
        await timer.resume()
        await mockTimeProvider.advanceTime(by: 5)
        await timer.tick()
        await timer.stop()
        await timer.start()
        await mockTimeProvider.advanceTime(by: 3)
        await timer.tick()

        let isRunning = await timer.isRunning
        let isPaused = await timer.isPaused
        let remaining = await timer.remainingSeconds

        #expect(isRunning == true)
        #expect(isPaused == false)
        #expect(remaining < 100)
        #expect(remaining >= 0)
    }
}

// MARK: - Task 6.1.2: SessionTimer Callback Tests

@Suite("SessionTimer onTick Callback")
struct SessionTimerOnTickCallbackTests {

    @Test("onTick callback should be called on each tick")
    func testOnTickCalled() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        var tickCount = 0
        await timer.setOnTick { _ in
            tickCount += 1
        }

        await timer.start()

        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        #expect(tickCount == 1)
    }

    @Test("onTick callback should receive remainingSeconds")
    func testOnTickReceivesRemainingSeconds() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        var receivedSeconds: [Int] = []
        await timer.setOnTick { remaining in
            receivedSeconds.append(remaining)
        }

        await timer.start()

        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        #expect(receivedSeconds == [59, 58, 57])
    }

    @Test("onTick callback should not be called when paused")
    func testOnTickNotCalledWhenPaused() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        var tickCount = 0
        await timer.setOnTick { _ in
            tickCount += 1
        }

        await timer.start()
        await timer.pause()

        await mockTimeProvider.advanceTime(by: 5)
        await timer.tick()

        #expect(tickCount == 0)
    }

    @Test("onTick callback should not be called when stopped")
    func testOnTickNotCalledWhenStopped() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        var tickCount = 0
        await timer.setOnTick { _ in
            tickCount += 1
        }

        await timer.start()
        await timer.stop()

        await mockTimeProvider.advanceTime(by: 5)
        await timer.tick()

        #expect(tickCount == 0)
    }

    @Test("onTick callback should resume after unpause")
    func testOnTickResumesAfterUnpause() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        var tickCount = 0
        await timer.setOnTick { _ in
            tickCount += 1
        }

        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        await timer.pause()
        await mockTimeProvider.advanceTime(by: 5)
        await timer.tick() // Should not count

        await timer.resume()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        #expect(tickCount == 2)
    }

    @Test("onTick callback can be replaced")
    func testOnTickCanBeReplaced() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        var firstCallbackCalled = false
        var secondCallbackCalled = false

        await timer.setOnTick { _ in
            firstCallbackCalled = true
        }

        await timer.setOnTick { _ in
            secondCallbackCalled = true
        }

        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        #expect(firstCallbackCalled == false)
        #expect(secondCallbackCalled == true)
    }
}

@Suite("SessionTimer onComplete Callback")
struct SessionTimerOnCompleteCallbackTests {

    @Test("onComplete callback should be called when timer reaches zero")
    func testOnCompleteCalledAtZero() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 3, timeProvider: mockTimeProvider)

        var completeCalled = false
        await timer.setOnComplete {
            completeCalled = true
        }

        await timer.start()

        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        #expect(completeCalled == true)
    }

    @Test("onComplete callback should be called only once")
    func testOnCompleteCalledOnlyOnce() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 2, timeProvider: mockTimeProvider)

        var completeCount = 0
        await timer.setOnComplete {
            completeCount += 1
        }

        await timer.start()

        // Tick past zero
        for _ in 0..<5 {
            await mockTimeProvider.advanceTime(by: 1)
            await timer.tick()
        }

        #expect(completeCount == 1)
    }

    @Test("onComplete callback should not be called if stopped before zero")
    func testOnCompleteNotCalledIfStopped() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 10, timeProvider: mockTimeProvider)

        var completeCalled = false
        await timer.setOnComplete {
            completeCalled = true
        }

        await timer.start()
        await mockTimeProvider.advanceTime(by: 3)
        await timer.tick()
        await timer.stop()

        #expect(completeCalled == false)
    }

    @Test("onComplete callback should be called even when paused at zero")
    func testOnCompleteCalledIfTimerReachesZero() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 1, timeProvider: mockTimeProvider)

        var completeCalled = false
        await timer.setOnComplete {
            completeCalled = true
        }

        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        // Complete should have been called when it reached zero
        #expect(completeCalled == true)
    }

    @Test("onComplete callback can be replaced")
    func testOnCompleteCanBeReplaced() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 1, timeProvider: mockTimeProvider)

        var firstCalled = false
        var secondCalled = false

        await timer.setOnComplete {
            firstCalled = true
        }

        await timer.setOnComplete {
            secondCalled = true
        }

        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        #expect(firstCalled == false)
        #expect(secondCalled == true)
    }

    @Test("onComplete should set isRunning to false")
    func testOnCompleteSetsIsRunningFalse() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 1, timeProvider: mockTimeProvider)

        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        let isRunning = await timer.isRunning
        #expect(isRunning == false)
    }
}

// MARK: - Task 6.1.2: SessionTimer Time Formatting Tests

@Suite("SessionTimer Time Formatting")
struct SessionTimerTimeFormattingTests {

    @Test("formattedTime should return MM:SS format")
    func testFormattedTimeFormat() async {
        let timer = await SessionTimer(durationSeconds: 1800)

        let formatted = await timer.formattedTime
        #expect(formatted == "30:00")
    }

    @Test("formattedTime should pad single digit minutes")
    func testFormattedTimePadsSingleDigitMinutes() async {
        let timer = await SessionTimer(durationSeconds: 300) // 5 minutes

        let formatted = await timer.formattedTime
        #expect(formatted == "05:00")
    }

    @Test("formattedTime should pad single digit seconds")
    func testFormattedTimePadsSingleDigitSeconds() async {
        let timer = await SessionTimer(durationSeconds: 65) // 1 min 5 sec

        let formatted = await timer.formattedTime
        #expect(formatted == "01:05")
    }

    @Test("formattedTime should handle zero")
    func testFormattedTimeZero() async {
        let timer = await SessionTimer(durationSeconds: 0)

        let formatted = await timer.formattedTime
        #expect(formatted == "00:00")
    }

    @Test("formattedTime should handle 59:59")
    func testFormattedTimeMaxMinutesSeconds() async {
        let timer = await SessionTimer(durationSeconds: 3599) // 59:59

        let formatted = await timer.formattedTime
        #expect(formatted == "59:59")
    }

    @Test("formattedTime should handle over an hour (clamp to MM:SS)")
    func testFormattedTimeOverAnHour() async {
        let timer = await SessionTimer(durationSeconds: 7200) // 2 hours = 120:00

        let formatted = await timer.formattedTime
        // Could be "120:00" or we might want to clamp/format differently
        // For simplicity, assuming we allow minutes > 59
        #expect(formatted == "120:00")
    }

    @Test("formattedTime should update after tick")
    func testFormattedTimeUpdatesAfterTick() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 100, timeProvider: mockTimeProvider)

        let initialFormatted = await timer.formattedTime
        #expect(initialFormatted == "01:40")

        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        let afterTickFormatted = await timer.formattedTime
        #expect(afterTickFormatted == "01:39")
    }

    @Test("formattedTime various values")
    func testFormattedTimeVariousValues() async {
        // Test: 25:35 = 1535 seconds
        let timer1 = await SessionTimer(durationSeconds: 1535)
        let formatted1 = await timer1.formattedTime
        #expect(formatted1 == "25:35")

        // Test: 10:00 = 600 seconds
        let timer2 = await SessionTimer(durationSeconds: 600)
        let formatted2 = await timer2.formattedTime
        #expect(formatted2 == "10:00")

        // Test: 00:30 = 30 seconds
        let timer3 = await SessionTimer(durationSeconds: 30)
        let formatted3 = await timer3.formattedTime
        #expect(formatted3 == "00:30")
    }
}

// MARK: - Task 6.1.2: SessionTimer Reset Tests

@Suite("SessionTimer Reset")
struct SessionTimerResetTests {

    @Test("reset should restore remainingSeconds to original duration")
    func testResetRestoresRemainingSeconds() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 100, timeProvider: mockTimeProvider)

        await timer.start()
        await mockTimeProvider.advanceTime(by: 50)
        for _ in 0..<50 {
            await timer.tick()
        }

        await timer.reset()

        let remaining = await timer.remainingSeconds
        #expect(remaining == 100)
    }

    @Test("reset should stop the timer")
    func testResetStopsTimer() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 100, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.reset()

        let isRunning = await timer.isRunning
        #expect(isRunning == false)
    }

    @Test("reset should clear isPaused")
    func testResetClearsIsPaused() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 100, timeProvider: mockTimeProvider)

        await timer.start()
        await timer.pause()
        await timer.reset()

        let isPaused = await timer.isPaused
        #expect(isPaused == false)
    }

    @Test("reset should allow restarting")
    func testResetAllowsRestart() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()
        await mockTimeProvider.advanceTime(by: 30)
        for _ in 0..<30 {
            await timer.tick()
        }
        await timer.reset()
        await timer.start()

        let isRunning = await timer.isRunning
        let remaining = await timer.remainingSeconds

        #expect(isRunning == true)
        #expect(remaining == 60)
    }

    @Test("reset should clear onComplete called flag")
    func testResetClearsOnCompleteFlag() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 2, timeProvider: mockTimeProvider)

        var completeCount = 0
        await timer.setOnComplete {
            completeCount += 1
        }

        // Run to completion
        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        #expect(completeCount == 1)

        // Reset and run again
        await timer.reset()
        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        #expect(completeCount == 2)
    }
}

// MARK: - Task 6.1.2: SessionTimer Edge Cases Tests

@Suite("SessionTimer Edge Cases")
struct SessionTimerEdgeCasesTests {

    @Test("timer with 1 second duration should complete after 1 tick")
    func testOneSecondDuration() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 1, timeProvider: mockTimeProvider)

        var completeCalled = false
        await timer.setOnComplete {
            completeCalled = true
        }

        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        let remaining = await timer.remainingSeconds
        #expect(remaining == 0)
        #expect(completeCalled == true)
    }

    @Test("timer with 0 second duration should complete immediately on start")
    func testZeroSecondDuration() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 0, timeProvider: mockTimeProvider)

        var completeCalled = false
        await timer.setOnComplete {
            completeCalled = true
        }

        await timer.start()

        // Complete should be called immediately or on first tick check
        #expect(completeCalled == true)
    }

    @Test("rapid start/stop should not cause issues")
    func testRapidStartStop() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        for _ in 0..<100 {
            await timer.start()
            await timer.stop()
        }

        let isRunning = await timer.isRunning
        let remaining = await timer.remainingSeconds

        #expect(isRunning == false)
        #expect(remaining == 60)
    }

    @Test("rapid pause/resume should not cause issues")
    func testRapidPauseResume() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 60, timeProvider: mockTimeProvider)

        await timer.start()

        for _ in 0..<100 {
            await timer.pause()
            await timer.resume()
        }

        let isRunning = await timer.isRunning
        let isPaused = await timer.isPaused

        #expect(isRunning == true)
        #expect(isPaused == false)
    }

    @Test("tick when time already at zero should be no-op")
    func testTickAtZero() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 1, timeProvider: mockTimeProvider)

        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        // Timer is now at 0
        let remainingBefore = await timer.remainingSeconds
        #expect(remainingBefore == 0)

        // Another tick should not affect anything
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        let remainingAfter = await timer.remainingSeconds
        #expect(remainingAfter == 0)
    }

    @Test("multiple callbacks should not interfere")
    func testMultipleCallbacks() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 3, timeProvider: mockTimeProvider)

        var tickSeconds: [Int] = []
        var completeCalled = false

        await timer.setOnTick { remaining in
            tickSeconds.append(remaining)
        }

        await timer.setOnComplete {
            completeCalled = true
        }

        await timer.start()

        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        #expect(tickSeconds == [2, 1, 0])
        #expect(completeCalled == true)
    }
}

// MARK: - Task 6.1.2: SessionTimer Thread Safety Tests

@Suite("SessionTimer Thread Safety")
struct SessionTimerThreadSafetyTests {

    @Test("concurrent access should be safe")
    func testConcurrentAccess() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 1000, timeProvider: mockTimeProvider)

        await timer.start()

        await withTaskGroup(of: Void.self) { group in
            // Concurrent reads
            for _ in 0..<10 {
                group.addTask {
                    _ = await timer.remainingSeconds
                    _ = await timer.isRunning
                    _ = await timer.isPaused
                    _ = await timer.formattedTime
                }
            }

            // Concurrent operations
            for _ in 0..<10 {
                group.addTask {
                    await timer.pause()
                    await timer.resume()
                }
            }
        }

        // Should complete without crash
        let isRunning = await timer.isRunning
        #expect(isRunning == true || isRunning == false) // Either state is valid
    }

    @Test("concurrent ticks should be handled safely")
    func testConcurrentTicks() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 100, timeProvider: mockTimeProvider)

        await timer.start()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await mockTimeProvider.advanceTime(by: 1)
                    await timer.tick()
                }
            }
        }

        // Should complete without crash
        let remaining = await timer.remainingSeconds
        #expect(remaining >= 0)
        #expect(remaining <= 100)
    }
}

// MARK: - Task 6.1.2: SessionTimer Computed Properties Tests

@Suite("SessionTimer Computed Properties")
struct SessionTimerComputedPropertiesTests {

    @Test("elapsedSeconds should return correct value")
    func testElapsedSeconds() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 100, timeProvider: mockTimeProvider)

        await timer.start()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()
        await mockTimeProvider.advanceTime(by: 1)
        await timer.tick()

        let elapsed = await timer.elapsedSeconds
        #expect(elapsed == 3)
    }

    @Test("elapsedSeconds should be 0 for new timer")
    func testElapsedSecondsNew() async {
        let timer = await SessionTimer(durationSeconds: 100)

        let elapsed = await timer.elapsedSeconds
        #expect(elapsed == 0)
    }

    @Test("totalDurationSeconds should return original duration")
    func testTotalDurationSeconds() async {
        let timer = await SessionTimer(durationSeconds: 1800)

        let total = await timer.totalDurationSeconds
        #expect(total == 1800)
    }

    @Test("progressPercentage should return correct value")
    func testProgressPercentage() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 100, timeProvider: mockTimeProvider)

        await timer.start()
        for _ in 0..<50 {
            await mockTimeProvider.advanceTime(by: 1)
            await timer.tick()
        }

        let progress = await timer.progressPercentage
        #expect(progress >= 49.9)
        #expect(progress <= 50.1)
    }

    @Test("progressPercentage should be 0 for new timer")
    func testProgressPercentageNew() async {
        let timer = await SessionTimer(durationSeconds: 100)

        let progress = await timer.progressPercentage
        #expect(progress == 0.0)
    }

    @Test("progressPercentage should be 100 when complete")
    func testProgressPercentageComplete() async {
        let mockTimeProvider = MockTimeProvider()
        let timer = await SessionTimer(durationSeconds: 10, timeProvider: mockTimeProvider)

        await timer.start()
        for _ in 0..<10 {
            await mockTimeProvider.advanceTime(by: 1)
            await timer.tick()
        }

        let progress = await timer.progressPercentage
        #expect(progress == 100.0)
    }
}

// MARK: - Mock Types for SessionTimer Tests

/// Mock time provider for testable timer behavior
/// Conforms to TimeProviding protocol for dependency injection
actor MockTimeProvider: TimeProviding {
    private var currentTime: TimeInterval = 0
    private var elapsedSinceLastTick: TimeInterval = 0

    func now() async -> TimeInterval {
        return currentTime
    }

    func advanceTime(by seconds: TimeInterval) {
        currentTime += seconds
        elapsedSinceLastTick += seconds
    }

    func elapsedSinceTick() async -> TimeInterval {
        let elapsed = elapsedSinceLastTick
        elapsedSinceLastTick = 0
        return elapsed
    }

    func reset() {
        currentTime = 0
        elapsedSinceLastTick = 0
    }
}
