const screenshot = require('screenshot-desktop');
const sharp = require('sharp');
const logger = require('../utils/logger');

const QUALITY_MAP = {
  low: { width: 854, height: 480, jpegQuality: 50 },
  medium: { width: 1280, height: 720, jpegQuality: 70 },
  high: { width: 1920, height: 1080, jpegQuality: 85 },
};

/**
 * Capture the desktop screen and return a JPEG Buffer
 * @param {string} quality - 'low' | 'medium' | 'high'
 * @param {number} [monitorIndex] - optional monitor index (0 = primary)
 * @returns {Promise<{buffer: Buffer, width: number, height: number}>}
 */
async function captureScreen(quality = 'medium', monitorIndex = 0) {
  const { width, height, jpegQuality } = QUALITY_MAP[quality] || QUALITY_MAP.medium;

  try {
    // screenshot-desktop returns a PNG buffer
    let screenshotBuffer;
    const displays = await screenshot.listDisplays();
    if (displays && displays.length > monitorIndex) {
      screenshotBuffer = await screenshot({ screen: displays[monitorIndex].id, format: 'png' });
    } else {
      screenshotBuffer = await screenshot({ format: 'png' });
    }

    // Resize and compress with sharp
    const jpegBuffer = await sharp(screenshotBuffer)
      .resize(width, height, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: jpegQuality, mozjpeg: true })
      .toBuffer();

    return { buffer: jpegBuffer, width, height };
  } catch (err) {
    logger.error('Screen capture error:', err.message);
    throw err;
  }
}

/**
 * Get list of available monitors
 */
async function getDisplays() {
  try {
    const displays = await screenshot.listDisplays();
    return displays.map((d, i) => ({ index: i, id: d.id, name: d.name || `Monitor ${i + 1}` }));
  } catch {
    return [{ index: 0, id: 0, name: 'Primary Monitor' }];
  }
}

module.exports = { captureScreen, getDisplays };
