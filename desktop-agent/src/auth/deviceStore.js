const path = require('path');
const fs = require('fs-extra');
const { v4: uuidv4 } = require('uuid');
const logger = require('../utils/logger');

let storePath = '';
let store = { devices: [], revokedTokens: [] };

async function initDeviceStore() {
  const configDir = path.join(process.env.APPDATA || require('os').homedir(), 'RemoteConnect');
  await fs.ensureDir(configDir);
  storePath = path.join(configDir, 'devices.json');

  if (await fs.pathExists(storePath)) {
    try {
      store = await fs.readJson(storePath);
      if (!store.devices) store.devices = [];
      if (!store.revokedTokens) store.revokedTokens = [];
    } catch {
      store = { devices: [], revokedTokens: [] };
    }
  }

  logger.info(`Device store loaded: ${store.devices.length} trusted devices`);
}

async function saveStore() {
  await fs.writeJson(storePath, store, { spaces: 2 });
}

/**
 * Register a new trusted device after pairing
 */
async function addDevice({ deviceId, deviceName, platform }) {
  const existing = store.devices.find(d => d.deviceId === deviceId);
  if (existing) {
    existing.lastSeen = new Date().toISOString();
    existing.deviceName = deviceName;
    await saveStore();
    return existing;
  }

  const device = {
    id: uuidv4(),
    deviceId,
    deviceName,
    platform: platform || 'unknown',
    pairedAt: new Date().toISOString(),
    lastSeen: new Date().toISOString(),
    trusted: true,
  };

  store.devices.push(device);
  await saveStore();
  logger.info(`New device paired: ${deviceName} (${deviceId})`);
  return device;
}

/**
 * Check if a device is trusted
 */
function isTrustedDevice(deviceId) {
  return store.devices.some(d => d.deviceId === deviceId && d.trusted);
}

/**
 * Get all trusted devices
 */
function getAllDevices() {
  return store.devices.map(d => ({
    id: d.id,
    deviceId: d.deviceId,
    deviceName: d.deviceName,
    platform: d.platform,
    pairedAt: d.pairedAt,
    lastSeen: d.lastSeen,
    trusted: d.trusted,
  }));
}

/**
 * Remove a device from trusted list
 */
async function removeDevice(deviceId) {
  const before = store.devices.length;
  store.devices = store.devices.filter(d => d.deviceId !== deviceId);
  if (store.devices.length < before) {
    await saveStore();
    return true;
  }
  return false;
}

/**
 * Update last seen time for a device
 */
async function updateLastSeen(deviceId) {
  const device = store.devices.find(d => d.deviceId === deviceId);
  if (device) {
    device.lastSeen = new Date().toISOString();
    await saveStore();
  }
}

/**
 * Revoke all sessions (logout all devices)
 */
async function revokeAllSessions() {
  store.revokedTokens.push({
    revokedAt: new Date().toISOString(),
    reason: 'logout_all',
  });
  await saveStore();
}

module.exports = {
  initDeviceStore,
  addDevice,
  isTrustedDevice,
  getAllDevices,
  removeDevice,
  updateLastSeen,
  revokeAllSessions,
};
