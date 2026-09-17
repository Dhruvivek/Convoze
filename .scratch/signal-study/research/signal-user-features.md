# Signal user features: replies, mentions, voice notes, message requests, stories, polls

Research for issue #15 (part of the wayfinder map #10). It feeds into **Rank Signal-inspired features for Convoze**.

- Retrieved: 2026-09-17, from the `main` branches of the signalapp repos and from signal.org.
- Signal's code is AGPLv3. This file only describes data shapes and behaviour. No code was copied, and none should be.
- Convoze context: Flutter client plus Node.js, Socket.IO and PostgreSQL. Phone and OTP login. **No E2EE**, so the server can read messages (see `docs/features.md`, `docs/adr/0001-flutter-client-architecture.md`).

## Sources used

| Key | URL |
|---|---|
| PROTO | https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/protowire/SignalService.proto |
| DMP | https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/messages/DataMessageProcessor.kt |
| VALIDATOR | https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/java/org/whispersystems/signalservice/api/messages/EnvelopeContentValidator.kt |
| AUDIOCODEC | https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/audio/AudioCodec.java |
| AUDIOREC | https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/audio/AudioRecorder.java |
| SPEEDS | https://github.com/signalapp/Signal-Android/blob/main/app/src/main/res/values/arrays.xml (`PlaybackSpeedToggleTextView__speeds`) |
| MRSTATE | https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/messagerequests/MessageRequestState.kt |
| RECIPUTIL | https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/recipients/RecipientUtil.java |
| READRCPT | https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/jobs/SendReadReceiptJob.java |
| TYPING | https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/jobs/TypingSendJob.java |
| STORYEXP | https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/service/ExpiringStoriesManager.kt |
| BLOG-GROUPS | https://signal.org/blog/new-groups/ (Oct 2020, adds @mentions) |
| BLOG-MR | https://signal.org/blog/message-requests/ |
| BLOG-STORIES | https://signal.org/blog/introducing-stories/ (7 Nov 2022) |
| BLOG-POLLS | https://signal.org/blog/polls/ (19 Nov 2025) |
| SUP-POLLS | https://support.signal.org/hc/en-us/articles/9971667844506-Signal-Polls |
| SUP-STORIES | https://support.signal.org/hc/en-us/articles/5008009166234-Stories |
| SUP-MR | https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests |

> Caveat: support.signal.org returned HTTP 403 when fetched directly. Claims cited to `SUP-*` come from the search-engine excerpts of those pages, and each one is backed up by a blog post or code wherever possible.

---

## Signal's general design: everything is a client-side message

Signal's server only relays encrypted envelopes. Its `Envelope.Type` values are `DOUBLE_RATCHET`, `PREKEY_MESSAGE`, `UNIDENTIFIED_SENDER`, `PLAINTEXT_CONTENT` and so on [PROTO]. Every feature below lives inside the encrypted `Content` as either a `DataMessage` or a `StoryMessage` [PROTO]:

- **Messages point at each other by `(author ACI, sentTimestamp)`, not by a server ID.** Reactions, deletes, quotes, poll votes and story replies all do this [PROTO]. The receiver looks up the target with `getMessageFor(targetSentTimestamp, authorId)` [DMP].
- **Each client works out state on its own.** Vote tallies, "is this a request?", and story expiry are all computed on the device.
- **Version gating:** `DataMessage.ProtocolVersion` includes `REACTIONS = 4`, `MENTIONS = 6` and `POLLS = 8`, with `CURRENT = 8` [PROTO].

**Main lesson for Convoze:** a server that can read messages can replace most of this client-side bookkeeping with foreign keys and server-side checks. So in most cases the non-E2EE version is *simpler* than Signal's.

---

## 1. Quote replies

**How Signal models it** [PROTO]
- `DataMessage.quote = 8` holds a `Quote` with these fields:
  - `id` (uint64): the sent timestamp of the original message.
  - `authorAci` or `authorAciBinary`.
  - `text`: a copy of the quoted text.
  - `attachments`: repeated `QuotedAttachment { contentType, fileName, thumbnail }`.
  - `bodyRanges`: mentions and styles inside the quoted text.
  - `type`: `NORMAL`, `GIFT_BADGE` or `POLL`.
