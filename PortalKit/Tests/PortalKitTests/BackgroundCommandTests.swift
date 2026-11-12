import Foundation
import Testing

@testable import PortalKit

/// Background shell commands: each view counts and lists its own, only the owner may stop one, and the message that wakes the
/// assistant when one ends is not shown.
@Suite struct BackgroundCommandTests {
    private let running = BackgroundCommand(
        id: "c1", userId: "user01", command: "tail -f /var/log/planner.log", commandState: "running", stdoutTail: "line 1\nline 2\n",
        stderrTail: "warning: slow", startedAt: "2026-03-01T10:00:00Z")
    private let threadRunning = BackgroundCommand(
        id: "c2", threadRootMessageId: "root01", userId: "user02", command: "make test", commandState: "running", startedAt: "2026-03-01T10:05:00Z")
    private let finished = BackgroundCommand(
        id: "c3", userId: "user01", command: "du -sh /data", commandState: "exited", exitCode: 0, startedAt: "2026-03-01T09:00:00Z",
        finishedAt: "2026-03-01T09:01:05Z")

    @Test func eachViewCountsOnlyItsOwnRunningCommands() {
        let all = [finished, running, threadRunning]
        #expect(BackgroundCommandRules.runningCount(all, inView: nil) == 1)
        #expect(BackgroundCommandRules.runningCount(all, inView: "root01") == 1)
        #expect(BackgroundCommandRules.commands(all, inView: nil).map(\.id) == ["c1", "c3"])
    }

    @Test func onlyTheOwnerMayStopARunningCommand() {
        #expect(BackgroundCommandRules.canStop(running, currentUserId: "user01"))
        #expect(!BackgroundCommandRules.canStop(running, currentUserId: "user02"))
        #expect(!BackgroundCommandRules.canStop(finished, currentUserId: "user01"))
    }

    @Test func theTailShowsTheNewestOutputThenTheErrors() {
        #expect(running.outputTail == "line 1\nline 2\nwarning: slow")
        #expect(finished.elapsed() == 65)
        #expect(BackgroundCommandRules.clock(65) == "1:05")
        #expect(BackgroundCommandRules.clock(3_725) == "1:02:05")
    }

    @Test func theWakeMessageIsANoteNotABubble() {
        let note = Transcript.note(forUserText: "[Background command finished: make test]\nExit code 0.")
        #expect(note == .backgroundCommandFinished(command: "make test", report: "Exit code 0."))
    }

    @Test func theListIsAskedForOnlyWhereTheServerHasIt() {
        #expect(ServerCapabilities(queryNames: ["ListBackgroundCommands"]).offersBackgroundCommands)
        #expect(!ServerCapabilities().offersBackgroundCommands)
    }
}
