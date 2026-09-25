// A Message's wire shape, shared by the Hydrator (#47) and the REST history
// pages (#50). A deleted Message never carries its content past this
// boundary, even if the caller reused a stale row: a tombstone is always
// built from scratch.
export function tombstone(message) {
  return { id: message.id, conversationId: message.conversationId, isDeleted: true };
}

export function messagePayload(message) {
  if (message.isDeleted) return tombstone(message);
  return {
    id: message.id,
    conversationId: message.conversationId,
    senderId: message.senderId,
    clientMsgId: message.clientMsgId,
    replyToMessageId: message.replyToMessageId,
    linkPreview: message.linkPreview,
    type: message.type,
    content: message.content,
    createdAt: message.createdAt,
    editedAt: message.editedAt,
    isDeleted: message.isDeleted,
  };
}
