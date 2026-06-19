const { captureScreen } = require('./capture');
const logger = require('../utils/logger');

// Map of socketId → intervalId for active streaming sessions
const activeStreamers = new Map();

/**
 * Start streaming screen frames to a specific socket at given FPS & quality
 */
function startScreenStreamer(socket, fps = 15, quality = 'medium', monitorIndex = 0) {
  const socketId = socket.id;

  // Stop any existing streamer for this socket
  stopScreenStreamer(socketId);

  const intervalMs = Math.floor(1000 / fps);
  let isCapturing = false;

  const intervalId = setInterval(async () => {
    // Skip frame if previous capture hasn't finished (backpressure)
    if (isCapturing) return;
    if (!socket.connected) {
      stopScreenStreamer(socketId);
      return;
    }

    isCapturing = true;
    try {
      const { buffer, width, height } = await captureScreen(quality, monitorIndex);
      const base64 = buffer.toString('base64');

      socket.emit('screen:frame', {
        data: base64,
        width,
        height,
        timestamp: Date.now(),
      });
    } catch (err) {
      logger.error(`Frame capture error for ${socketId}:`, err.message);
    } finally {
      isCapturing = false;
    }
  }, intervalMs);

  activeStreamers.set(socketId, intervalId);
  logger.debug(`Streamer started: ${socketId} @ ${fps}fps, ${quality}`);
}

/**
 * Stop streaming for a given socket
 */
function stopScreenStreamer(socketId) {
  if (activeStreamers.has(socketId)) {
    clearInterval(activeStreamers.get(socketId));
    activeStreamers.delete(socketId);
    logger.debug(`Streamer stopped: ${socketId}`);
  }
}

/**
 * Stop all active streamers (used on shutdown)
 */
function stopAllStreamers() {
  for (const [id, intervalId] of activeStreamers) {
    clearInterval(intervalId);
    logger.debug(`Streamer stopped: ${id}`);
  }
  activeStreamers.clear();
}

module.exports = { startScreenStreamer, stopScreenStreamer, stopAllStreamers };
