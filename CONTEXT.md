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
