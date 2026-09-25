# Chat Application — Features Documentation

**Scope:** Core + Medium tier features
**Target timeline:** 1 week
**Stack assumption:** Node.js, Express.js, MongoDB/PostgreSQL, Socket.IO

---

## Table of Contents
1. [Core Features](#core-features)
2. [Medium Features](#medium-features)
3. [Extended Tier (Signal-inspired)](#extended-tier-signal-inspired)
4. [Suggested Build Order (7-Day Plan)](#suggested-build-order-7-day-plan)
5. [Data Model Overview](#data-model-overview)

---

## Core Features

### 1. User Authentication
**What it is:** Users sign up, log in, and stay authenticated across sessions.
**Implementation notes:**
- JWT-based auth (access token + refresh token) or session-based with `express-session`
- Password hashing with `bcrypt`
- Middleware to protect authenticated routes
- Optional: OAuth (Google) if time permits — otherwise skip for a 1-week build

**Key endpoints:** `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`

---

### 2. 1:1 Real-Time Messaging
**What it is:** Two users can exchange messages instantly without refreshing the page.
**Implementation notes:**
- Socket.IO for bi-directional real-time communication
- Each user joins a personal room (`socket.join(userId)`) on connect
- Message event: `sendMessage` → server persists → emits `receiveMessage` to recipient's room
- Fallback: if recipient is offline, message still saves to DB for later retrieval

---

### 3. Message Persistence
**What it is:** All messages are stored in a database so chat history survives refreshes/reconnects.
**Implementation notes:**
- Schema: `{ senderId, receiverId, conversationId, content, type, createdAt }`
- Index on `conversationId` + `createdAt` for fast history queries
- Prisma (Postgres) or Mongoose (MongoDB) — either works; Postgres is easier to demonstrate relational thinking in interviews

---

### 4. Online/Offline Presence
**What it is:** Show whether a user is currently online.
**Implementation notes:**
- Track connected socket IDs in memory (a `Map<userId, socketId>`) or Redis if you want it scalable
- Emit `userOnline` / `userOffline` events on connect/disconnect
- Simple to build, high visual payoff for a demo

---

### 5. Typing Indicators
**What it is:** "User is typing..." shown in real time.
**Implementation notes:**
- Client emits `typing` on keypress (debounced ~300ms)
- Server relays to the other participant
- Client emits `stopTyping` after a pause or on send

---

### 6. Timestamps & Read Receipts
**What it is:** Messages show when they were sent, delivered, and seen.
**Implementation notes:**
- `createdAt` field for send time
- `status` field: `sent → delivered → seen`
- `delivered` set when the message reaches the recipient's socket
- `seen` set when the recipient opens the conversation (emit `markAsRead`)

---

### 7. Basic User Profile
**What it is:** Avatar, display name, bio/status.
**Implementation notes:**
- Simple `PUT /users/me` endpoint
- Avatar upload can be deferred to "Media Sharing" below (reuse the same upload logic)

---

## Medium Features

### 8. Group Chats / Channels
**What it is:** Multiple users in one conversation with member management.
**Implementation notes:**
- `Conversation` model with `type: 'direct' | 'group'`
- `Participant` join table: `{ conversationId, userId, role: 'admin' | 'member' }`
- Socket rooms per `conversationId` instead of per-user for group broadcast
- Admin-only actions: add/remove member, rename group

---

### 9. Media Sharing
**What it is:** Send images, files, and short videos in chat.
**Implementation notes:**
- Use `multer` for upload handling, store files on disk/S3/Cloudinary (don't store binaries in your DB)
- Validate file type & size server-side (don't trust the client)
- Message `type` field: `text | image | file | video`
- For a 1-week build: local disk storage + serve via static route is fine; swap to S3 later

---

### 10. Message Editing & Deletion
**What it is:** Users can edit or delete their own sent messages.
**Implementation notes:**
- Soft delete: `isDeleted: true` flag instead of removing the row (preserves conversation integrity)
- `editedAt` timestamp, show "(edited)" label in UI
- Server-side check: only sender can edit/delete their own messages

---

### 11. Message Reactions
**What it is:** Emoji reactions on messages (👍 ❤️ 😂).
**Implementation notes:**
- `Reaction` model: `{ messageId, userId, emoji }`
- Unique constraint on `(messageId, userId, emoji)` to prevent duplicate reactions
- Emit `reactionAdded`/`reactionRemoved` via socket

---

### 12. Push Notifications
**What it is:** Notify users of new messages when the app isn't focused.
**Implementation notes:**
- Web Push API + service worker for browser notifications
- Firebase Cloud Messaging (FCM) if you want mobile-ready notifications
- Trigger: when a message is sent to an offline/unfocused user

---

### 13. Search
**What it is:** Search messages and users.
**Implementation notes:**
- Basic version: SQL `LIKE`/Mongo `$regex` on message content — fine for a week-long build
- User search: filter by username/email prefix
- (Full-text search engines like Elasticsearch are advanced tier — skip for now)

---

### 14. Pagination / Infinite Scroll
**What it is:** Load older messages as the user scrolls up, instead of loading entire history at once.
**Implementation notes:**
- Cursor-based pagination using `createdAt` or message `id` as the cursor (more reliable than offset-based under concurrent writes)
- `GET /conversations/:id/messages?cursor=<messageId>&limit=30`

---

### 15. Rate Limiting & Spam Protection
**What it is:** Prevent abuse (message flooding, brute-force login attempts).
**Implementation notes:**
- `express-rate-limit` on auth routes
- Simple in-memory or Redis-based throttle on `sendMessage` socket event (e.g., max 10 messages/10 sec per user)

---

### 16. Blocking / Reporting Users
**What it is:** Users can block others (no messages delivered) or report abusive content.
**Implementation notes:**
- `Block` model: `{ blockerId, blockedId }`
- Check block status before delivering a message or allowing a conversation to be created
- Reporting can just be a `Report` table logged for manual review — no moderation dashboard needed at this stage

---

## Extended Tier (Signal-inspired)

Chosen by the Signal study (#10, ranked in #19). Built **after** the Medium tier, in the order below. A candidate was adopted only if it costs roughly 3 days or less and rides on an already-designed path. Terms: `CONTEXT.md`.

### 17. Quote Replies
**What it is:** Reply to a specific earlier message; the reply shows the original above it.
**Implementation notes:**
- `Message.replyToMessageId` (nullable, same Conversation)
- The preview is hydrated from the original's *current* state (ADR 0008 references, not copies), so a deleted original shows "Original message was deleted". No snapshot is stored.
- Swipe to reply; tap the quote to scroll to the original
- Folds into the messaging spec

---

### 18. Conversation Preferences (pin / archive / mute / delete chat)
**What it is:** Per-user chat list controls that sync across the user's Devices.
**Implementation notes:**
- Designed in ADR 0009: `Participant` columns, a `conversation.prefs` Update written to the owner's log only
- Mute: 8 hours / 1 week / always. No push and not counted in the app badge
- Pin: at most 5. Archive survives new messages. Delete chat = hidden + a history-cleared watermark; Clear chat = the watermark only
- Its own spec, blocked by the messaging and push specs

---

### 19. Link Previews
**What it is:** A title/description/thumbnail card for the first link in a message.
**Implementation notes:**
- Built on the **sender's device** (Open Graph tags); the server never fetches URLs (no SSRF, no URL logging)
- The thumbnail is uploaded through ADR 0002's signed Cloudinary path; the message carries a `linkPreview` JSON (url, title, description, thumbnail id) that the server only validates for shape
- Folds into the messaging spec

---

### 20. Polls
**What it is:** A question with up to 10 options in a group chat; members vote, the creator can close it.
**Implementation notes:**
- `Poll`, `PollOption`, `PollVote` tables. One Vote per Participant per Poll, replaced in a transaction
- Each vote is an Update referring to the poll message, which hydrates to the current tally
- Groups only; votes are visible to everyone
- Its own spec, blocked by the groups spec

---

### Deferred and rejected

| Candidate | Verdict | Reason |
|---|---|---|
| Voice notes | Deferred (first to promote) | About 4–6 days, mostly recording and playback UX; the backend is an ADR 0002 audio upload |
| @mentions | Deferred | About 3–5 days (rich composer); when picked up, a mention should override mute in the push filter |
| Message requests | Deferred | Needs a user-discovery / contacts decision that doesn't exist yet; blocking and rate limiting cover basic abuse |
| View-once media | Deferred | Low value (screenshots defeat it); adds media-deletion and multi-device "viewed" edge cases |
| Chat folders | Deferred | A separate list-of-lists concept with no demand yet (ADR 0009) |
| On-device search | Deferred | Server search stays; `SearchRepository` is the seam (ADR 0009) |
| Local DB encryption | Deferred | Behind `openReplica()` (ADR 0009) |
| Content-free push | Deferred | `buildPush()` seam (ADR 0006, #16) |
| Stories | Rejected | A second product surface (feeds, audiences, expiry) at several times the cost bar |
| E2EE / client-encrypted attachments | Rejected | Server-trusted by design (ADR 0007) |

---

## Suggested Build Order (7-Day Plan)

| Day | Focus |
|-----|-------|
| 1 | Auth (register/login/JWT), user model, basic profile |
| 2 | Socket.IO setup, 1:1 messaging, message persistence |
| 3 | Presence, typing indicators, read receipts |
| 4 | Group chats/channels, participant management |
| 5 | Media sharing, message edit/delete |
| 6 | Reactions, search, pagination |
| 7 | Rate limiting, blocking/reporting, bug fixes, deploy |

This order front-loads the features that depend on each other (auth → messaging → group logic) and pushes the more isolated, "nice-to-have" features (reactions, search, blocking) to the back half, so if you run short on time, you can cut from the bottom without breaking anything upstream.

---

## Data Model Overview

```
User
 ├─ id, username, email, passwordHash, avatarUrl, status, createdAt

Conversation
 ├─ id, type (direct | group), name (for groups), createdAt

Participant
 ├─ id, conversationId, userId, role (admin | member), joinedAt

Message
 ├─ id, conversationId, senderId, content, type (text | image | file | video),
 │  status (sent | delivered | seen), isDeleted, editedAt, createdAt

Reaction
 ├─ id, messageId, userId, emoji

Block
 ├─ id, blockerId, blockedId, createdAt

Report
 ├─ id, reporterId, reportedUserId, reason, createdAt
```

**Relational note:** Using a `Participant` join table (rather than an array of user IDs on `Conversation`) keeps both 1:1 and group chats under the same schema — you don't need a separate model for direct messages.
