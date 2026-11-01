import Foundation
import Testing

@testable import PortalKit

@Suite struct CommunicationSenderTests {
    private func payload(kind: String, arguments: [String], chatId: String? = nil, conversationId: String? = nil) -> PushPayload {
        var portal: [String: Any] = ["userId": "user01", "kind": kind]
        if let chatId { portal["chatId"] = chatId }
        if let conversationId { portal["conversationId"] = conversationId }
        return PushPayload(userInfo: ["portal": portal, "aps": ["alert": ["loc-key": "x", "loc-args": arguments]]])!
    }

    @Test func aGroupMessageNamesTheAuthorAndTheGroup() throws {
        let sender = try #require(CommunicationSender(payload: payload(kind: "chat_message", arguments: ["Sam Sample", "Night shift", "Dock 4 is free"], chatId: "chat01"), assistantName: "Assistant"))
        #expect(sender.displayName == "Sam Sample")
        #expect(sender.groupName == "Night shift")
        #expect(sender.conversationIdentifier == "chat:chat01")
        #expect(sender.messageText == "Dock 4 is free")
        #expect(sender.initials == "SS")
    }

    @Test func aDirectMessageHasNoGroupName() throws {
        let sender = try #require(CommunicationSender(payload: payload(kind: "chat_message", arguments: ["Sam Sample", "Sam Sample", "Hi"], chatId: "chat02"), assistantName: "Assistant"))
        #expect(sender.groupName == nil)
    }

    @Test func theAssistantIsTheSenderOfItsOwnMessages() throws {
        let sender = try #require(CommunicationSender(payload: payload(kind: "agent_message", arguments: ["All quiet"], conversationId: "conversation01"), assistantName: "Assistant"))
        #expect(sender.isAssistant)
        #expect(sender.displayName == "Assistant")
        #expect(sender.conversationIdentifier == "conversation01")
        #expect(sender.avatarSubject == nil)
    }

    @Test func otherPushesAreNotMessages() {
        #expect(CommunicationSender(payload: payload(kind: "agent_job_failed", arguments: ["Nightly"]), assistantName: "Assistant") == nil)
    }

    @Test func theMemberOfThatNameGivesTheUserIdForThePicture() throws {
        let sender = try #require(CommunicationSender(payload: payload(kind: "chat_message", arguments: ["Sam Sample", "Night shift", "Hi"], chatId: "chat01"), assistantName: "Assistant"))
        let resolved = sender.resolving(members: [ChatMember(id: "m1", userId: "user02", userName: "Sam Sample")])
        #expect(resolved.userId == "user02")
        #expect(resolved.handle == "user02")
        #expect(resolved.avatarSubject == AvatarSubject(kind: .user, id: "user02"))
        #expect(sender.resolving(members: []).userId == nil)
    }
}
