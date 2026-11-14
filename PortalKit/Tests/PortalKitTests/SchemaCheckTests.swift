import Foundation
import Testing

@testable import PortalKit

/// Every GraphQL document the app sends must be valid against Portal's schema,
/// vendored in Schema/schema.json (refresh it with scripts/refresh-schema.sh).
@Suite struct SchemaCheckTests {
    static let schema: Schema = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try! Data(contentsOf: root.appendingPathComponent("Schema/schema.json"))
        return try! Schema(introspection: data)
    }()

    @Test func everyDocumentIsValid() throws {
        for document in Documents.all {
            let problems = try DocumentValidator(schema: Self.schema).problems(in: document)
            #expect(problems.isEmpty, "\(document.prefix(60)): \(problems)")
        }
    }

    /// Voice messages and calls are built against the contract the server plans. Each group is checked as soon as the
    /// vendored schema has it, and not before: an older schema is how the app learns the server does not offer them.
    @Test func theVoiceAndCallDocumentsAreValidOnceTheSchemaHasThem() throws {
        let schema = Self.schema
        let mutations = schema.types[schema.mutationType]?.fields ?? []
        if mutations.contains(where: { $0.name == "StartChatCall" }) {
            for document in Documents.chatCallDocuments {
                let problems = try DocumentValidator(schema: schema).problems(in: document)
                #expect(problems.isEmpty, "\(document.prefix(60)): \(problems)")
            }
        }
        if mutations.first(where: { $0.name == "SendMessage" })?.args.contains(where: { $0.name == "voiceMessage" }) == true {
            for document in Documents.chatVoiceMessageDocuments {
                let problems = try DocumentValidator(schema: schema).problems(in: document)
                #expect(problems.isEmpty, "\(document.prefix(60)): \(problems)")
            }
        }
        let messageFields = (schema.types["ConversationMessage"]?.fields ?? []).map(\.name)
        if messageFields.contains("voiceMessage") || messageFields.contains("call") {
            for document in Documents.all where document.contains("linkPreviewsRemovedAt") {
                let problems = try DocumentValidator(schema: schema).problems(in: Documents.withChatMedia(document))
                #expect(problems.isEmpty, "\(document.prefix(60)): \(problems)")
            }
        }
    }

    /// Message threads are built against the contract the server has, which the vendored schema holds: the fields and arguments are
    /// checked wherever the app adds them for a server that offers them.
    @Test func theThreadFieldsAreValidWhereTheyAreAdded() throws {
        var checked = 0
        for document in Documents.all where document.contains("linkPreviewsRemovedAt") || document.contains("OnConversationEvent(") {
            let problems = try DocumentValidator(schema: Self.schema).problems(in: Documents.withThreads(document))
            #expect(problems.isEmpty, "\(document.prefix(60)): \(problems)")
            checked += 1
        }
        #expect(checked >= 4)
    }

    /// An assistant answer's isOnBehalfOfMujinUser is a valid field wherever a message's fields are asked for.
    @Test func theOnBehalfOfStaffFieldIsValidWhereItIsAdded() throws {
        var checked = 0
        for document in Documents.all where document.contains("onBehalfOfUserName") {
            let prepared = Documents.withOnBehalfOfStaff(document)
            #expect(prepared.contains("onBehalfOfUserName isOnBehalfOfMujinUser"))
            let problems = try DocumentValidator(schema: Self.schema).problems(in: prepared)
            #expect(problems.isEmpty, "\(document.prefix(60)): \(problems)")
            checked += 1
        }
        #expect(checked >= 2)
    }

    /// A thread-native server's thread fields are valid on every interaction document they are added to.
    @Test func theThreadToolFieldsAreValidWhereTheyAreAdded() throws {
        var checked = 0
        for document in Documents.all where Documents.withThreadTools(document) != document {
            let problems = try DocumentValidator(schema: Self.schema).problems(in: Documents.withThreadTools(document))
            #expect(problems.isEmpty, "\(document.prefix(60)): \(problems)")
            checked += 1
        }
        #expect(checked >= 5)
    }

    /// The lists people pick from ask for foreground conversations only, a valid argument wherever it is added.
    @Test func theForegroundOnlyListsAreValid() throws {
        var checked = 0
        for document in Documents.all where document.contains("ListConversations(") {
            let prepared = Documents.withForegroundOnly(document)
            #expect(prepared.contains("ListConversations(isForegroundOnly: true, "))
            #expect(!prepared.contains("query ListConversations(isForegroundOnly"))
            #expect(prepared.components(separatedBy: "isForegroundOnly").count == 2, "The argument is added once.")
            #expect(Documents.withForegroundOnly(prepared) == prepared, "Preparing a document again adds nothing.")
            let problems = try DocumentValidator(schema: Self.schema).problems(in: prepared)
            #expect(problems.isEmpty, "\(document.prefix(60)): \(problems)")
            checked += 1
        }
        #expect(checked >= 2)
    }

    /// Internal notes: every document that asks for a message's or a chat's fields is valid with the internal-note fields added, on top
    /// of the thread fields, and SendMessage with its isInternal argument.
    @Test func theInternalNoteFieldsAreValidWhereTheyAreAdded() throws {
        var checked = 0
        for document in Documents.all where document.contains("linkPreviewsRemovedAt") || document.contains("lastMessageAuthorName") {
            let problems = try DocumentValidator(schema: Self.schema).problems(in: Documents.withInternalNotes(Documents.withThreads(document)))
            #expect(problems.isEmpty, "\(document.prefix(60)): \(problems)")
            checked += 1
        }
        #expect(checked >= 4)
        for document in Documents.all where document.contains("linkPreviewsRemovedAt") {
            let problems = try DocumentValidator(schema: Self.schema).problems(in: Documents.withChatReferences(Documents.withInternalNotes(document)))
            #expect(problems.isEmpty, "\(document.prefix(60)): \(problems)")
        }
        for document in [Documents.sendChatMessage, Documents.sendChatMessageWithMentions] {
            let problems = try DocumentValidator(schema: Self.schema).problems(in: Documents.withInternalArgument(document))
            #expect(problems.isEmpty, "\(problems)")
        }
    }

    /// Dictation and reading aloud are built against the contract the server plans: the two availability fields are checked as soon as
    /// the vendored schema has them, and not before. The app asks for them only of a server whose schema has them.
    @Test func theVoiceAvailabilityDocumentIsValidOnceTheSchemaHasTheFields() throws {
        let fields = (Self.schema.types["AgentVoiceSetting"]?.fields ?? []).map(\.name)
        for (isAskingForDictation, isAskingForReadAloud) in [(true, false), (false, true), (true, true)] {
            let hasFields = (!isAskingForDictation || fields.contains("isDictationAvailable")) && (!isAskingForReadAloud || fields.contains("isReadAloudAvailable"))
            guard hasFields else { continue }
            let document = Documents.agentVoiceAvailability(isAskingForDictation: isAskingForDictation, isAskingForReadAloud: isAskingForReadAloud)
            let problems = try DocumentValidator(schema: Self.schema).problems(in: document)
            #expect(problems.isEmpty, "\(document): \(problems)")
        }
    }

    @Test func theValidatorCatchesAWrongField() throws {
        let problems = try DocumentValidator(schema: Self.schema).problems(
            in: "query ListConversations($userId: String) { ListConversations(userId: $userId) { conversations { id noSuchField } } }")
        #expect(problems.contains { $0.contains("noSuchField") })
    }

    @Test func theValidatorCatchesAWrongArgumentAndAnUndeclaredVariable() throws {
        let problems = try DocumentValidator(schema: Self.schema).problems(
            in: "query GetConversation($id: String!) { GetConversation(conversationId: $conversationId, nope: 1) { id } }")
        #expect(problems.contains { $0.contains("nope") })
        #expect(problems.contains { $0.contains("$conversationId") })
    }

    @Test func theValidatorCatchesAMissingSelection() throws {
        let problems = try DocumentValidator(schema: Self.schema).problems(in: "query Me { Me }")
        #expect(problems.contains { $0.contains("needs a selection") })
    }

    @Test func theEventTypesPortalEmitsAreTheOnesTheAppFolds() {
        #expect(ConversationEvent.Kind(rawValue: "text_delta") != nil)
        #expect(ConversationEvent.Kind(rawValue: "run_error") != nil)
    }
}

