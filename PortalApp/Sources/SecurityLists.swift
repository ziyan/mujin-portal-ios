import PortalKit
import SwiftUI

/// The six lists of the account's security, each as the words and calls its ManagedListView needs.
extension ManagedListSpec {
    private static func details(_ pairs: [(String, String?)]) -> [ManagedFact] {
        pairs.compactMap { pair in
            guard let value = pair.1, !value.isEmpty else { return nil }
            return ManagedFact(label: pair.0, value: value)
        }
    }

    private static func absolute(_ text: String?) -> String? {
        PortalDate.parse(text).map { $0.formatted(.dateTime.year().month().day().hour().minute()) }
    }

    static var sessions: ManagedListSpec {
        ManagedListSpec(
            title: "Sessions", emptyTitle: "No other sessions", emptySymbol: "iphone",
            emptyMessage: "Browsers signed in to Portal on the web show up here, and you can sign any of them out.",
            introduction: "This app's own sign-in is not listed. To end it, use Sign out in More.",
            removeTitle: "Revoke session",
            removeMessage: { item in String(localized: "\(item.title) is signed out right away and has to sign in again.") },
            load: { connection in
                let list = try await connection.sessions()
                let split = SignInRecords.splitCurrent(list)
                var sections: [ManagedSection] = []
                // The server names the session a request came in on only for a browser; for this app it names none, so none is called this device.
                if let current = split.current { sections.append(ManagedSection(id: "current", title: String(localized: "This device"), items: [sessionItem(current)])) }
                if !split.others.isEmpty {
                    sections.append(
                        ManagedSection(
                            id: "others", title: split.current == nil ? nil : String(localized: "Other devices"), items: split.others.map(sessionItem))
                    )
                }
                return sections
            },
            remove: { connection, identifier in try await connection.revokeSession(id: identifier) })
    }

