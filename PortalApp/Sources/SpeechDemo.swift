import Foundation

/// SpeechDemo is the demo's screens for dictation and reading aloud, served only on their own screens against a server that says it
/// has both. The thread screens share the data of ThreadDemo. All the words are invented.
enum SpeechDemo {
    static let screens: Set<String> = [
        "dictate-chat", "dictate-chat-listening", "dictate-chat-words", "dictate-conversation", "dictate-conversation-listening",
        "dictate-conversation-words", "dictate-thread-chat", "dictate-thread-conversation", "read-aloud-chat", "read-aloud-chat-playing",
        "read-aloud-conversation", "read-aloud-conversation-playing", "read-aloud-thread-chat", "read-aloud-thread-conversation",
    ]

    static func owns(_ screen: String?) -> Bool { screen.map { screens.contains($0) } ?? false }

    /// The conversation a screen opens, when it is not one of the thread screens (ThreadDemo opens those).
    static func conversationId(for screen: String?) -> String? {
        switch screen {
        case "dictate-chat", "dictate-chat-listening", "dictate-chat-words", "read-aloud-chat", "read-aloud-chat-playing": "chatconv01"
        case "dictate-conversation", "dictate-conversation-listening", "dictate-conversation-words", "read-aloud-conversation",
            "read-aloud-conversation-playing":
            "conversation01"
        default: nil
        }
    }

    private static func isThreadScreen(_ screen: String?) -> Bool { screen?.contains("-thread-") == true }

    /// Whether the screen shows the microphone on, with a live caption, in the view that is a thread or the view that is not.
    static func stagesListening(_ screen: String?, isThread: Bool) -> Bool {
        guard isThreadScreen(screen) == isThread else { return false }
        switch screen {
        case "dictate-chat-listening", "dictate-conversation-listening", "dictate-thread-chat", "dictate-thread-conversation": return true
        default: return false
        }
    }

    /// Whether the screen shows dictated words already in the box.
    static func stagesWords(_ screen: String?) -> Bool {
        screen == "dictate-chat-words" || screen == "dictate-conversation-words"
    }

    /// The message a screen shows being read aloud, in the view that is a thread or the view that is not.
    static func messageToPlay(_ screen: String?, isThread: Bool) -> String? {
        guard isThreadScreen(screen) == isThread else { return nil }
        switch screen {
        case "read-aloud-chat-playing": return "c10"
        case "read-aloud-conversation-playing": return "m04"
        case "read-aloud-thread-chat": return "t02"
        case "read-aloud-thread-conversation": return "a04"
        default: return nil
        }
    }

    /// The message whose actions a screen holds open, to show Read aloud among them.
    static func messageToHold(_ screen: String?) -> String? {
        switch screen {
        case "read-aloud-chat": "c10"
        case "read-aloud-conversation": "m04"
        default: nil
        }
    }

    /// The fields of the voice setting the demo server's schema has, with the two availability fields.
    static let voiceSettingFieldNames = [
        "speechVoice", "speechVoices", "defaultSpeechVoice", "previewText", "isDictationAvailable", "isReadAloudAvailable",
    ]
}
