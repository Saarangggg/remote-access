const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const logger = require('../utils/logger');

const CS_FILE = path.join(__dirname, 'background-input.cs');
const EXE_FILE = path.join(__dirname, 'background-input.exe');
const CSC_PATH = 'C:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\csc.exe';

let childProcess = null;

function compileBinary() {
  if (fs.existsSync(EXE_FILE)) {
    logger.info('background-input.exe already exists, skipping compilation.');
    return;
  }
  
  if (!fs.existsSync(CSC_PATH)) {
    throw new Error(`C# compiler csc.exe not found at ${CSC_PATH}`);
  }
  
  logger.info('Compiling background-input.cs to background-input.exe...');
  try {
    execSync(`"${CSC_PATH}" /out:"${EXE_FILE}" "${CS_FILE}"`, { stdio: 'pipe' });
    logger.info('Compilation successful!');
  } catch (err) {
    const errorMsg = err.stdout?.toString() || err.stderr?.toString() || err.message;
    logger.error('C# Compilation failed:', errorMsg);
    throw new Error(errorMsg);
  }
}

function startProcess() {
  if (childProcess) return;
  
  try {
    compileBinary();
  } catch (err) {
    logger.error('Failed to compile background input executable, independent mode will not work:', err.message);
    return;
  }
  
  if (!fs.existsSync(EXE_FILE)) {
    logger.error('background-input.exe is missing even after compilation attempt');
    return;
  }
  
  logger.info(`Spawning background-input.exe: ${EXE_FILE}`);
  childProcess = spawn(EXE_FILE, [], { stdio: ['pipe', 'pipe', 'inherit'] });
  
  childProcess.stdout.on('data', (data) => {
    logger.info(`[background-input] ${data.toString().trim()}`);
  });
  
  childProcess.on('close', (code) => {
    logger.warn(`background-input.exe process exited with code ${code}`);
    childProcess = null;
  });
}

function sendCommand(cmd) {
  if (!childProcess) {
    startProcess();
  }
  if (childProcess && childProcess.stdin.writable) {
    childProcess.stdin.write(cmd + '\n');
  } else {
    logger.warn(`Cannot send command "${cmd}", background process is not running or stdin is closed`);
  }
}

function click(x, y, button) {
  sendCommand(`click ${x} ${y} ${button}`);
}

function move(x, y) {
  sendCommand(`move ${x} ${y}`);
}

function down(x, y, button) {
  sendCommand(`down ${x} ${y} ${button}`);
}

function up(x, y, button) {
  sendCommand(`up ${x} ${y} ${button}`);
}

function scroll(x, y, scrollDelta) {
  // Convert typical scrollDelta.dy (+/- 3) to Windows WHEEL_DELTA (+/- 120)
  const dy = scrollDelta.dy || 0;
  // dy > 0 in Flutter is scroll down (negative wheel delta in Win32)
  // dy < 0 in Flutter is scroll up (positive wheel delta in Win32)
  const win32Delta = Math.round(-dy * 40);
  sendCommand(`scroll ${x} ${y} ${win32Delta}`);
}

function type(text) {
  sendCommand(`type ${text}`);
}

function key(keyname, modifiers = []) {
  sendCommand(`key ${keyname} ${modifiers.join(' ')}`);
}

module.exports = {
  startProcess,
  click,
  move,
  down,
  up,
  scroll,
  type,
  key
};
