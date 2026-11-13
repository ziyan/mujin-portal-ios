import Foundation

/// BackgroundCommand is a shell command the assistant runs in the background: started that way, or moved there when it ran long.
public struct BackgroundCommand: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let conversationId: String?
    /// The thread the command was started in; nil for the main history.
    public let threadRootMessageId: String?
    /// Who the command runs for, who alone may stop it.
    public let userId: String?
    public let command: String?
    /// `running`, `exited`, `stopped`, `timed_out` or `lost`.
    public let commandState: String?
    public let isMovedFromInline: Bool?
    public let exitCode: Int?
    public let endReason: String?
    public let stdoutHead: String?
    public let stdoutTail: String?
    public let stderrHead: String?
    public let stderrTail: String?
    public let stdoutByteCount: Int64?
    public let stderrByteCount: Int64?
    public let stopRequestedAt: String?
    public let startedAt: String?
    public let finishedAt: String?

    public init(
        id: String, conversationId: String? = nil, threadRootMessageId: String? = nil, userId: String? = nil, command: String? = nil,
        commandState: String? = nil, isMovedFromInline: Bool? = nil, exitCode: Int? = nil, endReason: String? = nil, stdoutHead: String? = nil,
        stdoutTail: String? = nil, stderrHead: String? = nil, stderrTail: String? = nil, stdoutByteCount: Int64? = nil, stderrByteCount: Int64? = nil,
        stopRequestedAt: String? = nil, startedAt: String? = nil, finishedAt: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.threadRootMessageId = threadRootMessageId
        self.userId = userId
        self.command = command
        self.commandState = commandState
        self.isMovedFromInline = isMovedFromInline
        self.exitCode = exitCode
        self.endReason = endReason
        self.stdoutHead = stdoutHead
        self.stdoutTail = stdoutTail
        self.stderrHead = stderrHead
        self.stderrTail = stderrTail
        self.stdoutByteCount = stdoutByteCount
        self.stderrByteCount = stderrByteCount
        self.stopRequestedAt = stopRequestedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var isRunning: Bool { commandState == "running" }

    /// The newest of what the command wrote: the tail of its output, or all of it when it wrote little, then what it wrote as errors.
    public var outputTail: String {
        let output = (stdoutTail?.isEmpty == false ? stdoutTail : stdoutHead) ?? ""
        let errors = (stderrTail?.isEmpty == false ? stderrTail : stderrHead) ?? ""
        return [output, errors].filter { !$0.isEmpty }.joined(separator: output.hasSuffix("\n") || output.isEmpty ? "" : "\n")
    }

    /// How long the command ran, or has run so far.
    public func elapsed(now: Date = Date()) -> TimeInterval? {
        guard let started = PortalDate.parse(startedAt) else { return nil }
        let end = PortalDate.parse(finishedAt) ?? now
        return max(0, end.timeIntervalSince(started))
    }
}

/// BackgroundCommandRules decides what a view shows of the background commands.
public enum BackgroundCommandRules {
    /// The commands of one view, the main history's or a thread's, running first, then the newest.
    public static func commands(_ commands: [BackgroundCommand], inView viewThreadRootMessageId: String?) -> [BackgroundCommand] {
        commands
            .filter { ThreadRouting.normalized($0.threadRootMessageId) == ThreadRouting.normalized(viewThreadRootMessageId) }
            .sorted { first, second in
                if first.isRunning != second.isRunning { return first.isRunning }
                return (first.startedAt ?? "") > (second.startedAt ?? "")
            }
    }

    /// How many commands run in a view, which its header shows while there are any.
    public static func runningCount(_ commands: [BackgroundCommand], inView viewThreadRootMessageId: String?) -> Int {
        Self.commands(commands, inView: viewThreadRootMessageId).filter(\.isRunning).count
    }

    /// Whether the person may stop a command: their own, still running, not already asked to stop.
    public static func canStop(_ command: BackgroundCommand, currentUserId: String) -> Bool {
        command.isRunning && command.userId == currentUserId && (command.stopRequestedAt ?? "").isEmpty
    }

    /// How long something ran, as minutes and seconds, with hours once it passes one.
    public static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let rest = whole % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// The prefix of the message that wakes the assistant when a background command ends, which the transcript does not show.
    public static let wakePrefix = "[Background command finished:"
}

extension ServerCapabilities {
    /// Whether the assistant runs shell commands in the background, which the app lists and may stop.
    public var offersBackgroundCommands: Bool { offersQuery("ListBackgroundCommands") }
}

extension Documents {
    static let backgroundCommandFields = """
        id conversationId threadRootMessageId userId command commandState isMovedFromInline exitCode endReason stdoutHead stdoutTail stderrHead
        stderrTail stdoutByteCount stderrByteCount stopRequestedAt startedAt finishedAt
        """

    public static let listBackgroundCommands = """
        query ListBackgroundCommands($conversationId: String, $isRunningOnly: Boolean, $options: ListOptionsInput) {
          ListBackgroundCommands(conversationId: $conversationId, isRunningOnly: $isRunningOnly, options: $options) {
            backgroundCommands { \(backgroundCommandFields) }
            meta { totalCount }
          }
        }
        """

    public static let stopBackgroundCommand = """
        mutation StopBackgroundCommand($backgroundCommandId: String) {
          StopBackgroundCommand(backgroundCommandId: $backgroundCommandId) { backgroundCommand { \(backgroundCommandFields) } }
        }
        """

    static var backgroundCommandDocuments: [String] { [listBackgroundCommands, stopBackgroundCommand] }
}

extension Connection {
    /// The background commands of a conversation, every thread's together, the newest first; the 50 newest at most.
    public func backgroundCommands(conversationId: String) async throws -> [BackgroundCommand] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let backgroundCommands: [BackgroundCommand]? }
            let ListBackgroundCommands: List?
        }
        let variables: [String: JSONValue] = ["conversationId": .string(conversationId), "options": .object(["first": .number(50)])]
        return try await execute(Documents.listBackgroundCommands, variables: variables, as: Answer.self).ListBackgroundCommands?.backgroundCommands ?? []
    }

    /// Asks a running command to stop. Only its owner may.
    public func stopBackgroundCommand(id: String) async throws {
        _ = try await execute(Documents.stopBackgroundCommand, variables: ["backgroundCommandId": .string(id)], as: JSONValue.self)
    }
}
