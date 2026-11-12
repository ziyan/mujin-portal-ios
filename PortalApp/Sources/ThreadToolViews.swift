import PortalKit
import SwiftUI

/// TodoPanel is the assistant's todo list for one view, the main history's or a thread's, on a rule above where the person writes. Its
/// header says how many are open and folds the list away; open items come first, then done ones.
struct TodoPanel: View {
    let todos: [ConversationTodo]
    @State private var isFolded = false

    private var openCount: Int { todos.filter { !$0.isDone }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isFolded.toggle() }
            } label: {
                HStack {
                    Text(openCount > 0 ? "Todos \u{00B7} \(openCount)" : "Todos")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isFolded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(openCount > 0 ? "Todos, \(openCount) open" : "Todos"))
            .accessibilityHint(Text(isFolded ? "Shows the list" : "Hides the list"))
            .accessibilityIdentifier("todoPanelHeader")
            if !isFolded {
                ForEach(todos) { todo in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.footnote)
                            .foregroundStyle(todo.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .accessibilityLabel(todo.isDone ? Text("Done") : Text("Not done"))
                        Text(todo.title ?? "")
                            .font(.footnote)
                            .strikethrough(todo.isDone)
                            .foregroundStyle(todo.isDone ? .secondary : .primary)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todoPanel")
    }
}

/// WaitingInThreadLine is the main history's one line about a question or approval that waits in a thread, which opens the thread.
struct WaitingInThreadLine: View {
    let excerpt: String?
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.bubble")
                .font(.footnote)
                .foregroundStyle(Color.statusWarning)
                .accessibilityHidden(true)
            Group {
                if let excerpt, !excerpt.isEmpty {
                    Text("Waiting for you in a thread: \(excerpt)")
                } else {
                    Text("Waiting for you in a thread")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open thread", action: onOpen)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityIdentifier("openWaitingThreadButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("waitingInThreadLine")
    }
}
