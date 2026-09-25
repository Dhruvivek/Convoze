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
A User's online/last-seen status, derived server-side from their currently-connected sockets — not a stored field. Distinct from a client's *belief* about another User's presence, which goes stale while the client's own socket is disconnected and must never be shown as a confident "offline" during that gap.
_Avoid_: online status, connection status (that's the client's own transport state, not another User's presence)

**Device token**:
A Device's registered push-delivery credential (FCM/APNs token), stored independently of that Device's Session and correlated to it only by the `(userId, deviceId)` pair — not a foreign key. A push is sent to a Device token when that Device's current Session has zero live sockets.
_Avoid_: push token (ambiguous with the JWT access token), FCM token (names one provider; the concept spans FCM and APNs)
