const express = require('express');
const router = express.Router();
const { requireAuth } = require('../auth/jwt');
const { getClipboard, setClipboard } = require('./clipboardManager');

router.use(requireAuth);

// GET /api/clipboard — read current clipboard
router.get('/', async (req, res) => {
  const text = await getClipboard();
  res.json({ text, timestamp: new Date().toISOString() });
});

// POST /api/clipboard/sync — write to clipboard
router.post('/sync', async (req, res) => {
  const { text } = req.body;
  if (!text && text !== '') return res.status(400).json({ error: 'text is required' });
  const ok = await setClipboard(text);
  res.json({ success: ok });
});

module.exports = router;
