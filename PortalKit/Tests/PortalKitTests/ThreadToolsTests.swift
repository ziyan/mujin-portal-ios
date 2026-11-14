import Foundation
import Testing

@testable import PortalKit

/// Thread-native interactions: each question, approval, waiting item, artifact and todo says its thread, and each view shows its own.
@Suite struct ThreadToolsTests {
    @Test func theThreadIsAskedForOnlyOfAServerThatHasIt() async {
        let (connection, _) = scriptedConnection { _, _ in [:] }
        #expect(!(await connection.prepared(Documents.listQuestions)).contains("threadRootMessageId"))
        await connection.setThreadTools(true)
        for document in [Documents.listQuestions, Documents.listApprovals, Documents.listWaiting, Documents.listConversationArtifacts, Documents.listTodos] {
            #expect(await connection.prepared(document).contains("threadRootMessageId"), "\(document.prefix(50))")
        }
        #expect(ServerCapabilities(questionFieldNames: ["threadRootMessageId"]).offersThreadTools)
        #expect(!ServerCapabilities().offersThreadTools)
        #expect(ServerCapabilities(queryNames: ["ListConversationTodos"]).offersTodos)
    }

    @Test func eachViewShowsItsOwnTodosOpenFirst() {
        let todos = [
            ConversationTodo(id: "t1", title: "Check door 4", status: "done", createdAt: "2026-03-01T09:00:00Z"),
            ConversationTodo(id: "t2", title: "Order pads", status: "open", createdAt: "2026-03-01T10:00:00Z"),
            ConversationTodo(id: "t3", title: "Read the log", status: "open", createdAt: "2026-03-01T08:00:00Z", threadRootMessageId: "root01"),
        ]
        #expect(ThreadViews.todos(todos, inView: nil).map(\.id) == ["t2", "t1"])
        #expect(ThreadViews.todos(todos, inView: "root01").map(\.id) == ["t3"])
    }

    @Test func theMainHistoryPointsToTheThreadsWhereSomethingWaits() {
        let questions = [QuestionCard(id: "q1", question: "Which door?", threadRootMessageId: "root01")]
        let approvals = [ApprovalCard(id: "a1", toolName: "shell", threadRootMessageId: "root02"), ApprovalCard(id: "a2", toolName: "shell", threadRootMessageId: "root01")]
        #expect(ThreadViews.waitingThreads(questions: questions, approvals: approvals) == ["root01", "root02"])
        #expect(ThreadViews.threadToOpenOn(questions: questions, approvals: approvals) == "root01")
        let mainQuestion = QuestionCard(id: "q2", question: "Restart now?")
        #expect(ThreadViews.threadToOpenOn(questions: questions + [mainQuestion], approvals: approvals) == nil)
    }

    @Test func aThreadListsItsArtifactsAndThoseWhoseCardIsInItNewestFirst() {
        let artifacts = [
            ArtifactReference(id: "made-main", title: "Main", kind: .html, createdAt: "2026-03-01T09:00:00Z"),
            ArtifactReference(id: "made-here", title: "Here", kind: .html, threadRootMessageId: "root01", createdAt: "2026-03-01T10:00:00Z"),
            ArtifactReference(id: "card-here", title: "Card", kind: .markdown, createdAt: "2026-03-01T11:00:00Z"),
        ]
        #expect(ThreadViews.artifacts(artifacts, inView: "root01", cardIds: ["card-here"]).map(\.id) == ["card-here", "made-here"])
        #expect(ThreadViews.artifacts(artifacts, inView: nil, cardIds: []).map(\.id) == ["card-here", "made-main"])
    }

    @Test func artifactsMadeAtTheSameMomentGoByIdDescending() {
        let artifacts = [
            ArtifactReference(id: "artifact-a", title: "A", kind: .html, createdAt: "2026-03-01T09:00:00Z"),
            ArtifactReference(id: "artifact-c", title: "C", kind: .html, createdAt: "2026-03-01T09:00:00Z"),
            ArtifactReference(id: "artifact-b", title: "B", kind: .html, createdAt: "2026-03-01T08:00:00Z"),
            ArtifactReference(id: "artifact-d", title: "D", kind: .html),
        ]
        #expect(ThreadViews.newestFirst(artifacts).map(\.id) == ["artifact-c", "artifact-a", "artifact-b", "artifact-d"])
    }
}