// MARK: - a small GraphQL checker

struct Schema: Sendable {
    struct TypeReference: Decodable, Sendable {
        let kind: String
        let name: String?
        let ofType: Box?
        var baseName: String { name ?? ofType?.value.baseName ?? "" }
    }
    final class Box: Decodable, Sendable {
        let value: TypeReference
        required init(from decoder: Decoder) throws { value = try TypeReference(from: decoder) }
    }
    struct Argument: Decodable, Sendable {
        let name: String
        let type: TypeReference
    }
    struct Field: Decodable, Sendable {
        let name: String
        let args: [Argument]
        let type: TypeReference
    }
    struct SchemaType: Decodable, Sendable {
        let name: String
        let kind: String
        let fields: [Field]?
    }

    let types: [String: SchemaType]
    let queryType: String
    let mutationType: String
    let subscriptionType: String

    init(introspection: Data) throws {
        struct Root: Decodable {
            struct Data: Decodable {
                struct Inner: Decodable {
                    struct Named: Decodable { let name: String }
                    let types: [SchemaType]
                    let queryType: Named
                    let mutationType: Named
                    let subscriptionType: Named
                }
                let __schema: Inner
            }
            let data: Data
        }
        let root = try JSONDecoder().decode(Root.self, from: introspection).data.__schema
        types = Dictionary(uniqueKeysWithValues: root.types.map { ($0.name, $0) })
        queryType = root.queryType.name
        mutationType = root.mutationType.name
        subscriptionType = root.subscriptionType.name
    }
}

struct DocumentValidator {
    let schema: Schema

    struct Selection {
        let name: String
        let arguments: [(name: String, variable: String?)]
        let children: [Selection]?
    }

