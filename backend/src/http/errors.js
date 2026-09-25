// Every error response uses one shape: { error: { code, message } }.
export function sendError(res, status, code, message) {
  res.status(status).json({ error: { code, message } });
}

export function notFoundHandler(_req, res) {
  sendError(res, 404, 'not_found', 'Not found');
}

export function errorHandler(err, _req, res, _next) {
  if (err.type === 'entity.parse.failed') {
    sendError(res, 400, 'invalid_request', 'Malformed JSON body');
    return;
  }
  console.error(err);
  sendError(res, 500, 'internal_error', 'Internal server error');
}
