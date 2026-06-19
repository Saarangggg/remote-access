const logger = require('../utils/logger');

let nutjs = null;
let robotjs = null;

async function getNutJs() {
  if (nutjs) return nutjs;
  try {
    nutjs = require('@nut-tree-fork/nut-js');
    await nutjs.keyboard.type(''); // warm up
    return nutjs;
  } catch {
    return null;
  }
}

function getRobotJs() {
  if (robotjs) return robotjs;
  try {
    robotjs = require('@hurdlegroup/robotjs');
    return robotjs;
  } catch {
    return null;
  }
}

// Map from phone key names to nut-js Key enum values
const NUT_KEY_MAP = {
  Enter: 'Return',
  Escape: 'Escape',
  Tab: 'Tab',
  Backspace: 'Backspace',
  Delete: 'Delete',
  Space: 'Space',
  ArrowUp: 'Up',
  ArrowDown: 'Down',
  ArrowLeft: 'Left',
  ArrowRight: 'Right',
  Home: 'Home',
  End: 'End',
  PageUp: 'PageUp',
  PageDown: 'PageDown',
  F1: 'F1', F2: 'F2', F3: 'F3', F4: 'F4', F5: 'F5',
  F6: 'F6', F7: 'F7', F8: 'F8', F9: 'F9', F10: 'F10',
  F11: 'F11', F12: 'F12',
  Control: 'LeftControl',
  Alt: 'LeftAlt',
  Shift: 'LeftShift',
  Meta: 'LeftSuper',
  CapsLock: 'CapsLock',
  Insert: 'Insert',
  PrintScreen: 'Print',
};

// Map for robotjs
const ROBOT_KEY_MAP = {
  Enter: 'enter',
  Escape: 'escape',
  Tab: 'tab',
  Backspace: 'backspace',
  Delete: 'delete',
  Space: 'space',
  ArrowUp: 'up',
  ArrowDown: 'down',
  ArrowLeft: 'left',
  ArrowRight: 'right',
  Home: 'home',
  End: 'end',
  PageUp: 'pageup',
  PageDown: 'pagedown',
  F1: 'f1', F2: 'f2', F3: 'f3', F4: 'f4', F5: 'f5',
  F6: 'f6', F7: 'f7', F8: 'f8', F9: 'f9', F10: 'f10',
  F11: 'f11', F12: 'f12',
  Control: 'control',
  Alt: 'alt',
  Shift: 'shift',
  Meta: 'command',
};

/**
 * Handle keyboard event from phone
 * data: { key, text, modifiers, coexistMode }
 * - key: special key name (e.g. 'Enter', 'Escape', 'F5')
 * - text: regular text to type
 * - modifiers: array of modifier keys ['ctrl', 'alt', 'shift', 'meta']
 */
async function handleKeyEvent(data) {
  const { key, text, modifiers = [], coexistMode = false } = data;

  if (coexistMode === 'independent') {
    const independentManager = require('./independentManager');
    if (text && !key) {
      independentManager.type(text);
    } else if (key) {
      independentManager.key(key, modifiers);
    }
    return;
  }

  const nut = await getNutJs();

  if (nut) {
    await _handleNutKey(nut, key, text, modifiers);
  } else {
    const r = getRobotJs();
    if (r) _handleRobotKey(r, key, text, modifiers);
  }
}

async function _handleNutKey(nut, key, text, modifiers) {
  const { keyboard, Key } = nut;

  try {
    if (text && !key) {
      // Type regular text
      await keyboard.type(text);
      return;
    }

    let nutKey = NUT_KEY_MAP[key];
    if (!nutKey && key && key.length === 1) {
      const upper = key.toUpperCase();
      if (Key[upper] !== undefined) {
        nutKey = upper;
      }
    }

    if (!nutKey) {
      // Try typing as text
      if (key && key.length === 1) await keyboard.type(key);
      return;
    }

    const keys = [];

    // Add modifiers
    if (modifiers.includes('ctrl') || modifiers.includes('control')) keys.push(Key.LeftControl);
    if (modifiers.includes('alt')) keys.push(Key.LeftAlt);
    if (modifiers.includes('shift')) keys.push(Key.LeftShift);
    if (modifiers.includes('meta') || modifiers.includes('super')) keys.push(Key.LeftSuper);

    const actualKey = Key[nutKey];
    if (actualKey !== undefined) {
      keys.push(actualKey);
    }

    // Filter undefined keys
    const validKeys = keys.filter(Boolean);
    if (validKeys.length > 0) {
      await keyboard.pressKey(...validKeys);
      await keyboard.releaseKey(...validKeys);
    }
  } catch (err) {
    logger.error('nut-js key error:', err.message);
  }
}

function _handleRobotKey(r, key, text, modifiers) {
  try {
    if (text && !key) {
      r.typeString(text);
      return;
    }

    let robotKey = ROBOT_KEY_MAP[key];
    if (!robotKey && key && key.length === 1) {
      robotKey = key.toLowerCase();
    }

    if (modifiers.length > 0 && robotKey) {
      r.keyTap(robotKey, modifiers.map(m => m === 'ctrl' ? 'control' : m));
    } else if (robotKey) {
      r.keyTap(robotKey);
    } else if (key && key.length === 1) {
      r.typeString(key);
    }
  } catch (err) {
    logger.error('robotjs key error:', err.message);
  }
}

module.exports = { handleKeyEvent };