- The sender puts a **snapshot** of the quoted content into the message. That way the receiver can still show the quote if it never had the original, or has deleted it.
- The receiver runs `getValidatedQuote`. It returns nothing if `quote.id` is null. Otherwise it looks up `getMessageFor(quote.id, authorId)`, and if it finds the local message it uses that message's own text and mentions [DMP].

**Does it depend on E2EE?** No. The snapshot exists because the server cannot see message history, so it has nothing to do with the feature itself.

**Convoze (non-E2EE) version**
- Add `messages.reply_to_message_id UUID NULL REFERENCES messages(id) ON DELETE SET NULL`.
- The server joins or embeds a small preview (author, the first N characters, the first attachment's type and thumbnail) in the Socket.IO payload.
- Optional: keep a `reply_preview JSONB` snapshot so a quote still shows after the original is deleted.
- UX: swipe to reply, and tap the quote to scroll to the original.
- **Complexity: Low (about 1–2 days).**

## 2. @mentions

**How Signal models it** [PROTO]
- `DataMessage.bodyRanges = 18` is a list of `BodyRange { start, length, oneof associatedValue { mentionAci | mentionAciBinary | style } }`.
- The same structure carries text styles: `BOLD`, `ITALIC`, `SPOILER`, `STRIKETHROUGH` and `MONOSPACE`.
- The body text holds a placeholder at the mention position. The client draws the mentioned person's *current* profile name over that range.
- The receiver takes the ranges that have a mention ACI and turns them into `Mention(recipientId, start, length)` rows. It stores style ranges separately, and caps how many ranges it processes (`BODY_RANGE_PROCESSING_LIMIT`) [DMP].
- Quotes also carry `bodyRanges`, so mentions survive inside quotes [PROTO].
- UX: type "@" in a group to open a member picker. When you are mentioned, a "jump to mention" button appears when you open the chat [BLOG-GROUPS].
- Mentions arrived with the new group system, so they are a group feature [BLOG-GROUPS].

**Does it depend on E2EE?** No. The ACIs sit inside ciphertext only because everything does.

**Convoze (non-E2EE) version**
- Store `messages.body` plus a `body_ranges JSONB` column shaped like `[{start, length, userId}]`, or a `message_mentions(message_id, user_id, start, len)` table.
- The server checks that every mentioned user is a member of the conversation.
- Mentions can also drive notifications, such as a "notify on mention even when muted" setting.
- The client needs a member picker and a rich text field. The fiddly part in Flutter is keeping ranges correct while the user edits text, especially with emoji and UTF-16 offsets. Signal's `start` and `length` count UTF-16 units, the same as Java and Dart strings.
- **Complexity: Medium (about 3–5 days)**, mostly on the client. The server work is Low.

## 3. Voice notes

**How Signal models it**
- A voice note is a normal attachment with a flag set: `AttachmentPointer.Flags { VOICE_MESSAGE = 1; BORDERLESS = 2; GIF = 8 }` [PROTO]. There is no separate message type.
- Recording on Android:
  - Android 8 (API 26) and newer use `MediaRecorderWrapper`. Older versions fall back to `AudioCodec` [AUDIOREC].
  - The output MIME type is `MediaUtil.AUDIO_AAC` [AUDIOREC].
  - `AudioCodec` records AAC (`audio/mp4a-latm`) at 44100 Hz, 32 kbps, mono, framed in ADTS headers [AUDIOCODEC].
- Playback UX on Android:
  - A speed toggle cycles through 1×, 1.5×, 2× and 0.5×, stored as `100, 150, 200, 50` [SPEEDS].
  - A voice-note player drives playback: `VoiceNoteMediaController` and `VoiceNotePlayerView` in `app/src/main/java/org/thoughtcrime/securesms/components/voice/`.
- **Not verified:** the recording formats on iOS and Desktop, and the exact waveform rendering. I did not check these against source.

**Does it depend on E2EE?** No. The attachment is encrypted like any other file, but the voice-note feature itself is only a flag and a player.

**Convoze (non-E2EE) version**
- Upload through the existing attachment path, such as an S3 or disk blob plus a Postgres row.
- Add `attachments.kind = 'voice'`, `duration_ms`, and optionally `waveform SMALLINT[]` computed on the client or with ffmpeg on the server.
- Flutter needs:
  - hold-to-record with slide-to-cancel and lock
  - microphone permission handling
  - AAC/M4A recording that plays on both platforms
  - a playback speed toggle
  - optional server-side transcoding
- **Complexity: Medium (about 4–6 days).** Most of the effort is the client recording and playback UX, not the backend.

## 4. Message requests

**How Signal models it**
- **No wire message is involved.** "Is this a request?" is decided by each client.
- `RecipientUtil.isMessageRequestAccepted` returns true if any of these hold [RECIPUTIL]:
  - the thread is with yourself
  - profile sharing is on
  - the sender is a system contact
  - the sender is not registered on Signal
  - you have sent a message in the thread
  - the thread has no messages and no calls
- Calls use a stricter version, `isCallRequestAccepted`. It requires profile sharing, a system contact, or a message you sent [RECIPUTIL].
- The blog confirms the phone does not ring for an unknown caller until you accept [BLOG-MR].
- The first message you send shares your profile automatically (`shareProfileIfFirstSecureMessage`) [RECIPUTIL].
- `MessageRequestState.State` values [MRSTATE]:
  - `NONE` and `NONE_HIDDEN`: accepted
  - `INDIVIDUAL` and `INDIVIDUAL_HIDDEN`: pending request from a person
  - `GROUP_V2_INVITE` and `GROUP_V2_ADD`: pending group invite or add
  - `INDIVIDUAL_BLOCKED` and `BLOCKED_GROUP`: blocked
  - `LEGACY_INDIVIDUAL` and `DEPRECATED_GROUP_V1`: legacy cases
- **What is held back until you accept:**
  - **Read receipts:** verified. `SendReadReceiptJob` refuses with "Refusing to send receipts to untrusted recipient" when the request is not accepted, and also refuses for blocked recipients [READRCPT].
  - **Your profile:** your name and avatar are shared only once you accept or send a message [RECIPUTIL, BLOG-MR].
  - **Calls:** they do not ring [BLOG-MR].
  - **Typing indicators:** *not verified*. `TypingSendJob` only skips blocked and unregistered recipients [TYPING]. The request check may happen higher up in the UI, since the composer is replaced by the request bar (see below), but I did not confirm this.
- **Actions:**
  - Accept, Delete, Block, and Report or Block-and-report [SUP-MR].
  - Other devices are kept in sync with `SyncMessage.MessageRequestResponse.Type`: `ACCEPT`, `DELETE`, `BLOCK`, `BLOCK_AND_DELETE`, `SPAM` and `BLOCK_AND_SPAM` [PROTO].
  - While a request is pending, the composer is replaced by the request bar (`DisabledInputView.showAsMessageRequest`, `MessageRequestsBottomView` in Signal-Android).
- **What `block()` does** [RECIPUTIL]:
  - leaves the group, if it is a group
  - sets `blocked = true`
  - rotates your profile key where needed, so the blocked person loses access to future profile updates
  - schedules a storage sync and a multi-device blocked-list update
- Blocking takes effect on the client. The Signal server cannot see who blocked whom.

**Does it depend on E2EE?** Only in part. The idea is independent of E2EE. The *way* Signal builds it (client-side rules, profile-key rotation) exists because the server is blind. In Convoze the server can and should enforce it.

**Convoze (non-E2EE) version**
- Add `conversation_members.status` with values `pending_request`, `accepted` or `blocked`, or add a `contact_acceptance(user_id, peer_id, state)` table. Add `blocks(blocker_id, blocked_id)`.
- The server:
  - sets the recipient to `pending_request` on the first message from someone who is not a contact and whom the recipient has never messaged
  - withholds read receipts, typing events, presence and last-seen, and profile photo and name, until the state is `accepted`
  - drops or quietly discards messages from blocked users
  - keeps pending requests out of the push-notification path
- Convoze logs in by phone number, so "is a contact" needs a contact-sync decision. That ties into the privacy review.
- **Complexity: Medium (about 3–5 days).** It is easier than Signal's version because enforcement happens in one place (Socket.IO middleware plus SQL). It touches receipts, typing, presence, push and profile endpoints.

## 5. Stories

**How Signal models it**
- A story is a separate content type, `Content.storyMessage = 9`: `StoryMessage { profileKey, group (GroupContextV2), oneof attachment { fileAttachment | textAttachment }, allowsReplies, bodyRanges }` [PROTO].
- `TextAttachment` holds text, a text style (`REGULAR`, `BOLD`, `SERIF`, `SCRIPT`, `CONDENSED`), foreground and background colours, an optional link `preview`, and a solid or gradient background [PROTO].
- **Audiences:**
  - Types [BLOG-STORIES, SUP-STORIES]:
    - **My Story:** all Signal connections by default, restrictable with an allow-list or an "all except" list.
    - **Custom stories:** named distribution lists.
    - **Group stories:** sent to an existing group.
  - Distribution lists are never sent to recipients. Only your *own other devices* learn about them, through `SyncMessage.Sent.storyMessageRecipients: StoryMessageRecipient { destinationServiceId, distributionListIds[], isAllowedToReply }` [PROTO].
  - Each recipient just receives a `StoryMessage`.
- **Replies and reactions:**
  - A reply is an ordinary `DataMessage` that carries `storyContext = 21` (`StoryContext { authorAci, sentTimestamp }`). A reaction to a story is `DataMessage.reaction` with that same `storyContext` [PROTO].
  - The sender controls replies with `allowsReplies` [PROTO].
  - Replies to a group story are visible to the group. Replies to a private story go to the author 1:1 [BLOG-STORIES].
- **Expiry:** the client deletes a story 24 hours after it was sent (`STORY_LIFESPAN = TimeUnit.HOURS.toMillis(24)`) [STORYEXP]. You can delete it sooner [SUP-STORIES].
- **Views:** `ReceiptMessage.Type` includes `VIEWED` [PROTO]. You can turn view receipts on or off, and turning stories off is private [BLOG-STORIES].

**Does it depend on E2EE?** No. Keeping distribution lists local, and syncing them only between your own devices, is a privacy choice that follows from E2EE. A server-visible version is simpler.

**Convoze (non-E2EE) version**
- Tables:
  - `stories(id, author_id, kind media|text, attachment_id, text_payload JSONB, allows_replies, audience_type my|custom|group, audience_ref, created_at, expires_at)`
  - `story_audience_lists(id, owner_id, name)` and `story_audience_members`
  - `story_views(story_id, viewer_id, viewed_at)`
- Replies and reactions become messages with `story_id` in a 1:1 or group conversation.
- A cron job or `WHERE expires_at > now()` filter handles expiry, plus media cleanup.
- Fan-out: when a story is posted, work out who can see it and push a "new story" event over Socket.IO. The feed is a query.
- Client: a full-screen viewer with progress bars, a text-story composer, a camera or media picker, an audience picker, a viewers list and a reply sheet.
- **Complexity: High (about 2–3 weeks).** Audiences, feed, expiry, views and replies add up to a small product of their own. Most of the work is in the client UI.

## 6. Polls: shipped (Nov 2025)

**Is it shipped?** **Yes.** It launched on 19 Nov 2025 for Android, iOS and Desktop [BLOG-POLLS].
- In the UI, polls are **for group chats** [BLOG-POLLS, SUP-POLLS].
- In the Android code, the receiver also accepts a poll in a 1:1 thread, as long as the sender belongs to that thread [DMP]. So the protocol does not require a group.

**How Signal models it** [PROTO]
- `DataMessage.pollCreate = 24`: `PollCreate { question, allowMultiple, options[] }`
- `DataMessage.pollVote = 26`: `PollVote { targetAuthorAciBinary, targetSentTimestamp, optionIndexes[], voteCount }`
- `DataMessage.pollTerminate = 25`: `PollTerminate { targetSentTimestamp }`
- `Quote.Type.POLL` lets you quote a poll.

**Rules the receiver checks** [DMP, VALIDATOR]
- The question must be 1–200 characters. There can be 1–10 options, each 1–100 characters (`POLL_QUESTION_CHARACTER_LIMIT`, `POLL_OPTIONS_LIMIT`, `POLL_CHARACTER_LIMIT`).
- In a group, the poll author must be a group member.
- **Each vote replaces the voter's earlier vote.** `voteCount` works as a per-voter counter, so a vote is ignored unless its count is higher than the stored one. The last vote wins, so a later vote can also retract earlier choices.
- Option indexes must be in range. More than one index is allowed only if `allowMultiple` is set. Votes on a poll that has ended are dropped.

**UX** [BLOG-POLLS, SUP-POLLS]
- Votes are **not anonymous**: members can see who voted for what.
- The creator can end the poll. A poll cannot be edited after it is sent.

**Does it depend on E2EE?** No. `voteCount` and the last-write-wins rule exist because there is no central authority to order votes. In Convoze, Postgres is that authority.

**Convoze (non-E2EE) version**
- Tables:
  - `polls(message_id PK/FK, question, allow_multiple, ended_at)`
  - `poll_options(id, poll_id, idx, text)`
  - `poll_votes(poll_id, option_id, voter_id, PRIMARY KEY(poll_id, option_id, voter_id))`
- To vote, replace the voter's rows for that poll inside one transaction and check `allow_multiple` and `ended_at`. Then emit a `poll:updated` event with the tallies (or voter lists) to the conversation room.
- Client: a creation sheet, an options list with live counts, and a sheet showing who voted.
- **Complexity: Low–Medium (about 2–4 days).**

---

## Summary

| Feature | Signal model (wire) | Needs E2EE? | Convoze non-E2EE design | Complexity |
|---|---|---|---|---|
| Quote replies | `DataMessage.quote` = target sent timestamp + author + snapshot text/attachment thumbs + bodyRanges | No | `reply_to_message_id` FK + server-built preview | **Low** (1–2 d) |
| @mentions | `bodyRanges[]` with `mentionAci` (UTF-16 start/length); group feature | No | `body_ranges JSONB` / `message_mentions` table; membership check; mention notifications | **Medium** (3–5 d, mostly client editor) |
| Voice notes | Normal attachment + `Flags.VOICE_MESSAGE`; Android records AAC mono 44.1 kHz/32 kbps; speed 1/1.5/2/0.5× | No | attachment `kind='voice'`, `duration_ms`, waveform; Flutter record/playback | **Medium** (4–6 d, client-heavy) |
| Message requests | No wire type; each client decides from contacts, profile sharing and sent history; `MessageRequestResponse` sync (ACCEPT/DELETE/BLOCK/SPAM…); receipts withheld until accepted | Only in how it is built | Server state per member (`pending/accepted/blocked`) + `blocks`; server withholds receipts, typing, presence, profile | **Medium** (3–5 d) |
| Stories | `StoryMessage` (file/text attachment, `allowsReplies`, group); lists synced only to own devices; replies via `storyContext`; 24 h expiry on the client; `VIEWED` receipts | No (private lists are a privacy choice) | `stories`, audience lists, `story_views`, `expires_at` + cron, feed query, reply-as-message | **High** (2–3 wks) |
| Polls | **Shipped Nov 2025.** `PollCreate/PollVote/PollTerminate`; ≤10 options; last vote wins via `voteCount`; not anonymous; groups in UI (1:1 accepted in code) | No | `polls`, `poll_options`, `poll_votes` with transactional replace + socket tally broadcast | **Low–Medium** (2–4 d) |

**Unverified / open items**
- Whether Signal holds back *typing indicators* for unaccepted requests. The send job does not check for this, and I did not trace the UI layer.
- The voice-note recording formats on iOS and Desktop.
- The exact text of the support.signal.org pages, which blocked direct fetching. Claims from them rely on search excerpts.
