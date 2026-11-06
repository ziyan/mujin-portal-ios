# Mujin Portal for iPhone

A native iPhone client for Mujin Portal. Phase 1 covers sign-in, several
accounts on several Portal instances, the conversation list, and a
conversation with the assistant: streamed answers, Markdown, sending messages,
and question and approval cards.

The first account defaults to `https://portal.mujin.cloud`. "Use another
server" takes any https address, so the same build works against another Portal
instance.

## What it does

The tabs follow who is signed in, decided by the organization's `isMujin`
flag (falling back to the permissions):

| Customers | Mujin users | What it holds |
| --- | --- | --- |
| Assistant | Assistant | Conversations, search, "Waiting for you", reactions, artifacts, automations under More |
| Chats | | Placeholder until the server lists chat operations |
| Tickets | Tickets | List by status, thread, replies with photos and files, create |
| Site | | Alarms, robots, controllers, cameras, incidents with evidence and recording |
| | Monitoring | Ticket queue across organizations and recent incidents |
| | Customers | Organization picker, then its sites and tickets |
| More | More | Notifications, settings, automations, about, sign out |

The default bar is Chat, Sites and Tickets, then More, with Search set apart at the trailing end (a person may choose two
tabs besides Chat, so a phone never shows more than five). Surveillance lives under More and in search, and a person who put it
on the bar keeps it. On a wide iPad window the tabs become a sidebar. Features that depend on a
newer server are built against its contract and shown only when the server
offers the operation (`ServerCapabilities` reads the schema once per sign-in).

## Search

The Search tab asks the server the same `GlobalSearch` query as the Portal web app's Ctrl-K palette, after a pause in typing, so
both show the same rows under the same names: controllers, virtual controllers, sites, cells, cameras, organizations, people,
chats, assistant conversations, tickets, releases, pages and incidents, with shortcuts to settings and other screens first when
they match. An empty field lists the rows opened before (kept on the phone, per account) and the shortcuts the server suggests.
A row opens through the same `PortalLink` mapping as a link tapped in a chat: the app's own screen where there is one, and
otherwise the page in the built-in browser, signed in. Search is shown as unavailable on a server that does not have the query.

## Cameras

A site with cameras lists them on the Site tab; each opens live video, and an incident plays the
recording from just before it was detected. Video is decoded by the system, not a web view: the
camera's fragmented MP4 stream (H.264 or H.265) is cut into frames by PortalKit and shown by an
`AVSampleBufferDisplayLayer`, whose clock gives pause and speed. The timeline, the date jump and
shared clips use the NVR's own clock and say so. Recorded playback uses the controller's playback
websocket only, a minute at a time, on a channel the NVR records (the sharpest or the least sharp, never the middle one); a controller too old to have the route (its upgrade is answered with a web page) says so and offers a clip download; clips from `video/export` are only downloaded to be shared. Sound
starts off; the speaker button on the camera screen plays the stream's AAC track on the same clock,
and the audio session is only taken while sound is on. The demo server plays a generated test pattern
(`PortalApp/Resources/DemoCamera.mp4`, made with a software encoder; nothing recorded by a camera).

## Web apps

A controller's page and a virtual controller's page list the web apps installed on it as a grid of tiles with each app's icon and name
(`ListControllerWebApps`, shown only when the server offers it). A tile opens the app's page in the built-in browser through the same web
session handoff as the controller's web UI, so it lands signed in. Icons come from a Portal route that takes the app's token, since the
controller's own host refuses it. Most apps ship an SVG, which UIKit cannot decode, so the app draws each one once with WebKit.

## Layout

| Path | What it is |
| --- | --- |
| `PortalKit/` | SwiftPM package with everything that is not a screen: server address, OpenID Connect sign-in with PKCE, the `Connection` actor, the keychain account ring, the `graphql-transport-ws` feed and the transcript. It builds and tests on Linux. |
| `PortalApp/` | The SwiftUI app (iOS 26, Swift 6), the String Catalog (English, Japanese, Simplified and Traditional Chinese, German, French, Dutch) and the privacy manifest. |
| `PortalNotification/` | Notification service extension: turns a question's choices into buttons, gives an approval Approve and Deny, stacks by conversation and clears a card answered elsewhere. |
| `Schema/schema.json` | Names, types and arguments of Portal's GraphQL schema, used by a test that validates every document the app sends. |
| `project.yml` | The Xcode project as XcodeGen text. `MujinPortal.xcodeproj` is generated and not committed. |
| `Configuration/` | Build settings, the export options for TestFlight, and an example of the uncommitted `Identity.xcconfig`. |

## Build

