import Foundation
import Testing

@testable import PortalKit

@Suite struct NavigationTests {
    @Test func customersGetMessagesSitesTicketsAndMore() {
        #expect(Navigation.sections(for: .customer) == [.assistant, .site, .tickets, .more])
        #expect(Navigation.home(for: .customer) == .assistant)
    }

    @Test func mujinUsersGetMonitoringFirstAndCustomersInPlaceOfSite() {
        #expect(Navigation.sections(for: .staff) == [.monitoring, .assistant, .tickets, .customers, .more])
        #expect(Navigation.home(for: .staff) == .monitoring)
    }

    @Test func noPersonaHasMoreThanFiveTabs() {
        for persona in [Persona.customer, .staff] { #expect(Navigation.sections(for: persona).count <= 5) }
    }

    @Test func theOrganizationDecidesThePersonaWhenItIsKnown() {
        #expect(Persona.resolve(isMujinOrganization: true, permissions: []) == .staff)
        #expect(Persona.resolve(isMujinOrganization: false, permissions: ["platform:administer"]) == .customer)
    }

    @Test func permissionsDecideWhenTheOrganizationCannotBeRead() {
        #expect(Persona.resolve(isMujinOrganization: nil, permissions: ["ticket:read", "monitoring:read"]) == .staff)
        #expect(Persona.resolve(isMujinOrganization: nil, permissions: ["ticket:read"]) == .customer)
        #expect(Persona.resolve(isMujinOrganization: nil, permissions: []) == .customer)
    }

    @Test func theProfileReadsThePersonaFromTheOrganization() async throws {
        let (connection, _) = scriptedConnection { operation, variables in
            switch operation {
            case "Me": return ["Me": ["id": "user01", "name": "Alex Example", "organizationId": "organization01", "permissions": ["ticket:read"]]]
            default: return ["GetOrganization": ["id": variables["organizationId"] as? String ?? "", "name": "Organization One", "isMujin": true]]
            }
        }
        let profile = try await connection.profile()
        #expect(profile.persona == .staff)
        #expect(profile.organizationName == "Organization One")
    }

    @Test func theProfileFallsBackToPermissionsWhenTheOrganizationFails() async throws {
        let transport = ScriptedTransport { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            if body.contains("GetOrganization") { return (200, ScriptedTransport.json(["errors": [["message": "not found"]]])) }
            return (200, ScriptedTransport.json(["data": ["Me": ["id": "user01", "organizationId": "organization01", "permissions": ["monitoring:read"]]]]))
        }
        let profile = try await Connection(account: makeAccount(), transport: transport).profile()
        #expect(profile.isMujinOrganization == nil)
        #expect(profile.persona == .staff)
    }

    @Test func capabilitiesIgnoreTheCaseOfTheFirstLetter() async {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "__schema": [
                    "queryType": ["fields": [["name": "listTickets"], ["name": "getAgentOversight"]]],
                    "mutationType": ["fields": [["name": "registerPushDevice"]]],
                    "subscriptionType": NSNull(),
                ]
            ]
        }
        let capabilities = await connection.capabilities()
        #expect(capabilities.offersQuery("ListTickets"))
        #expect(capabilities.offersAgentOversight)
        #expect(capabilities.offersPushRegistration)
        #expect(!capabilities.offersChats)
        #expect(!capabilities.offersNotificationFeed)
    }

    @Test func aServerThatRefusesIntrospectionOffersNothing() async {
        let transport = ScriptedTransport { _ in (200, ScriptedTransport.json(["errors": [["message": "introspection is disabled"]]])) }
        let capabilities = await Connection(account: makeAccount(), transport: transport).capabilities()
        #expect(capabilities == ServerCapabilities())
    }

    @Test func chatsAppearWhenTheServerListsThem() {
        #expect(ServerCapabilities(queryNames: ["ListChatCandidates"], mutationNames: ["StartDirectChat"]).offersChats)
    }
}
