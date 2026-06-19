const express = require('express');
const router = express.Router();
const os = require('os');
const { requireAuth } = require('../auth/jwt');
const config = require('../utils/config');
const { getDisplays } = require('../screen/capture');
const logger = require('../utils/logger');

router.use(requireAuth);

// GET /api/device/status — full device status
router.get('/status', (req, res) => {
  res.json(config.getDeviceStatus());
});

// GET /api/device/info — basic device info + tunnel URL
router.get('/info', (req, res) => {
  res.json({
    deviceId: config.deviceId,
    deviceName: config.deviceName,
    platform: os.platform(),
    tunnelUrl: config.tunnelUrl,
    agentVersion: '1.0.0',
  });
});

// GET /api/device/displays — list available monitors
router.get('/displays', async (req, res) => {
  const displays = await getDisplays();
  res.json({ displays });
});

// GET /api/device/apps — list installed programs scanned from Start Menu
router.get('/apps', async (req, res) => {
  const fs = require('fs-extra');
  const path = require('path');
  const os = require('os');

  const apps = [];
  const pathsToScan = [];

  // Common start menu programs
  const commonPrograms = 'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs';
  try {
    if (await fs.exists(commonPrograms)) {
      pathsToScan.push(commonPrograms);
    }
  } catch (e) {}

  // User start menu programs
  const userPrograms = path.join(os.homedir(), 'AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs');
  try {
    if (await fs.exists(userPrograms)) {
      pathsToScan.push(userPrograms);
    }
  } catch (e) {}

  async function scanDir(dir, depth = 0) {
    if (depth > 3) return; // avoid deep recursion
    try {
      const entries = await fs.readdir(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          await scanDir(fullPath, depth + 1);
        } else if (entry.isFile() && entry.name.toLowerCase().endsWith('.lnk')) {
          const name = path.basename(entry.name, '.lnk');
          const lowerName = name.toLowerCase();
          // Exclude uninstallers or documentation links
          if (!lowerName.includes('uninstall') && 
              !lowerName.includes('help') && 
              !lowerName.includes('readme') && 
              !lowerName.includes('read me') && 
              !lowerName.includes('documentation') &&
              !lowerName.includes('website')) {
            apps.push({
              name: name,
              path: fullPath.replace(/\\/g, '/'),
            });
          }
        }
      }
    } catch (e) {
      // Ignore read errors
    }
  }

  try {
    for (const p of pathsToScan) {
      await scanDir(p);
    }

    // Sort alphabetically by name
    apps.sort((a, b) => a.name.localeCompare(b.name));

    // Remove duplicates
    const uniqueApps = [];
    const seen = new Set();
    for (const app of apps) {
      const normName = app.name.toLowerCase();
      if (!seen.has(normName)) {
        seen.add(normName);
        uniqueApps.push(app);
      }
    }

    res.json({ apps: uniqueApps });
  } catch (err) {
    logger.error(`Failed to scan installed apps: ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/device/open-app — open a specific desktop app or execute command
router.post('/open-app', (req, res) => {
  const { appName, command } = req.body;
  const { exec } = require('child_process');

  let cmd = '';
  if (command) {
    if (command.toLowerCase().endsWith('.lnk')) {
      cmd = `start "" "${command}"`;
    } else {
      cmd = command;
    }
  } else {
    switch (appName?.toLowerCase()) {
      case 'notepad':
        cmd = 'start notepad';
        break;
      case 'calculator':
      case 'calc':
        cmd = 'start calc';
        break;
      case 'cmd':
      case 'command prompt':
        cmd = 'start cmd';
        break;
      case 'powershell':
        cmd = 'start powershell';
        break;
      case 'explorer':
      case 'file explorer':
        cmd = 'start explorer';
        break;
      case 'chrome':
        cmd = 'start chrome';
        break;
      case 'taskmgr':
      case 'task manager':
        cmd = 'start taskmgr';
        break;
      default:
        return res.status(400).json({ error: 'Unsupported application or command' });
    }
  }

  // Windows-specific wrapping for robust launch
  if (process.platform === 'win32') {
    cmd = `cmd.exe /c "${cmd}"`;
  }

  logger.info(`Opening application: ${appName || cmd}`);
  exec(cmd, (err) => {
    if (err) {
      logger.error(`Failed to launch app/command: ${err.message}`);
      return res.status(500).json({ error: err.message });
    }
    res.json({ success: true });
  });
});

module.exports = router;
