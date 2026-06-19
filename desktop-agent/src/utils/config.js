const path = require('path');
const fs = require('fs-extra');
const { v4: uuidv4 } = require('uuid');
const os = require('os');
const logger = require('./logger');

const CONFIG_DIR = path.join(process.env.APPDATA || os.homedir(), 'RemoteConnect');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');

class Config {
  constructor() {
    this.deviceId = '';
    this.deviceName = process.env.DEVICE_NAME || os.hostname();
    this.pairCode = '';
    this.tunnelUrl = '';
    this._data = {};
  }

  async init() {
    await fs.ensureDir(CONFIG_DIR);

    if (await fs.pathExists(CONFIG_FILE)) {
      try {
        this._data = await fs.readJson(CONFIG_FILE);
      } catch {
        this._data = {};
      }
    }

    // Generate device ID if not set
    if (!this._data.deviceId) {
      this._data.deviceId = uuidv4();
    }

    // Generate pair code if not set
    if (!this._data.pairCode) {
      this._data.pairCode = Math.floor(100000 + Math.random() * 900000).toString();
    }

    this.deviceId = this._data.deviceId;
    this.deviceName = this._data.deviceName || this.deviceName;
    this.pairCode = this._data.pairCode;

    await this.save();
    logger.info(`Config initialized. Device: ${this.deviceName} | ID: ${this.deviceId}`);
  }

  async save() {
    await fs.writeJson(CONFIG_FILE, {
      ...this._data,
      deviceId: this.deviceId,
      deviceName: this.deviceName,
      pairCode: this.pairCode,
    }, { spaces: 2 });
  }

  async regeneratePairCode() {
    this.pairCode = Math.floor(100000 + Math.random() * 900000).toString();
    await this.save();
    return this.pairCode;
  }

  getDeviceStatus() {
    return {
      deviceId: this.deviceId,
      deviceName: this.deviceName,
      platform: os.platform(),
      arch: os.arch(),
      uptime: os.uptime(),
      freeMemory: os.freemem(),
      totalMemory: os.totalmem(),
      cpus: os.cpus().length,
      networkInterfaces: this._getLocalIP(),
      tunnelUrl: this.tunnelUrl,
      agentVersion: '1.0.0',
      timestamp: new Date().toISOString(),
    };
  }

  _getLocalIP() {
    const nets = os.networkInterfaces();
    const addresses = [];
    for (const name of Object.keys(nets)) {
      for (const net of nets[name]) {
        if (net.family === 'IPv4' && !net.internal) {
          addresses.push({ interface: name, address: net.address });
        }
      }
    }
    return addresses;
  }

  getConfigDir() {
    return CONFIG_DIR;
  }
}

module.exports = new Config();
