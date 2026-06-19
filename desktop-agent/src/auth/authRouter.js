const express = require('express');
const router = express.Router();
const Joi = require('joi');
const config = require('../utils/config');
const logger = require('../utils/logger');
const { generateAccessToken, generateRefreshToken, verifyRefreshToken, requireAuth } = require('./jwt');
const { addDevice, getAllDevices, removeDevice, revokeAllSessions } = require('./deviceStore');

// Validation schemas
const pairSchema = Joi.object({
  username: Joi.string().required(),
  password: Joi.string().required(),
  deviceId: Joi.string().required(),
  deviceName: Joi.string().max(64).required(),
  platform: Joi.string().optional(),
});

const refreshSchema = Joi.object({
  refreshToken: Joi.string().required(),
});

/**
 * POST /api/auth/pair
 * Login with username + password and issue tokens to a new device
 */
router.post('/pair', async (req, res) => {
  const { error, value } = pairSchema.validate(req.body);
  if (error) return res.status(400).json({ error: error.details[0].message });

  const { username, password, deviceId, deviceName, platform } = value;

  const expectedUser = process.env.AGENT_USER || 'sarang';
  const expectedPass = process.env.AGENT_PASSWORD || 'Sarang@123';

  if (username !== expectedUser || password !== expectedPass) {
    logger.warn(`Failed login attempt from ${deviceName} (${deviceId}) - invalid credentials`);
    return res.status(401).json({ error: 'Invalid username or password' });
  }

  // Register device
  const device = await addDevice({ deviceId, deviceName, platform });

  const tokenPayload = {
    deviceId,
    deviceName,
    platform: platform || 'unknown',
  };

  const accessToken = generateAccessToken(tokenPayload);
  const refreshToken = generateRefreshToken(tokenPayload);

  logger.info(`Device paired successfully: ${deviceName}`);

  res.json({
    success: true,
    accessToken,
    refreshToken,
    device: {
      desktopDeviceId: config.deviceId,
      desktopDeviceName: config.deviceName,
    },
  });
});

/**
 * POST /api/auth/refresh
 * Exchange a refresh token for a new access token
 */
router.post('/refresh', (req, res) => {
  const { error, value } = refreshSchema.validate(req.body);
  if (error) return res.status(400).json({ error: error.details[0].message });

  const payload = verifyRefreshToken(value.refreshToken);
  if (!payload) return res.status(401).json({ error: 'Invalid or expired refresh token' });

  const accessToken = generateAccessToken({
    deviceId: payload.deviceId,
    deviceName: payload.deviceName,
    platform: payload.platform,
  });

  res.json({ accessToken });
});

/**
 * GET /api/auth/devices
 * List all trusted devices
 */
router.get('/devices', requireAuth, (req, res) => {
  res.json({ devices: getAllDevices() });
});

/**
 * DELETE /api/auth/devices/:deviceId
 * Remove a trusted device
 */
router.delete('/devices/:deviceId', requireAuth, async (req, res) => {
  const removed = await removeDevice(req.params.deviceId);
  if (!removed) return res.status(404).json({ error: 'Device not found' });
  res.json({ success: true });
});

/**
 * POST /api/auth/logout-all
 * Revoke all sessions
 */
router.post('/logout-all', requireAuth, async (req, res) => {
  await revokeAllSessions();
  res.json({ success: true, message: 'All sessions revoked' });
});

module.exports = router;
