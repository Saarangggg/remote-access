const jwt = require('jsonwebtoken');
const logger = require('../utils/logger');

const ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'remoteconnect_access_secret_dev';
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'remoteconnect_refresh_secret_dev';
const ACCESS_EXPIRY = process.env.JWT_ACCESS_EXPIRY || '15m';
const REFRESH_EXPIRY = process.env.JWT_REFRESH_EXPIRY || '7d';

/**
 * Generate an access token for a paired device
 */
function generateAccessToken(payload) {
  return jwt.sign(payload, ACCESS_SECRET, { expiresIn: ACCESS_EXPIRY });
}

/**
 * Generate a refresh token for a paired device
 */
function generateRefreshToken(payload) {
  return jwt.sign(payload, REFRESH_SECRET, { expiresIn: REFRESH_EXPIRY });
}

/**
 * Verify an access token — returns payload or null
 */
function verifyAccessToken(token) {
  try {
    return jwt.verify(token, ACCESS_SECRET);
  } catch (e) {
    return null;
  }
}

/**
 * Verify a refresh token — returns payload or null
 */
function verifyRefreshToken(token) {
  try {
    return jwt.verify(token, REFRESH_SECRET);
  } catch (e) {
    return null;
  }
}

/**
 * Socket.IO middleware verification — checks access token
 */
function verifySocketToken(token) {
  return verifyAccessToken(token);
}

/**
 * Express middleware — requires valid Authorization: Bearer <token>
 */
function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Authorization header required' });
  }
  const token = authHeader.split(' ')[1];
  const payload = verifyAccessToken(token);
  if (!payload) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
  req.device = payload;
  next();
}

module.exports = {
  generateAccessToken,
  generateRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
  verifySocketToken,
  requireAuth,
};
