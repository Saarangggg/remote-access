const logger = require('../utils/logger');

let lastClipboard = '';
let monitorInterval = null;

/**
 * Start monitoring clipboard for changes and emit to all connected sockets
 * @param {import('socket.io').Server} io
 */
async function startClipboardMonitor(io) {
  const { default: clipboardy } = await import('clipboardy');

  try {
    lastClipboard = await clipboardy.read();
  } catch {
    lastClipboard = '';
  }

  monitorInterval = setInterval(async () => {
    try {
      const current = await clipboardy.read();
      if (current !== lastClipboard && current.trim()) {
        lastClipboard = current;
        logger.debug('Clipboard changed, broadcasting...');
        io.emit('clipboard:update', {
          text: current,
          source: 'desktop',
          timestamp: new Date().toISOString(),
        });
      }
    } catch {
      // Clipboard read failure is non-fatal
    }
  }, 500);

  logger.info('Clipboard monitor started');
}

function stopClipboardMonitor() {
  if (monitorInterval) {
    clearInterval(monitorInterval);
    monitorInterval = null;
    logger.info('Clipboard monitor stopped');
  }
}

async function getClipboard() {
  const { default: clipboardy } = await import('clipboardy');
  try {
    return await clipboardy.read();
  } catch {
    return '';
  }
}

async function setClipboard(text) {
  const { default: clipboardy } = await import('clipboardy');
  try {
    await clipboardy.write(text);
    lastClipboard = text;
    return true;
  } catch {
    return false;
  }
}

module.exports = { startClipboardMonitor, stopClipboardMonitor, getClipboard, setClipboard };
