const logger = require('../utils/logger');

let robot = null;

async function getRobot() {
  if (robot) return robot;
  try {
    robot = require('@nut-tree-fork/nut-js');
    const { mouse, straightTo, Point } = robot;
    // Test that nut-js works
    await mouse.getPosition();
    logger.info('Input: using @nut-tree-fork/nut-js');
    return robot;
  } catch (e) {
    logger.warn('nut-js not available, trying robotjs fallback:', e.message);
    try {
      robot = require('@hurdlegroup/robotjs');
      robot._isRobotjs = true;
      logger.info('Input: using @hurdlegroup/robotjs fallback');
      return robot;
    } catch (e2) {
      logger.error('No mouse/keyboard library available:', e2.message);
      robot = null;
      return null;
    }
  }
}

let lastFinalX = 0;
let lastFinalY = 0;

/**
 * Handle incoming mouse event from phone
 * data: { type, x, y, button, screenWidth, screenHeight }
 * - type: 'move' | 'down' | 'up' | 'click' | 'dblclick' | 'rclick' | 'scroll'
 * - x, y: normalized (0-1) phone-relative coordinates mapped to desktop
 * - scrollDelta: { dx, dy } for scroll events
 */
async function handleMouseEvent(data) {
  const r = await getRobot();
  if (!r) return;

  const { type, x, y, button = 'left', scrollDelta, monitorIndex = 0, coexistMode = false } = data;

  let finalX = lastFinalX;
  let finalY = lastFinalY;

  if (x !== undefined && y !== undefined) {
    finalX = Math.round(x);
    finalY = Math.round(y);
    try {
      const screenshot = require('screenshot-desktop');
      const displays = await screenshot.listDisplays();
      if (displays && displays.length > monitorIndex) {
        const d = displays[monitorIndex];
        const normalizedX = x / 1920;
        const normalizedY = y / 1080;
        finalX = d.left + Math.round(normalizedX * d.width);
        finalY = d.top + Math.round(normalizedY * d.height);
      }
    } catch (err) {
      logger.error('Failed to map coordinates for multi-monitor:', err.message);
    }
    lastFinalX = finalX;
    lastFinalY = finalY;
  }

  if (coexistMode === 'independent' || coexistMode === 'independent') {
    const independentManager = require('./independentManager');
    if (type === 'scroll') {
      independentManager.scroll(finalX, finalY, scrollDelta || { dx: 0, dy: 0 });
    } else if (type === 'move') {
      independentManager.move(finalX, finalY);
    } else if (type === 'click') {
      independentManager.click(finalX, finalY, button);
    } else if (type === 'dblclick') {
      independentManager.click(finalX, finalY, 'double');
    } else if (type === 'rclick') {
      independentManager.click(finalX, finalY, 'right');
    } else if (type === 'down') {
      independentManager.down(finalX, finalY, button);
    } else if (type === 'up') {
      independentManager.up(finalX, finalY, button);
    }
    return;
  }

  if (r._isRobotjs) {
    await _handleRobotjs(r, type, finalX, finalY, button, scrollDelta, coexistMode);
  } else {
    await _handleNutJs(r, type, finalX, finalY, button, scrollDelta, coexistMode);
  }
}

async function _handleNutJs(r, type, x, y, button, scrollDelta, coexistMode) {
  const { mouse, straightTo, Point, Button } = r;

  const absX = Math.round(x);
  const absY = Math.round(y);

  const btnMap = { left: Button.LEFT, right: Button.RIGHT, middle: Button.MIDDLE };
  const btn = btnMap[button] || Button.LEFT;

  // Cursors coexist backup
  let prevPoint = null;
  const isClickAction = ['click', 'dblclick', 'rclick', 'down'].includes(type);
  if (coexistMode && isClickAction) {
    try {
      prevPoint = await mouse.getPosition();
    } catch {}
  }

  switch (type) {
    case 'move':
      await mouse.move(straightTo(new Point(absX, absY)));
      break;
    case 'click':
      await mouse.move(straightTo(new Point(absX, absY)));
      await mouse.click(btn);
      break;
    case 'dblclick':
      await mouse.move(straightTo(new Point(absX, absY)));
      await mouse.doubleClick(btn);
      break;
    case 'rclick':
      await mouse.move(straightTo(new Point(absX, absY)));
      await mouse.click(Button.RIGHT);
      break;
    case 'down':
      await mouse.move(straightTo(new Point(absX, absY)));
      await mouse.pressButton(btn);
      break;
    case 'up':
      await mouse.releaseButton(btn);
      break;
    case 'scroll':
      if (scrollDelta) {
        const { scrollWheel } = require('@nut-tree-fork/nut-js');
        await scrollWheel.scrollDown(Math.abs(scrollDelta.dy));
      }
      break;
    default:
      break;
  }

  // Restore cursor position
  if (coexistMode && prevPoint) {
    try {
      await mouse.move(straightTo(prevPoint));
    } catch {}
  }
}

async function _handleRobotjs(r, type, x, y, button, scrollDelta, coexistMode) {
  const absX = Math.round(x);
  const absY = Math.round(y);
  const btnMap = { left: 'left', right: 'right', middle: 'middle' };
  const btn = btnMap[button] || 'left';

  // Cursors coexist backup
  let prevPos = null;
  const isClickAction = ['click', 'dblclick', 'rclick', 'down'].includes(type);
  if (coexistMode && isClickAction) {
    try {
      prevPos = r.getMousePos();
    } catch {}
  }

  switch (type) {
    case 'move':
      r.moveMouse(absX, absY);
      break;
    case 'click':
      r.moveMouse(absX, absY);
      r.mouseClick(btn);
      break;
    case 'dblclick':
      r.moveMouse(absX, absY);
      r.mouseClick(btn, true);
      break;
    case 'rclick':
      r.moveMouse(absX, absY);
      r.mouseClick('right');
      break;
    case 'down':
      r.moveMouse(absX, absY);
      r.mouseToggle('down', btn);
      break;
    case 'up':
      r.mouseToggle('up', btn);
      break;
    case 'scroll':
      if (scrollDelta) r.scrollMouse(scrollDelta.dx || 0, scrollDelta.dy || 0);
      break;
    default:
      break;
  }

  // Restore cursor position
  if (coexistMode && prevPos) {
    try {
      r.moveMouse(prevPos.x, prevPos.y);
    } catch {}
  }
}

module.exports = { handleMouseEvent };
