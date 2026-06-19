const { spawn } = require('child_process');
const logger = require('../utils/logger');

let cloudflaredProcess = null;
let tunnelUrl = null;

/**
 * Start the Cloudflare tunnel and return the public URL
 * @param {number} port - Local port to tunnel
 * @returns {Promise<string>} - The tunnel URL
 */
function start(port) {
  return new Promise((resolve, reject) => {
    if (tunnelUrl) return resolve(tunnelUrl);

    const cloudflaredBin = process.env.CLOUDFLARED_PATH || 'cloudflared';

    logger.info(`Starting Cloudflare tunnel on port ${port}...`);

    cloudflaredProcess = spawn(cloudflaredBin, [
      'tunnel', '--url', `http://localhost:${port}`,
      '--no-autoupdate',
    ], {
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let resolved = false;
    const timeout = setTimeout(() => {
      if (!resolved) reject(new Error('Cloudflare tunnel timeout (30s)'));
    }, 30000);

    // Parse tunnel URL from stderr output
    const parseUrl = (data) => {
      const str = data.toString();
      const match = str.match(/https:\/\/[a-z0-9\-]+\.trycloudflare\.com/i)
        || str.match(/https:\/\/[a-zA-Z0-9\-\.]+\.cfargotunnel\.com/i);
      if (match && !resolved) {
        resolved = true;
        clearTimeout(timeout);
        tunnelUrl = match[0];
        logger.info(`Tunnel established: ${tunnelUrl}`);
        resolve(tunnelUrl);
      }
    };

    cloudflaredProcess.stdout.on('data', parseUrl);
    cloudflaredProcess.stderr.on('data', parseUrl);

    cloudflaredProcess.on('close', (code) => {
      logger.warn(`cloudflared exited with code ${code}`);
      tunnelUrl = null;
      cloudflaredProcess = null;
      if (!resolved) {
        resolved = true;
        clearTimeout(timeout);
        reject(new Error(`cloudflared exited with code ${code}`));
      }
    });

    cloudflaredProcess.on('error', (err) => {
      logger.error('cloudflared error:', err.message);
      if (!resolved) {
        resolved = true;
        clearTimeout(timeout);
        reject(err);
      }
    });
  });
}

function stop() {
  if (cloudflaredProcess) {
    cloudflaredProcess.kill();
    cloudflaredProcess = null;
    tunnelUrl = null;
    logger.info('Cloudflare tunnel stopped');
  }
}

function getUrl() {
  return tunnelUrl;
}

module.exports = { start, stop, getUrl };