You need a Mac with Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open MujinPortal.xcodeproj
```

A simulator build needs no signing. To run on a device, copy
`Configuration/Identity.example.xcconfig` to `Configuration/Identity.xcconfig`
(it is not committed) and set your team, and a bundle identifier you have
registered if you are not the publisher.

### Demo mode

Launch with the argument `-demo` and the app talks to a fake server with
invented data and a scripted streaming answer. CI uses it for screenshots.

### Tests

The kit needs no Mac:

```sh
docker run --rm -v "$PWD":/work -w /work/PortalKit swift:6.1 swift test
```

It covers the server address rules, PKCE, the sign-in exchange, token renewal
(one renewal for any number of callers, one retry after a 401), the feed
(ping, 15 second silence watchdog, reconnect backoff from 1 to 10 seconds,
renewal on close code 4401), transcript folding and replay deduplication, and
the schema check.

### Schema check

Every GraphQL document in `PortalKit/Sources/PortalKit/Documents.swift` is
validated against `Schema/schema.json` by `SchemaCheckTests`. To refresh the
copy from a Portal checkout:

```sh
scripts/refresh-schema.sh /path/to/portal/frontend/schema.json
```

The script drops every description and refuses to write a file that mentions a
host name.

## Sign-in

The app is a public OAuth client (authorization code with PKCE S256, no secret)
using `ASWebAuthenticationSession`.

- Client id `mujin-portal-ios`, a built-in client the Portal backend registers.
- Redirect `com.ziyan.mujinportal:/oauth`.
- Scopes `openid profile email offline_access api:read api:write`.
- Endpoints come from `/.well-known/openid-configuration`.

If a server does not know the built-in client, the app shows the server's own
error. Signing out unregisters the phone for push, then posts the refresh token
to the discovery document's `revocation_endpoint`, which ends the whole grant.

## Web pages, push, presence and voice

- **Built-in browser.** A Portal or controller page opens through a one-time
  `CreateWebSessionHandoff` address in a web view whose cookies belong to that
  account alone. A page that lands on Portal's login asks for a new address once.
- **Push.** `RegisterPushDevice` runs at every launch for every signed-in account.
  The environment (`sandbox` for a Debug build, `production` for Release) is set
  in `Configuration/Base.xcconfig`. The entitlement is `development`; the App
  Store export re-signs it for production. Approve and Deny need device
  authentication. Notification texts come from `push.<kind>.title|body` keys in
  the String Catalog.
- **Inbox.** `OnNotification` replaces polling and reconnects on close code 4401.
- **Presence.** While the app is in front it reports every minute, so the server
  does not push what the person is looking at.
- **Voice.** The mic button opens the streaming voice socket (24 kHz mono PCM,
  system voice processing, talking over the answer). A server without streaming
  transcription (`not_configured`) uses recorded utterances and the older
  transcribe and synthesize endpoints.

## Voice messages and calls

- **Voice messages.** In a chat with people, the microphone button beside the text box switches it to a bar to hold: hold to
  record (AAC in an m4a file, mono, up to two minutes, counting down from 1:50), slide up to cancel, let go to send. The 48 bars and the
  length are worked out on the phone. A bubble plays one message at a time, shows the waveform as a slider, and "Show text" reveals the
  transcript. A browser's WebM recording cannot be played here; its text is shown instead.
- **Calls.** WebRTC (the `stasel/WebRTC` package) to the server's media host, which is ICE-lite, so no ICE servers are given and the
  offer goes out once the phone's candidates are gathered. Incoming calls ring through CallKit from a PushKit VoIP push (the second
  token, `voipToken`, goes to the server with the alert token); the audio session is CallKit's and WebRTC takes it only when CallKit
  activates it. A call can be minimized to a bar over every tab.
- **Video selection.** The phone sends one video track in two simulcast layers (rid `small` at a quarter size, 150 kbps, 15 fps; rid `full` up to 720p, 1.5 Mbps, 30 fps), VP8 preferred, H.264 allowed. It tells the server how much of each person's video it wants (`SetChatCallVideoSubscriptions`): full for the main stage, small for strip tiles in view, off for tiles scrolled out and for everyone while the call is minimized. The plan is sent once the media is up, again after a reconnect, and after every change, debounced by 300 ms. A call's size limit comes from `GetChatCallMaximumPersonCount`.
- **Without a server that has them**, none of it shows: `ServerCapabilities` reads the schema once per sign-in.

## Message threads

A reply goes in a thread, in chats with people and in conversations with the assistant. The main history shows every message in time
order, replies included, and a reply keeps its quote of what it answers. A message that belongs to a thread opens it when tapped (a
reply, or a message with replies), and a message with replies also says "N replies" and when the last came. Reply on a message opens its
thread. A thread (`threadRootMessageId`) is a screen of its own, the root first, with its own composer; a reply sent from it goes to the
message picked, else to the root. Every event reaches the main history, so the streaming text of a threaded run shows there and in the
thread if it is open, and a thread shows only its own run. A push that carries `threadRootMessageId` opens that thread. A server without
the argument and fields is sent none of them (`ServerCapabilities.offersMessageThreads`) and behaves as before.

## TestFlight

TestFlight builds come from the `TestFlight` job of `.github/workflows/ios.yml`,
which runs only when started by hand: Actions, iOS, Run workflow, with
"Upload the build to TestFlight" on. The build number is the workflow run
number and the version is `MARKETING_VERSION` in `Configuration/Base.xcconfig`.

The app tells people when a newer build can be installed. It reads how it was
installed from its receipt's name, and not from StoreKit's app transaction,
which can prompt to sign in: a TestFlight copy reads `testflight.json` from the
`update-feed` release, and an App Store copy asks Apple's public lookup. The
feed holds the newest build public testers can install, so a build waiting for
beta review is not announced. The build's own run writes it, and the
`Update feed` workflow refreshes it on a schedule for reviews that finish later.

The job needs these repository secrets:

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | Key id of an App Store Connect API key with the Admin role |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer id shown beside the keys |
| `APP_STORE_CONNECT_API_KEY` | Contents of the `AuthKey_<id>.p8` file |
| `APPLE_DEVELOPMENT_TEAM` | The ten character team id |
| `APPLE_DEVELOPMENT_CERTIFICATE` | Base64 of a development certificate exported as `.p12` |
| `APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD` | The password of that `.p12` |

The App Store Connect app record (name, bundle id `com.ziyan.mujinportal`,
SKU) must exist before the first upload; Apple offers no API to create it. The
extension's bundle id is `com.ziyan.mujinportal.notification`.

## License

MIT, see `LICENSE`.
