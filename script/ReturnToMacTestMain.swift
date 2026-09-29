import Foundation

@main
struct ReturnToMacTestMain {
  static func main() throws {
    let tests = ReturnToMacTests()
    tests.testCompletionAndWatchdogHaveOnlyOneWinner()
    tests.testFailedCalibrationAttemptBreaksConsecutiveStreak()
    tests.testCalibrationDeadlineAndTwoDistinctConfirmations()
    tests.testBusyRefreshIsCoalescedAndResumesAfterWake()
    tests.testOnlyUniqueKnownDisplayAndTransportAreAccepted()
    tests.testOnlineRestIsOneShotAndCanRearm()
    tests.testUnknownOrDisabledBreaksSequence()
    tests.testLifecycleResetDisarms()
    tests.testTransportGapOnlyTriggersOnRecentDefiniteRest()
    tests.testRetentionExpiryAndClockReversalFailClosed()
    tests.testOnlineRepliesRefreshRetentionAndResetStillDisarms()
    try tests.testValidPacketIgnoresPadding()
    tests.testBadRepliesFailClosed()
    tests.testPacketEncoding()
    tests.testCancelledOperationNeverCommits()
    tests.testPS5ParserOnlyAcceptsStatusLine()
    print("PASS: 16 Return-to-Mac regression cases (bounded transport gaps, rule, parsers, cancellation, target policy, watchdog, calibration, refresh)")
  }
}