    func problems(in document: String) throws -> [String] {
        var parser = Parser(tokens: Parser.tokenize(document))
        let operation = try parser.parseOperation()
        var problems: [String] = []
        let rootName: String
        switch operation.kind {
        case "query": rootName = schema.queryType
        case "mutation": rootName = schema.mutationType
        default: rootName = schema.subscriptionType
        }
        check(operation.selections, on: rootName, declared: operation.variables, problems: &problems)
        return problems
    }

    private func check(_ selections: [Selection], on typeName: String, declared: [String: String], problems: inout [String]) {
        guard let type = schema.types[typeName] else {
            problems.append("unknown type \(typeName)")
            return
        }
        for selection in selections {
            if selection.name == "__typename" { continue }
            guard let field = type.fields?.first(where: { $0.name == selection.name }) else {
                problems.append("\(typeName) has no field \(selection.name)")
                continue
            }
            for argument in selection.arguments {
                guard let expected = field.args.first(where: { $0.name == argument.name }) else {
                    problems.append("\(typeName).\(selection.name) has no argument \(argument.name)")
                    continue
                }
                if let variable = argument.variable {
                    if let declaredType = declared[variable] {
                        if declaredType != expected.type.baseName {
                            problems.append("$\(variable) is \(declaredType) but \(selection.name)(\(argument.name):) takes \(expected.type.baseName)")
                        }
                    } else {
                        problems.append("$\(variable) is used but not declared")
                    }
                }
            }
            let returned = schema.types[field.type.baseName]
            let isObject = returned?.kind == "OBJECT"
            if isObject, selection.children == nil {
                problems.append("\(typeName).\(selection.name) needs a selection")
            } else if !isObject, selection.children != nil {
                problems.append("\(typeName).\(selection.name) is not an object and takes no selection")
            }
            if let children = selection.children {
                check(children, on: field.type.baseName, declared: declared, problems: &problems)
            }
        }
    }

    struct Operation {
        let kind: String
        let variables: [String: String]
        let selections: [Selection]
    }

    struct Parser {
        var tokens: [String]
        var position = 0

        init(tokens: [String]) { self.tokens = tokens }

        static func tokenize(_ text: String) -> [String] {
            var tokens: [String] = []
            var current = ""
            var isInComment = false
            var isInString = false
            func flush() {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            }
            for character in text {
                if isInComment {
                    if character == "\n" { isInComment = false }
                    continue
                }
                if isInString {
                    current.append(character)
                    if character == "\"" {
                        isInString = false
                        flush()
                    }
                    continue
                }
                switch character {
                case "#": flush(); isInComment = true
                case "\"": flush(); isInString = true; current.append(character)
                case "{", "}", "(", ")", ":", "$", "!", "[", "]", "=", ",", "@": flush(); if character != "," { tokens.append(String(character)) }
                case " ", "\n", "\t", "\r": flush()
                default: current.append(character)
                }
            }
            flush()
            return tokens
        }

        var peek: String? { position < tokens.count ? tokens[position] : nil }

        mutating func next() throws -> String {
            guard let token = peek else { throw PortalError.unreadableAnswer }
            position += 1
            return token
        }

        mutating func expect(_ token: String) throws {
            let found = try next()
            if found != token { throw PortalError.refused("expected \(token), found \(found)") }
        }

        mutating func parseOperation() throws -> Operation {
            let kind = try next()
            if let token = peek, token != "(", token != "{" { position += 1 }
            var variables: [String: String] = [:]
            if peek == "(" {
                try expect("(")
                while peek != ")" {
                    try expect("$")
                    let name = try next()
                    try expect(":")
                    variables[name] = try parseTypeBase()
                    if peek == "=" { position += 1; try skipValue() }
                }
                try expect(")")
            }
            return Operation(kind: kind, variables: variables, selections: try parseSelectionSet())
        }

        mutating func parseTypeBase() throws -> String {
            var base = ""
            if peek == "[" {
                position += 1
                base = try parseTypeBase()
                try expect("]")
            } else {
                base = try next()
            }
            if peek == "!" { position += 1 }
            return base
        }

        mutating func skipValue() throws {
            let token = try next()
            if token == "$" { position += 1; return }
            if token == "[" || token == "{" || token == "(" {
                let close = token == "[" ? "]" : token == "{" ? "}" : ")"
                var depth = 1
                while depth > 0 {
                    let inner = try next()
                    if inner == token { depth += 1 } else if inner == close { depth -= 1 }
                }
            }
        }

        mutating func parseSelectionSet() throws -> [Selection] {
            try expect("{")
            var selections: [Selection] = []
            while peek != "}" {
                var name = try next()
                if peek == ":" {
                    position += 1
                    name = try next()
                }
                var arguments: [(name: String, variable: String?)] = []
                if peek == "(" {
                    position += 1
                    while peek != ")" {
                        let argumentName = try next()
                        try expect(":")
                        if peek == "$" {
                            position += 1
                            arguments.append((argumentName, try next()))
                        } else {
                            try skipValue()
                            arguments.append((argumentName, nil))
                        }
                    }
                    try expect(")")
                }
                let children = peek == "{" ? try parseSelectionSet() : nil
                selections.append(Selection(name: name, arguments: arguments, children: children))
            }
            try expect("}")
            return selections
        }
    }
}
