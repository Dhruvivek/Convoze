import { Router } from 'express';

import { listUsers } from './listUsers.js';

// The Contacts tab's REST surface (#71): everyone else on Convoze.
export function createUsersRouter({ prisma, authenticated }) {
  const router = Router();

  router.get('/', authenticated, async (req, res) => {
    const users = await listUsers(prisma, req.auth.userId);
    res.json({ users });
  });

  return router;
}
