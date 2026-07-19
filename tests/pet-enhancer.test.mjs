import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = await fs.readFile(path.resolve(here, "../assets/pet-enhancer.js"), "utf8");
assert.doesNotMatch(source, /codex-dream-skin-style|--dream-background|--dream-character/);

function mainFixture() {
  const stored = [];
  const messages = [];
  const listeners = new Map();
  const spinners = [0, 1].map(() => ({
    closest() { return {}; },
  }));
  const sidebar = {
    querySelectorAll(selector) { return selector === ".animate-spin" ? spinners : []; },
  };
  const rootClasses = new Set();
  const rootStyles = new Map();
  const document = {
    documentElement: {
      classList: { contains: (name) => rootClasses.has(name) },
      style: { getPropertyValue: (name) => rootStyles.get(name) || "" },
    },
    querySelector(selector) {
      return selector === "aside.app-shell-left-panel" ? sidebar : null;
    },
    getElementById() { return null; },
    addEventListener(name, callback) { listeners.set(name, callback); },
    removeEventListener(name) { listeners.delete(name); },
  };
  const window = { screenX: 10, screenY: 20 };
  const context = {
    window,
    document,
    location: { search: "" },
    performance: { now: () => 1000 },
    Date,
    localStorage: { setItem(key, value) { stored.push({ key, value: JSON.parse(value) }); } },
    BroadcastChannel: class {
      postMessage(value) { messages.push(value); }
      close() {}
    },
    getComputedStyle: () => ({ display: "block" }),
    setInterval: () => 1,
    clearInterval() {},
  };
  return { context, window, stored, messages, listeners, rootClasses, rootStyles };
}

const main = mainFixture();
const mainResult = vm.runInNewContext(source, main.context);
assert.equal(mainResult.kind, "main");
assert.equal(mainResult.version, "1.0.1");
assert.equal(main.window.__CODEX_KIANA_PET_ENHANCER_STATE__.busyCount, 2);
assert.equal(main.messages.at(-1).working, true);
assert.equal(main.messages.at(-1).busyCount, 2);
assert.equal(main.rootClasses.size, 0, "pet-only bridge must not theme the document root");
assert.equal(main.rootStyles.size, 0, "pet-only bridge must not set theme variables");
assert.equal(main.listeners.has("pointermove"), true);
main.listeners.get("pointermove")({ screenX: 300, screenY: 200, clientX: 0, clientY: 0 });
assert.equal(main.messages.at(-1).type, "pointer");
assert.equal(main.window.__CODEX_KIANA_PET_ENHANCER_STATE__.cleanup(), true);
assert.equal(main.window.__CODEX_KIANA_PET_ENHANCER_STATE__, undefined);
assert.equal(main.listeners.has("pointermove"), false);

function overlayFixture() {
  const styleValues = new Map();
  let animationCallback = null;
  let wallNow = 100_000;
  const style = {
    setProperty(key, value) { styleValues.set(key, value); },
    removeProperty(key) { styleValues.delete(key); },
  };
  const avatar = {
    dataset: { avatarState: "idle" },
    style,
    removeAttribute(key) {
      if (key === "data-dream-pet-moving") delete this.dataset.dreamPetMoving;
      if (key === "data-dream-pet-owned") delete this.dataset.dreamPetOwned;
    },
    getBoundingClientRect() { return { x: 130, left: 130, right: 270, width: 140, height: 152 }; },
  };
  const button = {
    dataset: {},
    removeAttribute(key) {
      if (key === "data-dream-pet-moving") delete this.dataset.dreamPetMoving;
    },
    getBoundingClientRect() { return { x: 130, left: 130, right: 270, width: 140, height: 152 }; },
  };
  const nodes = new Map();
  const root = {
    clientWidth: 400,
    appendChild(node) { nodes.set(node.id, node); },
  };
  const document = {
    documentElement: root,
    head: root,
    body: { clientWidth: 400 },
    createElement() { return { id: "", textContent: "", remove() { nodes.delete(this.id); } }; },
    getElementById(id) { return nodes.get(id) ?? null; },
    querySelector(selector) {
      if (selector === '[data-testid="avatar-mascot-button"]') return button;
      if (selector === '[data-testid="codex-avatar"]') return avatar;
      return null;
    },
    querySelectorAll() { return []; },
    addEventListener() {},
    removeEventListener() {},
  };
  const window = { addEventListener() {}, removeEventListener() {}, screenX: 0, screenY: 0 };
  const context = {
    window,
    document,
    location: { search: "?initialRoute=%2Favatar-overlay" },
    innerWidth: 400,
    performance: { now: () => 1000 },
    Date: { now: () => wallNow },
    localStorage: {
      getItem() {
        return JSON.stringify({ type: "status", working: true, busyCount: 2, timestamp: 100_000 });
      },
    },
    MutationObserver: class { observe() {} disconnect() {} },
    requestAnimationFrame(callback) { animationCallback = callback; return 1; },
    cancelAnimationFrame() {},
  };
  return {
    context,
    window,
    avatar,
    button,
    nodes,
    styleValues,
    setWallNow(value) { wallNow = value; },
    tick(now) { animationCallback(now); },
  };
}

const overlay = overlayFixture();
const overlayResult = vm.runInNewContext(source, overlay.context);
assert.equal(overlayResult.kind, "avatar-overlay");
assert.equal(overlayResult.version, "1.0.1");
overlay.setWallNow(120_000);
overlay.tick(3_300);
assert.equal(overlay.button.dataset.dreamPetMoving, "true");
assert.equal(overlay.avatar.dataset.dreamPetMoving, "true");
assert.equal(overlay.styleValues.get("--dream-pet-scale-x"), "-1");
assert.equal(overlay.styleValues.get("--dream-pet-frame-y"), "10%");
assert.match(overlay.nodes.get("codex-dream-pet-overlay-style").textContent, /pointer-events:\s*none\s*!important/);
overlay.avatar.dataset.avatarState = "failed";
overlay.tick(5_000);
assert.equal(overlay.button.dataset.dreamPetMoving, undefined);
assert.equal(overlay.styleValues.get("--dream-pet-frame-y"), "50%");
overlay.tick(12_000);
assert.equal(overlay.styleValues.get("--dream-pet-frame-x"), "100%");
overlay.tick(20_000);
assert.equal(overlay.styleValues.get("--dream-pet-frame-x"), "100%");

console.log("PASS: pet enhancer preserves work, pointer, running, and failed behavior without applying the theme.");
