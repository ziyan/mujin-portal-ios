# Chat rendering fixture

Messages that cover how a chat draws what people and the assistant write:
Markdown (headings, lists, task lists, tables, quotes, code), diagrams, math,
the assistant's charts, pictures, video, files, a voice message, link
previews, Portal's own cards, reference chips, mentions, replies, reactions,
an internal note, a thread, an edited and a deleted message, the assistant's
tool lines and its artifacts. Everything in it is invented.

The same set of messages is drawn by Portal's web app and its phone apps, so
the three are checked against one another. In this app the demo server loads
it (`PortalApp/Sources/ChatRenderingDemo.swift`), and
`PortalUITests/ChatRenderingTests.swift` pictures every message and checks
what it must show.

## Files

- `messages.json`: the messages and the link previews to cache.
- `assets/`: the files the messages attach. `make-assets.py` writes the same
  bytes again if one has to change (needs Pillow, ffmpeg and zip).

## messages.json

`people` names the two sides of the chat: `customer` (a customer's
organization administrator, the person reading) and `staff` (Mujin staff).
`linkPreviews` are cached link cards: `ok` with a title, description, site
name and optional picture from `assets/`, or `failed` with a reason. The demo
server answers with them, so nothing is fetched.

Each entry of `messages`:

| Field | Meaning |
|---|---|
| `key`, `title` | A stable name and what the message checks |
| `surface` | `chat` (a chat with people) or `assistant` (a conversation with the assistant) |
| `author` | `customer`, `staff` or `assistant` |
| `text` | Markdown, with `{{placeholders}}` the demo fills in |
| `attachments` | Files from `assets/`, attached in order |
| `voiceMessage` | A voice message: its file, length and 48 waveform levels from 0 to 1; it has no text |
| `isInternal` | An internal note, which only staff read |
| `viewer` | Who reads it; `customer` unless it says `staff` |
| `replyTo` | The `key` of the message it answers |
| `threadReplies` | Replies in its thread, each with an author and text |
| `reactions` | Emoji reactions and who gave them |
| `editedText` | Text it is edited to after it is sent |
| `isDeleted` | Deleted after it is sent |
| `toolCalls` | For the assistant: tool calls with their arguments and results |
| `artifact` | For the assistant: a document or page artifact from `assets/` |
| `pending` | A feature the web does not draw yet |
| `checks` | What must be true of the drawn message, written for the web's page |

The placeholders are `ticketSequence`, `siteId`, `siteName`, `cellId`,
`cellName`, `controllerId`, `pageId`, `pageTitle`, `portalOrigin` (the
server's own address), `staffName` and `customerName`.

A check is one of: `selector` with `count`, `minimum` or `hasSize`;
`textContains`; `hasNoOverflow` (nothing in the message reaches past its
right edge, apart from tables and code, which scroll inside themselves); or
`columnAlignment` (each column of the table, header included, lines up
`left`, `right` or `center` as its Markdown says); `drawnDiagrams` (how many
Mermaid diagrams are drawn rather than shown as source); or `katexOutput` (how
many formulas KaTeX draws). The
selectors name the web page's elements; the app's test reads each check as
what a picture must show and asserts its native counterpart under the same
name.
