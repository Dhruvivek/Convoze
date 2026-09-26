# Convoze

A real-time 1:1 + group chat app: Flutter mobile client, Node.js backend, PostgreSQL, Socket.IO.

## Language

**Session**:
A durable, revocable record of one authenticated login for one user on one Device (refresh token, expiry, revocation state), tracked server-side. Not the same as an access token — the access token is a short-lived, stateless JWT derived from a Session; the Session is what actually holds the login open and can be revoked.
_Avoid_: login, token (when referring to the durable record rather than the JWT itself)

**Device**:
A single client installation, identified by a client-generated UUID sent at login. The unit a Session is scoped to — a user with multiple Devices has multiple concurrent Sessions.
_Avoid_: client, install

**Read watermark**:
A single marker per Participant recording the last Message they've read in a Conversation, not a record per message read. "Seen by N" is derived by comparing every Participant's watermark against a given Message, not by looking up a stored per-message status.
_Avoid_: read receipt (implies a record per message per reader, which this project deliberately does not do), delivery status

**Presence**:
A User's online/last-seen status. "Online" is derived server-side from their currently-connected sockets and never stored; "last seen" is the one part that is — `User.lastSeenAt`, written the moment their last live socket disconnects, so it survives a restart (#34). Distinct from a client's *belief* about another User's presence, which goes stale while the client's own socket is disconnected and must never be shown as a confident "offline" during that gap.
_Avoid_: online status, connection status (that's the client's own transport state, not another User's presence)

**Device token**:
A Device's registered push-delivery credential (FCM/APNs token), stored independently of that Device's Session and correlated to it only by the `(userId, deviceId)` pair — not a foreign key. A push is sent to a Device token when that Device's current Session has zero live sockets.
_Avoid_: push token (ambiguous with the JWT access token), FCM token (names one provider; the concept spans FCM and APNs)

**Delivery watermark**:
A single marker per Participant recording the last Message that has reached at least one of their Devices (acknowledged by that Device), mirroring the Read watermark. "Delivered to N" is derived by comparing every Participant's delivery watermark against a given Message. A Participant's delivery watermark is always at or ahead of their Read watermark.
_Avoid_: delivery receipt, delivered status (both imply a stored per-message record)

**Update**:
One durable change a User must converge on — a new, edited or deleted Message, a reaction change, a watermark move, or a membership change — positioned in that User's Update log. An Update refers to the thing that changed rather than copying it, so it always reflects the thing's current state when delivered. Typing and Presence are never Updates.
_Avoid_: event (too broad — includes ephemeral signals), notification (that's a push)

**Update log**:
The ordered, per-User sequence of Updates, each numbered by a per-User position that only goes up. The single path by which a Device learns about durable changes, whether live or catching up after being offline. Retained for a bounded window; a Device that falls behind it must resync from a snapshot instead.
_Avoid_: queue (implies entries are removed once delivered — Update log entries are not), inbox, feed

**Sync cursor**:
The highest Update log position a Device has durably applied locally. Held by the Device, not the server, and presented on every (re)connect to resume from.
_Avoid_: offset, pts, since-token

**Local replica**:
A Device's on-device copy of the User's conversations, messages and related data, which is the only thing the Device's UI reads from. Network traffic writes into it; screens never read from the network directly. Disposable: everything in it except the Outbox can be rebuilt from the server, so wiping it (at logout, on corruption, on a schema change) is always safe.
_Avoid_: cache (implies an optional speed-up the UI can bypass), local DB (names the storage, not the role)

**Outbox**:
The messages a User has composed on a Device that the server hasn't yet acknowledged, including ones the server rejected, which stay (as failed) until the User retries or deletes them. The one part of the Local replica the server can't rebuild, so losing it loses the User's words.
_Avoid_: pending queue, drafts (a draft is unsent text still in the composer, not a message the User has already sent)

**Conversation preferences**:
A Participant's own settings for how a Conversation appears and notifies for them — pinned, archived, muted, hidden, and how much of its history they have cleared — visible only to that User and synced across their Devices. Never seen by other Participants, unlike watermarks.
_Avoid_: chat settings (ambiguous with group settings every Participant sees, like the group name), chat list controls (names the UI, not the state)

**Reply**:
A Message that points at an earlier Message in the same Conversation and is shown alongside that Message as it is now — edited text, or "deleted" if it's gone — never a copy taken at reply time.
_Avoid_: quote (implies a snapshot of the original, which is what Signal stores because its server can't see history)

**Poll**:
A question with up to 10 options, posted as a Message in a group Conversation, which Participants answer with Votes until its creator closes it. Votes are visible to every Participant, not anonymous.
_Avoid_: survey

**Vote**:
A Participant's current choice in a Poll — at most one per Participant per Poll; voting again replaces it rather than adding a second.
_Avoid_: answer, response (both suggest something that accumulates)
