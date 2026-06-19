require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const path = require('path');

const logger = require('./utils/logger');
const config = require('./utils/config');
const { initDeviceStore } = require('./auth/deviceStore');
const { verifySocketToken } = require('./auth/jwt');
const authRouter = require('./auth/authRouter');
const fileRouter = require('./files/fileRouter');
const deviceRouter = require('./device/deviceRouter');
const clipboardRouter = require('./clipboard/clipboardRouter');
const { startScreenStreamer, stopScreenStreamer } = require('./screen/streamer');
const { handleMouseEvent } = require('./input/mouse');
const { handleKeyEvent } = require('./input/keyboard');
const { startClipboardMonitor } = require('./clipboard/clipboardManager');
const tunnelManager = require('./tunnel/tunnelManager');

const app = express();
app.set('trust proxy', 1); // Trust first proxy (e.g. Cloudflare, Nginx)
const httpServer = http.createServer(app);

// ─── Middleware ────────────────────────────────────────────────────────────────
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 60000,
  max: parseInt(process.env.RATE_LIMIT_MAX) || 100,
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api', limiter);

// ─── Routes ───────────────────────────────────────────────────────────────────
app.use('/api/auth', authRouter);
app.use('/api/files', fileRouter);
app.use('/api/device', deviceRouter);
app.use('/api/clipboard', clipboardRouter);

app.get('/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0', agent: config.deviceName });
});

// ─── Socket.IO ────────────────────────────────────────────────────────────────
const io = new Server(httpServer, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
  maxHttpBufferSize: 10 * 1024 * 1024, // 10MB for file chunks
  transports: ['websocket', 'polling'],
});

// Auth middleware for all socket connections
io.use((socket, next) => {
  const token = socket.handshake.auth?.token || socket.handshake.headers?.authorization?.split(' ')[1];
  if (!token) return next(new Error('Authentication required'));
  const payload = verifySocketToken(token);
  if (!payload) return next(new Error('Invalid or expired token'));
  socket.deviceId = payload.deviceId;
  socket.deviceName = payload.deviceName;
  next();
});

// Track active connections
const activeConnections = new Map();

io.on('connection', (socket) => {
  logger.info(`Device connected: ${socket.deviceName} (${socket.id})`);
  activeConnections.set(socket.id, socket);

  // Broadcast device status update
  socket.emit('device:status', config.getDeviceStatus());

  // ── Screen Streaming ──
  socket.on('screen:start', (opts = {}) => {
    const fps = Math.min(opts.fps || 15, 60);
    const quality = opts.quality || 'medium';
    const monitorIndex = opts.monitorIndex || 0;
    logger.info(`Screen stream started: ${fps}FPS, ${quality} quality, monitor ${monitorIndex}`);
    startScreenStreamer(socket, fps, quality, monitorIndex);
  });

  socket.on('screen:stop', () => {
    stopScreenStreamer(socket.id);
    logger.info(`Screen stream stopped for ${socket.id}`);
  });

  // ── Mouse Input ──
  socket.on('input:mouse', async (data) => {
    try {
      await handleMouseEvent(data);
    } catch (e) {
      logger.error('Mouse event error:', e.message);
    }
  });

  // ── Keyboard Input ──
  socket.on('input:key', async (data) => {
    try {
      await handleKeyEvent(data);
    } catch (e) {
      logger.error('Key event error:', e.message);
    }
  });

  // ── Clipboard Sync ──
  socket.on('clipboard:set', async (data) => {
    const { default: clipboardy } = await import('clipboardy');
    if (data?.text) {
      await clipboardy.write(data.text);
      logger.info('Clipboard updated from phone');
    }
  });

  // ── File Transfer Progress Subscribe ──
  socket.on('file:subscribe', () => {
    socket.join('file-progress');
  });

  socket.on('disconnect', (reason) => {
    logger.info(`Device disconnected: ${socket.deviceName} (${reason})`);
    stopScreenStreamer(socket.id);
    activeConnections.delete(socket.id);
  });
});

// Export io for use in other modules
module.exports.io = io;
module.exports.activeConnections = activeConnections;

// ─── Startup ──────────────────────────────────────────────────────────────────
async function start() {
  await initDeviceStore();
  await config.init();

  // Initialize and compile independent input helper
  try {
    const independentManager = require('./input/independentManager');
    independentManager.startProcess();
  } catch (err) {
    logger.error('Failed to initialize independent input manager:', err.message);
  }

  const PORT = parseInt(process.env.PORT) || 3000;

  httpServer.listen(PORT, '0.0.0.0', async () => {
    logger.info(`RemoteConnect Agent running on port ${PORT}`);
    logger.info(`Device: ${config.deviceName} | ID: ${config.deviceId}`);
    logger.info(`Pair Code: ${config.pairCode}`);

    // Start clipboard monitor
    startClipboardMonitor(io);

    // Configure URL based on environment
    if (process.env.CUSTOM_URL) {
      config.tunnelUrl = process.env.CUSTOM_URL;
      logger.info(`Using Custom Server URL: ${config.tunnelUrl}`);
      logger.info(`Agent is ready. Login with credentials set in .env`);
    } else if (process.env.USE_CLOUDFLARE_TUNNEL !== 'false') {
      try {
        const tunnelUrl = await tunnelManager.start(PORT);
        config.tunnelUrl = tunnelUrl;
        logger.info(`Tunnel URL: ${tunnelUrl}`);
      } catch (e) {
        logger.warn('Cloudflare tunnel failed to start:', e.message);
        logger.info('Running in local mode only');
      }
    }
  });
}

start().catch((err) => {
  logger.error('Failed to start agent:', err);
  process.exit(1);
});

// ─── Graceful Shutdown ────────────────────────────────────────────────────────
process.on('SIGINT', () => {
  logger.info('Shutting down...');
  tunnelManager.stop();
  httpServer.close(() => process.exit(0));
});

process.on('uncaughtException', (err) => {
  logger.error('Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason) => {
  logger.error('Unhandled Rejection:', reason);
});