    private static func sessionItem(_ record: SignInRecord) -> ManagedItem {
        let userAgent = (record.userAgent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let network = [record.ip, record.location?.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        var lines: [String] = []
        if !network.isEmpty { lines.append(network) }
        lines.append(
            AccountText.relative(record.usedAt).map { String(localized: "Last used \($0)") }
                ?? AccountText.relative(record.createdAt).map { String(localized: "Signed in \($0)") } ?? String(localized: "Never used"))
        return ManagedItem(
            id: record.id, title: record.deviceName ?? String(localized: "Unknown device"), lines: lines,
            facts: details([
                (String(localized: "Device"), userAgent), (String(localized: "Network address"), record.ip), (String(localized: "Place"), record.location?.text),
                (String(localized: "Signed in"), absolute(record.authorizedAt ?? record.createdAt)), (String(localized: "Last used"), absolute(record.usedAt)),
                (String(localized: "Ends"), absolute(record.expiresAt)),
            ]))
    }

    static var tokens: ManagedListSpec {
        ManagedListSpec(
            title: "API tokens", emptyTitle: "No API tokens", emptySymbol: "key",
            emptyMessage: "A token lets a script or a tool use Portal as you. Create one on the web and it is listed here.",
            introduction: "Anything holding a token can act as you until the token is revoked.",
            removeTitle: "Revoke token",
            removeMessage: { item in String(localized: "Anything using \(item.title) stops working right away.") },
            webPath: "/settings/tokens", webTitle: "Create a token on the web",
            webExplanation: "A token is shown once, when it is made, so it is created in Portal on the web. Come back to see it listed.",
            removeAllTitle: "Revoke all tokens", removeAllMessage: "Every script and tool using one of these stops working right away.",
            load: { connection in
                let tokens = try await connection.apiTokens()
                return tokens.isEmpty ? [] : [ManagedSection(id: "tokens", title: nil, items: tokens.map(tokenItem))]
            },
            remove: { connection, identifier in try await connection.revokeToken(id: identifier) },
            removeAll: { connection, identifiers in try await connection.revokeTokens(ids: identifiers) })
    }

    private static func tokenItem(_ record: SignInRecord) -> ManagedItem {
        var lines: [String] = []
        if let created = AccountText.added(record.createdAt) { lines.append(created) }
        lines.append(AccountText.lastUsed(record.usedAt))
        lines.append(AccountText.day(record.expiresAt).map { String(localized: "Expires \($0)") } ?? String(localized: "Does not expire"))
        let title = (record.comment ?? "").isEmpty ? String(localized: "API token") : record.comment!
        return ManagedItem(
            id: record.id, title: title, lines: lines,
            facts: details([
                (String(localized: "Created"), absolute(record.createdAt)), (String(localized: "Last used"), absolute(record.usedAt)),
                (String(localized: "Expires"), absolute(record.expiresAt)), (String(localized: "Last used from"), record.ip),
                (String(localized: "Place"), record.location?.text), (String(localized: "Used by"), record.userAgent),
            ]))
    }

    static var passkeys: ManagedListSpec {
        ManagedListSpec(
            title: "Passkeys", emptyTitle: "No passkeys", emptySymbol: "person.badge.key",
            emptyMessage: "A passkey signs you in with Face ID or a security key instead of an email link. Add one on the web.",
            renamePrompt: "Name", removeTitle: "Delete passkey",
            removeMessage: { item in String(localized: "\(item.title) can no longer be used to sign in. You can add it again on the web.") },
            webPath: "/settings/passkeys", webTitle: "Add a passkey on the web",
            webExplanation: "A passkey belongs to the website it is made on, so it is added in Portal on the web. Come back to see it listed.",
            load: { connection in
                let passkeys = try await connection.passkeys()
                return passkeys.isEmpty ? [] : [ManagedSection(id: "passkeys", title: nil, items: passkeys.map(passkeyItem))]
            },
            rename: { connection, identifier, name in try await connection.renamePasskey(id: identifier, name: name) },
            remove: { connection, identifier in try await connection.deletePasskey(id: identifier) })
    }

    private static func passkeyItem(_ passkey: Passkey) -> ManagedItem {
        var lines: [String] = []
        if let created = AccountText.added(passkey.createdAt) { lines.append(created) }
        lines.append(AccountText.lastUsed(passkey.usedAt))
        lines.append(passkey.isSynced ? String(localized: "Synced between your devices") : String(localized: "Stays on one device"))
        return ManagedItem(
            id: passkey.id, title: passkey.shownName, lines: lines,
            facts: details([
                (String(localized: "Added"), absolute(passkey.createdAt)), (String(localized: "Last used"), absolute(passkey.usedAt)),
                (String(localized: "Kept"), passkey.isSynced ? String(localized: "Synced between your devices") : String(localized: "On one device only")),
            ]),
            renameableName: passkey.shownName)
    }

    static var authorizedApps: ManagedListSpec {
        ManagedListSpec(
            title: "Authorized apps", emptyTitle: "No authorized apps", emptySymbol: "app.badge.checkmark",
            emptyMessage: "Apps you let sign in with Portal show up here, and you can take their access back.",
            removeTitle: "Revoke access",
            removeMessage: { item in String(localized: "\(item.title) is signed out and has to ask for your permission again.") },
            load: { connection in
                let apps = try await connection.authorizedApps()
                var sections: [ManagedSection] = []
                let thisApp = apps.filter(\.isThisApp)
                let others = apps.filter { !$0.isThisApp }
                if !thisApp.isEmpty {
                    sections.append(ManagedSection(id: "this", title: String(localized: "This app"), items: thisApp.map { appItem($0, isThisApp: true) }))
                }
                if !others.isEmpty {
                    sections.append(
                        ManagedSection(
                            id: "others", title: thisApp.isEmpty ? nil : String(localized: "Other apps"), items: others.map { appItem($0, isThisApp: false) }))
                }
                return sections
            },
            remove: { connection, identifier in try await connection.revokeAuthorizedApp(id: identifier) })
    }

    private static func scopeText(_ scopes: [String]?) -> String? {
        let words = (scopes ?? []).map { scope -> String in
            switch scope {
            case "api:read": String(localized: "read")
            case "api:write": String(localized: "write")
            default: scope
            }
        }
        return words.isEmpty ? nil : words.joined(separator: ", ")
    }

    private static func appItem(_ app: AuthorizedApp, isThisApp: Bool) -> ManagedItem {
        var lines: [String] = []
        if let scopes = scopeText(app.grantedScopes) { lines.append(String(localized: "Can \(scopes)")) }
        if let allowed = AccountText.day(app.createdAt) { lines.append(String(localized: "Allowed \(allowed)")) }
        return ManagedItem(
            id: app.id, title: app.shownName, lines: lines,
            facts: details([
                (String(localized: "Allowed"), absolute(app.createdAt)), (String(localized: "Can"), scopeText(app.grantedScopes)),
                (String(localized: "Application"), app.clientId),
            ]),
            // The consent of this app covers every phone and tablet signed in to the account, so ending it here would sign them all out.
            protectionNote: isThisApp
                ? String(localized: "Every phone and tablet signed in to Portal with this app shares this permission. To end the sign-in on this one, use Sign out in More.")
                : nil)
    }

    static var vpn: ManagedListSpec {
        ManagedListSpec(
            title: "VPN", emptyTitle: "No VPN devices", emptySymbol: "network",
            emptyMessage: "A VPN device can reach your controllers through Portal. Add one on the web and it is listed here.",
            renamePrompt: "Name", removeTitle: "Revoke access",
            removeMessage: { item in String(localized: "\(item.title) can no longer connect. It has to be added again on the web.") },
            webPath: "/settings/vpn", webTitle: "Add a device on the web",
            webExplanation: "The configuration for a new device is shown once, so it is made in Portal on the web. Come back to see it listed.",
            load: { connection in
                let peers = try await connection.wireGuardPeers()
                return peers.isEmpty ? [] : [ManagedSection(id: "peers", title: nil, items: peers.map(peerItem))]
            },
            rename: { connection, identifier, name in try await connection.renameWireGuardPeer(id: identifier, name: name) },
            remove: { connection, identifier in try await connection.revokeWireGuardPeer(id: identifier) })
    }

    private static func peerItem(_ peer: WireGuardPeer) -> ManagedItem {
        var lines: [String] = []
        if let key = WireGuardKey.abbreviated(peer.publicKey) { lines.append(String(localized: "Key \(key)")) }
        if let added = AccountText.added(peer.createdAt) { lines.append(added) }
        lines.append(AccountText.relative(peer.lastHandshakeAt).map { String(localized: "Last connected \($0)") } ?? String(localized: "Never connected"))
        return ManagedItem(
            id: peer.id, title: peer.shownName, lines: lines,
            facts: details([
                (String(localized: "Public key"), peer.publicKey), (String(localized: "Added"), absolute(peer.createdAt)),
                (String(localized: "Last connected"), absolute(peer.lastHandshakeAt)),
            ]),
            renameableName: peer.shownName)
    }

    static var sshKeys: ManagedListSpec {
        ManagedListSpec(
            title: "SSH keys", emptyTitle: "No SSH keys", emptySymbol: "terminal",
            emptyMessage: "A public key lets you sign in to a controller over SSH. Add one on the web and it is listed here.",
            renamePrompt: "Name", removeTitle: "Revoke key",
            removeMessage: { item in String(localized: "\(item.title) can no longer be used to sign in over SSH.") },
            webPath: "/settings/ssh", webTitle: "Add a key on the web",
            webExplanation: "Adding a key is done in Portal on the web, where it can be pasted in. Come back to see it listed.",
            load: { connection in
                let keys = try await connection.sshKeys()
                return keys.isEmpty ? [] : [ManagedSection(id: "keys", title: nil, items: keys.map(keyItem))]
            },
            rename: { connection, identifier, name in try await connection.renameSSHKey(id: identifier, name: name) },
            remove: { connection, identifier in try await connection.revokeSSHKey(id: identifier) })
    }

    private static func keyItem(_ key: SSHKey) -> ManagedItem {
        var lines: [String] = []
        if let fingerprint = key.fingerprint { lines.append(fingerprint) }
        if let added = AccountText.added(key.createdAt) { lines.append(added) }
        lines.append(AccountText.lastUsed(key.lastUsedAt))
        return ManagedItem(
            id: key.id, title: key.shownName, lines: lines,
            facts: details([
                (String(localized: "Fingerprint"), key.fingerprint), (String(localized: "Added"), absolute(key.createdAt)),
                (String(localized: "Last used"), absolute(key.lastUsedAt)), (String(localized: "Public key"), key.publicKey),
            ]),
            renameableName: key.shownName)
    }
}
