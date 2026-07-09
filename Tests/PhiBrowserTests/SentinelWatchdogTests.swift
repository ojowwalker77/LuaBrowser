// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import XCTest
@testable import Phi

@MainActor
final class SentinelWatchdogTests: XCTestCase {
    private let sentinelBundleID = "com.phibrowser.Sentinel"

    /// Poll interval used in tests. The fake `sleep` parks (suspends) any
    /// duration at or above `pollParkThreshold`, so the backstop poll loop
    /// never hot-spins on the immediate-return fake sleep and never records a
    /// duration into `recordedSleeps` (keeping recovery-timing assertions clean).
    private let pollInterval: TimeInterval = 3600
    private let pollParkThreshold: TimeInterval = 1000

    private var sentinelAlive = false
    private var launchCount = 0
    private var recordedSleeps: [TimeInterval] = []
    private var fakeNow = Date(timeIntervalSince1970: 1_778_620_000)
    private var notificationCenter = NotificationCenter()
    private var onSleep: ((TimeInterval) -> Void)?
    private var watchdog: SentinelWatchdog!

    override func setUp() {
        super.setUp()
        sentinelAlive = false
        launchCount = 0
        recordedSleeps = []
        fakeNow = Date(timeIntervalSince1970: 1_778_620_000)
        notificationCenter = NotificationCenter()
        onSleep = nil
        watchdog = nil
    }

    override func tearDown() {
        watchdog?.stop()
        watchdog = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testDeathSignalDebounceStillDeadLaunchesOnce() async {
        let watchdog = makeWatchdog()
        watchdog.start()

        await deliverDeathAndAwaitRecovery()

        XCTAssertEqual(launchCount, 1)
        XCTAssertEqual(recordedSleeps, [0.5]) // debounce only; first relaunch is immediate
        XCTAssertEqual(watchdog.attemptCount, 1)
    }

    func testStopThenDeathSignalDoesNotLaunch() async {
        let watchdog = makeWatchdog()
        watchdog.start()
        watchdog.stop()

        await deliverDeathAndAwaitRecovery()

        XCTAssertEqual(launchCount, 0)
        XCTAssertNil(watchdog.recoveryTask)
    }

    func testRecoveredDuringDebounceDoesNotLaunch() async {
        let watchdog = makeWatchdog()
        watchdog.start()

        // Sentinel comes back on its own while the debounce is in flight.
        onSleep = { [weak self] _ in self?.sentinelAlive = true }

        await deliverDeathAndAwaitRecovery()

        XCTAssertEqual(launchCount, 0)
    }

    func testRapidDeathsBackoffDelaysGrow() async {
        let watchdog = makeWatchdog(backoffCap: 8)
        watchdog.start()

        // 1st death: immediate relaunch, no backoff sleep.
        await deliverDeathAndAwaitRecovery()
        XCTAssertEqual(recordedSleeps, [0.5])
        recordedSleeps.removeAll()

        // 2nd death: backoff 1s.
        await deliverDeathAndAwaitRecovery()
        XCTAssertEqual(recordedSleeps, [0.5, 1])
        recordedSleeps.removeAll()

        // 3rd death: backoff 2s.
        await deliverDeathAndAwaitRecovery()
        XCTAssertEqual(recordedSleeps, [0.5, 2])
        recordedSleeps.removeAll()

        // 4th death: backoff 4s.
        await deliverDeathAndAwaitRecovery()
        XCTAssertEqual(recordedSleeps, [0.5, 4])

        XCTAssertEqual(launchCount, 4)
        XCTAssertEqual(watchdog.attemptCount, 4)
    }

    func testBackoffDelayCapsAtInjectedCap() async {
        let watchdog = makeWatchdog(backoffCap: 3)
        watchdog.start()

        // Drive deaths past the point where pow(2, n) would exceed the cap.
        let expectedBackoffs: [TimeInterval?] = [nil, 1, 2, 3, 3] // nil = immediate (delay 0)
        for expected in expectedBackoffs {
            recordedSleeps.removeAll()
            await deliverDeathAndAwaitRecovery()
            if let expected {
                XCTAssertEqual(recordedSleeps, [0.5, expected])
            } else {
                XCTAssertEqual(recordedSleeps, [0.5])
            }
        }

        XCTAssertEqual(launchCount, 5)
    }

    func testStabilityResetRelaunchesImmediately() async {
        let stabilityWindow: TimeInterval = 600
        let watchdog = makeWatchdog(backoffCap: 8, stabilityWindow: stabilityWindow)
        watchdog.start()

        // Two rapid deaths build up the attempt counter (delays 0 then 1).
        await deliverDeathAndAwaitRecovery()
        await deliverDeathAndAwaitRecovery()
        XCTAssertEqual(watchdog.attemptCount, 2)

        // A death well past the stability window resets the counter → immediate.
        fakeNow = fakeNow.addingTimeInterval(stabilityWindow + 1)
        recordedSleeps.removeAll()
        await deliverDeathAndAwaitRecovery()

        XCTAssertEqual(recordedSleeps, [0.5]) // debounce only; no backoff sleep
        XCTAssertEqual(watchdog.attemptCount, 1)
        XCTAssertEqual(launchCount, 3)
    }

    func testPollPathDiscoversDeadSentinelLaunches() async {
        let watchdog = makeWatchdog()
        watchdog.start()

        // Exercise the poll body directly (the real loop uses a 60s timer).
        watchdog.performPollCheck()
        await watchdog.recoveryTask?.value

        XCTAssertEqual(launchCount, 1)
    }

    func testOverlappingDeathSignalsSingleLaunch() async {
        let watchdog = makeWatchdog()
        watchdog.start()

        // Two death signals before the first recovery completes: single-flight.
        watchdog.handlePossibleSentinelTermination(bundleID: sentinelBundleID)
        watchdog.handlePossibleSentinelTermination(bundleID: sentinelBundleID)
        await watchdog.recoveryTask?.value

        XCTAssertEqual(launchCount, 1)
    }

    // MARK: - Helpers

    private func deliverDeathAndAwaitRecovery() async {
        watchdog.handlePossibleSentinelTermination(bundleID: sentinelBundleID)
        await watchdog.recoveryTask?.value
    }

    private func makeWatchdog(
        debounceInterval: TimeInterval = 0.5,
        backoffCap: TimeInterval = 8,
        stabilityWindow: TimeInterval = 600
    ) -> SentinelWatchdog {
        let watchdog = SentinelWatchdog(
            isRunningProvider: { [weak self] in self?.sentinelAlive ?? false },
            launcher: { [weak self] in self?.launchCount += 1 },
            workspaceNotificationCenter: notificationCenter,
            sentinelBundleIDProvider: { [weak self] in self?.sentinelBundleID ?? "" },
            now: { [weak self] in self?.fakeNow ?? Date() },
            sleep: { [weak self] duration in
                guard let self else { return }
                if duration >= self.pollParkThreshold {
                    // Backstop poll interval: park until cancelled.
                    try? await Task.sleep(nanoseconds: .max)
                    return
                }
                self.recordedSleeps.append(duration)
                self.onSleep?(duration)
                await Task.yield()
            },
            logger: { _ in },
            debounceInterval: debounceInterval,
            pollInterval: pollInterval,
            backoffCap: backoffCap,
            stabilityWindow: stabilityWindow
        )
        self.watchdog = watchdog
        return watchdog
    }
}
