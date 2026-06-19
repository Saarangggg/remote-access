const express = require('express');
const router = express.Router();
const path = require('path');
const fs = require('fs-extra');
const multer = require('multer');
const os = require('os');
const { requireAuth } = require('../auth/jwt');
const logger = require('../utils/logger');

/**
 * Get logical roots/drives on Windows or root directory on Unix.
 */
function getRoots() {
  if (process.platform === 'win32') {
    const drives = [];
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    for (let i = 0; i < letters.length; i++) {
      const drivePath = `${letters[i]}:\\`;
      try {
        if (fs.existsSync(drivePath)) {
          drives.push({
            name: `${letters[i]}: Drive`,
            path: `${letters[i]}:/`,
            type: 'directory',
          });
        }
      } catch (e) {}
    }
    return drives;
  } else {
    return [{
      name: 'Root /',
      path: '/',
      type: 'directory',
    }];
  }
}

/**
 * Resolve any path relative or absolute on the system.
 */
function resolveSafe(clientPath) {
  if (!clientPath || clientPath === '/' || clientPath === '') {
    return null; // root level listing (drives list)
  }
  return path.resolve(clientPath);
}

// ─── Multer Storage ───────────────────────────────────────────────────────────
const storage = multer.diskStorage({
  destination: async (req, file, cb) => {
    const targetPath = resolveSafe(req.query.path || req.body.path);
    if (!targetPath) return cb(new Error('Invalid upload path'));
    await fs.ensureDir(targetPath);
    cb(null, targetPath);
  },
  filename: (req, file, cb) => {
    // Sanitize filename
    const safe = path.basename(file.originalname).replace(/[<>:"/\\|?*]/g, '_');
    cb(null, safe);
  },
});

// No upload size limits
const upload = multer({
  storage,
});

// All file routes require authentication
router.use(requireAuth);

// ─── List Directory ───────────────────────────────────────────────────────────
router.get('/', async (req, res) => {
  const clientPath = req.query.path || '';

  if (!clientPath) {
    const roots = getRoots();
    const shortcuts = [
      { name: '⭐ Desktop', path: path.join(os.homedir(), 'Desktop').replace(/\\/g, '/'), type: 'directory' },
      { name: '⭐ Downloads', path: path.join(os.homedir(), 'Downloads').replace(/\\/g, '/'), type: 'directory' },
      { name: '⭐ Documents', path: path.join(os.homedir(), 'Documents').replace(/\\/g, '/'), type: 'directory' },
      { name: '⭐ Pictures', path: path.join(os.homedir(), 'Pictures').replace(/\\/g, '/'), type: 'directory' },
      { name: '⭐ Videos', path: path.join(os.homedir(), 'Videos').replace(/\\/g, '/'), type: 'directory' },
    ];

    const validShortcuts = [];
    for (const sh of shortcuts) {
      if (fs.existsSync(sh.path)) {
        validShortcuts.push(sh);
      }
    }

    return res.json({ path: '/', items: [...validShortcuts, ...roots] });
  }

  const fullPath = resolveSafe(clientPath);
  if (!fullPath) return res.status(400).json({ error: 'Invalid path' });

  try {
    const stat = await fs.stat(fullPath);
    if (!stat.isDirectory()) return res.status(400).json({ error: 'Not a directory' });

    const entries = await fs.readdir(fullPath, { withFileTypes: true });
    const items = await Promise.all(
      entries.map(async (entry) => {
        const entryPath = path.join(fullPath, entry.name);
        const isDir = entry.isDirectory();
        let size = 0;
        let mtime = null;
        try {
          const s = await fs.stat(entryPath);
          size = s.size;
          mtime = s.mtime.toISOString();
        } catch {}

        return {
          name: entry.name,
          path: path.join(clientPath, entry.name).replace(/\\/g, '/'),
          type: isDir ? 'directory' : 'file',
          size: isDir ? null : size,
          extension: isDir ? null : path.extname(entry.name).toLowerCase(),
          modified: mtime,
        };
      })
    );

    res.json({ path: clientPath, items });
  } catch (err) {
    logger.error('File list error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── Upload File ──────────────────────────────────────────────────────────────
router.post('/upload', upload.array('files', 20), (req, res) => {
  const uploaded = req.files.map(f => ({
    name: f.originalname,
    size: f.size,
    path: req.query.path || '',
  }));
  logger.info(`Uploaded ${uploaded.length} file(s)`);
  res.json({ success: true, files: uploaded });
});

// ─── Download File ────────────────────────────────────────────────────────────
router.get('/download', async (req, res) => {
  const fullPath = resolveSafe(req.query.path);
  if (!fullPath) return res.status(400).json({ error: 'Invalid path' });

  try {
    const stat = await fs.stat(fullPath);
    if (!stat.isFile()) return res.status(400).json({ error: 'Not a file' });
    res.download(fullPath);
  } catch (err) {
    res.status(404).json({ error: 'File not found' });
  }
});

// ─── Delete ───────────────────────────────────────────────────────────────────
router.delete('/delete', async (req, res) => {
  const fullPath = resolveSafe(req.body.path || req.query.path);
  if (!fullPath) return res.status(400).json({ error: 'Invalid path' });

  try {
    await fs.remove(fullPath);
    logger.info(`Deleted: ${fullPath}`);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── Rename ───────────────────────────────────────────────────────────────────
router.patch('/rename', async (req, res) => {
  const { path: oldPath, newName } = req.body;
  const fullOld = resolveSafe(oldPath);
  if (!fullOld) return res.status(400).json({ error: 'Invalid path' });

  const safeName = path.basename(newName).replace(/[<>:"/\\|?*]/g, '_');
  const fullNew = path.join(path.dirname(fullOld), safeName);

  try {
    await fs.rename(fullOld, fullNew);
    logger.info(`Renamed: ${fullOld} → ${fullNew}`);
    res.json({ success: true, newPath: req.body.path.replace(path.basename(oldPath), safeName) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── Move ─────────────────────────────────────────────────────────────────────
router.patch('/move', async (req, res) => {
  const { from, to } = req.body;
  const fullFrom = resolveSafe(from);
  const toDir = resolveSafe(to);
  if (!fullFrom || !toDir) return res.status(400).json({ error: 'Invalid path' });

  const dest = path.join(toDir, path.basename(fullFrom));
  try {
    await fs.move(fullFrom, dest, { overwrite: false });
    logger.info(`Moved: ${fullFrom} → ${dest}`);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── Create Folder ────────────────────────────────────────────────────────────
router.post('/mkdir', async (req, res) => {
  const { path: dirPath } = req.body;
  const fullPath = resolveSafe(dirPath);
  if (!fullPath) return res.status(400).json({ error: 'Invalid path' });

  try {
    await fs.ensureDir(fullPath);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── Search ───────────────────────────────────────────────────────────────────
router.get('/search', async (req, res) => {
  const { q, path: searchPath } = req.query;
  if (!q) return res.status(400).json({ error: 'Query required' });

  const startPath = searchPath ? resolveSafe(searchPath) : null;
  const roots = startPath ? [startPath] : getRoots().map(r => r.path);
  const query = q.toLowerCase();
  const results = [];

  async function searchDir(dir, depth = 0) {
    if (depth > 4 || results.length >= 100) return;
    try {
      const entries = await fs.readdir(dir, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.name.toLowerCase().includes(query)) {
          const entryPath = path.join(dir, entry.name);
          results.push({
            name: entry.name,
            path: entryPath,
            type: entry.isDirectory() ? 'directory' : 'file',
          });
        }
        if (entry.isDirectory() && depth < 4) {
          await searchDir(path.join(dir, entry.name), depth + 1);
        }
        if (results.length >= 100) break;
      }
    } catch {}
  }

  await Promise.all(roots.map(r => searchDir(r)));
  res.json({ query: q, results });
});

module.exports = router;
