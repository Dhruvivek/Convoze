// The Update kinds (`CONTEXT.md`'s Update; ADR 0008), stored as plain
// strings on `UserUpdate.kind` (see the schema comment for why). This
// ticket's Hydrator (`hydrator.js`) only knows how to hydrate these; later
// specs add more (`conversation.left`, `conversation.members`,
// `conversation.prefs`, ...) alongside their own hydration.
export const UPDATE_KINDS = Object.freeze({
  MESSAGE_NEW: 'message.new',
  MESSAGE_EDITED: 'message.edited',
  MESSAGE_DELETED: 'message.deleted',
  REACTION_CHANGED: 'reaction.changed',
  CONVERSATION_RECEIPTS: 'conversation.receipts',
  CONVERSATION_JOINED: 'conversation.joined',
});

export const ALL_UPDATE_KINDS = new Set(Object.values(UPDATE_KINDS));
