(() => {
  const VERSION = "1.0.3";
  const BRIDGE_STATE_KEY = "__CODEX_KIANA_PET_ENHANCER_STATE__";
  const OVERLAY_STATE_KEY = "__CODEX_DREAM_PET_OVERLAY_STATE__";
  const OVERLAY_STYLE_ID = "codex-dream-pet-overlay-style";
  const CHANNEL_NAME = "codex-dream-pet-v1";
  const STORAGE_KEY = "__codex_dream_pet_status_v1__";
  const isAvatarOverlay = /(?:^|[?&])initialRoute=(?:%2F|\/)avatar-overlay(?:&|$)/i
    .test(globalThis.location?.search || "");

  if (isAvatarOverlay) {
    window[OVERLAY_STATE_KEY]?.cleanup?.();
    const framePosition = (row, column) => ({
      x: `${(column / 7) * 100}%`,
      y: `${(row / 10) * 100}%`,
    });
    const animations = {
      wave: { row: 3, durations: [320, 360, 360, 720] },
      ponder: { row: 6, durations: [360, 420, 500, 500, 500, 900] },
      failed: { row: 5, durations: [260, 280, 320, 360, 420, 480, 620, 1800] },
    };
    const state = {
      version: VERSION,
      working: false,
      busyCount: 0,
      lastStatusAt: 0,
      pointer: null,
      dragging: false,
      workStartedAt: 0,
      failedStartedAt: null,
      nextGestureAt: performance.now() + 9000,
      gesture: null,
      animationFrame: null,
      observer: null,
      channel: null,
      onStorage: null,
      onPointerDown: null,
      onPointerUp: null,
      cleanup: null,
    };

    let style = document.getElementById(OVERLAY_STYLE_ID);
    if (!style) {
      style = document.createElement("style");
      style.id = OVERLAY_STYLE_ID;
      (document.head || document.documentElement).appendChild(style);
    }
    style.textContent = `
      [data-testid="codex-avatar"][data-dream-pet-moving="true"] {
        will-change: transform;
        transition: none !important;
        pointer-events: none !important;
        transform: translate3d(var(--dream-pet-translate-x, 0px), 0, 0)
          scaleX(var(--dream-pet-scale-x, 1)) !important;
        transform-origin: center center;
      }
      [data-testid="codex-avatar"][data-dream-pet-owned="true"] {
        background-position: var(--dream-pet-frame-x) var(--dream-pet-frame-y) !important;
      }
    `;

    const avatarNodes = () => ({
      button: document.querySelector('[data-testid="avatar-mascot-button"]'),
      avatar: document.querySelector('[data-testid="codex-avatar"]'),
    });
    const stopMoving = () => {
      const { button, avatar } = avatarNodes();
      button?.removeAttribute("data-dream-pet-moving");
      avatar?.removeAttribute("data-dream-pet-moving");
      avatar?.style.removeProperty("--dream-pet-translate-x");
      avatar?.style.removeProperty("--dream-pet-scale-x");
    };
    const releaseAvatar = () => {
      const { avatar } = avatarNodes();
      stopMoving();
      avatar?.removeAttribute("data-dream-pet-owned");
      avatar?.style.removeProperty("--dream-pet-frame-x");
      avatar?.style.removeProperty("--dream-pet-frame-y");
    };
    const showFrame = (avatar, row, column) => {
      const position = framePosition(row, column);
      avatar.dataset.dreamPetOwned = "true";
      avatar.style.setProperty("--dream-pet-frame-x", position.x);
      avatar.style.setProperty("--dream-pet-frame-y", position.y);
    };
    const animationColumn = (durations, elapsedMs) => {
      const total = durations.reduce((sum, duration) => sum + duration, 0);
      let cursor = elapsedMs % total;
      for (let index = 0; index < durations.length; index += 1) {
        if (cursor < durations[index]) return index;
        cursor -= durations[index];
      }
      return durations.length - 1;
    };
    const playOneShot = (name, now) => {
      const animation = animations[name];
      const elapsed = now - state.gesture.startedAt;
      const total = animation.durations.reduce((sum, duration) => sum + duration, 0);
      if (elapsed >= total) {
        state.gesture = null;
        state.nextGestureAt = now + 10000 + Math.random() * 8000;
        return null;
      }
      return { row: animation.row, column: animationColumn(animation.durations, elapsed) };
    };
    const chooseGesture = (now) => {
      const choices = ["wave", "ponder"];
      state.gesture = { name: choices[Math.floor(Math.random() * choices.length)], startedAt: now };
    };
    const readStoredStatus = () => {
      try {
        const value = JSON.parse(localStorage.getItem(STORAGE_KEY) || "null");
        if (value?.type === "status" && Date.now() - value.timestamp < 10000) {
          state.working = Boolean(value.working);
          state.busyCount = Number(value.busyCount) || 0;
          state.lastStatusAt = value.timestamp;
          if (state.working) state.workStartedAt = performance.now();
        }
      } catch {}
    };
    const onMessage = (payload) => {
      if (!payload || typeof payload !== "object") return;
      if (payload.type === "status") {
        const wasWorking = state.working;
        state.working = Boolean(payload.working);
        state.busyCount = Number(payload.busyCount) || 0;
        state.lastStatusAt = Number(payload.timestamp) || Date.now();
        if (state.working && !wasWorking) state.workStartedAt = performance.now();
      } else if (payload.type === "pointer") {
        state.pointer = {
          x: Number(payload.screenX),
          y: Number(payload.screenY),
          timestamp: Number(payload.timestamp) || Date.now(),
        };
      }
    };
    if (typeof BroadcastChannel === "function") {
      state.channel = new BroadcastChannel(CHANNEL_NAME);
      state.channel.addEventListener("message", (event) => onMessage(event.data));
    }
    state.onStorage = (event) => {
      if (event.key !== STORAGE_KEY || !event.newValue) return;
      try { onMessage(JSON.parse(event.newValue)); } catch {}
    };
    window.addEventListener("storage", state.onStorage);
    readStoredStatus();

    state.onPointerDown = () => {
      state.dragging = true;
      releaseAvatar();
    };
    state.onPointerUp = () => {
      state.dragging = false;
      state.workStartedAt = performance.now();
    };
    document.addEventListener?.("pointerdown", state.onPointerDown, true);
    document.addEventListener?.("pointerup", state.onPointerUp, true);
    document.addEventListener?.("pointercancel", state.onPointerUp, true);

    const tick = (now) => {
      const { button, avatar } = avatarNodes();
      if (!button || !avatar) {
        state.animationFrame = requestAnimationFrame(tick);
        return;
      }
      const nativeState = avatar.dataset.avatarState || "idle";
      const customFailed = !state.dragging && nativeState === "failed";
      const nativeOwnsAnimation = state.dragging || !["idle", "running", "failed"].includes(nativeState);
      const shouldRun = !nativeOwnsAnimation && (state.working || nativeState === "running");

      if (customFailed) {
        state.gesture = null;
        stopMoving();
        if (state.failedStartedAt === null) state.failedStartedAt = now;
        const failed = animations.failed;
        const elapsed = now - state.failedStartedAt;
        const total = failed.durations.reduce((sum, duration) => sum + duration, 0);
        const column = elapsed >= total
          ? failed.durations.length - 1
          : animationColumn(failed.durations, elapsed);
        showFrame(avatar, failed.row, column);
      } else if (nativeOwnsAnimation) {
        state.failedStartedAt = null;
        state.gesture = null;
        releaseAvatar();
      } else if (shouldRun) {
        state.failedStartedAt = null;
        state.gesture = null;
        const buttonRect = button.getBoundingClientRect();
        const avatarRect = avatar.getBoundingClientRect();
        const viewportWidths = [
          innerWidth,
          document.documentElement?.clientWidth,
          document.body?.clientWidth,
        ].filter((value) => Number.isFinite(value) && value > 0);
        const viewportWidth = viewportWidths.length
          ? Math.min(...viewportWidths)
          : Math.max(1, avatarRect.width || buttonRect.width);
        const safeInset = 26;
        const visualWidth = Math.max(1, avatarRect.width || buttonRect.width);
        const left = Math.min(safeInset, Math.max(0, (viewportWidth - visualWidth) / 2));
        const right = Math.max(left, viewportWidth - visualWidth - safeInset);
        const span = Math.max(1, right - left);
        const distance = Math.max(0, now - state.workStartedAt) * 0.095;
        const phase = distance % (span * 2);
        const movingRight = phase <= span;
        const targetX = movingRight ? left + phase : right - (phase - span);
        const translateX = Math.min(right, Math.max(left, targetX)) - buttonRect.x;
        button.dataset.dreamPetMoving = "true";
        avatar.dataset.dreamPetMoving = "true";
        avatar.style.setProperty("--dream-pet-translate-x", `${translateX}px`);
        avatar.style.setProperty("--dream-pet-scale-x", movingRight ? "1" : "-1");
        const frame = Math.floor((now - state.workStartedAt) / 120) % 8;
        showFrame(avatar, 1, frame);
      } else {
        state.failedStartedAt = null;
        stopMoving();
        const pointerFresh = state.pointer && Date.now() - state.pointer.timestamp < 1200;
        if (pointerFresh) {
          const rect = avatar.getBoundingClientRect();
          const centerX = window.screenX + rect.x + rect.width / 2;
          const centerY = window.screenY + rect.y + rect.height / 2;
          const dx = state.pointer.x - centerX;
          const dy = state.pointer.y - centerY;
          const distance = Math.hypot(dx, dy);
          if (distance >= 54) {
            const degrees = (Math.atan2(dy, dx) * 180 / Math.PI + 90 + 360) % 360;
            const index = Math.round(degrees / 22.5) % 16;
            showFrame(avatar, index < 8 ? 9 : 10, index < 8 ? index : index - 8);
            state.gesture = null;
          } else {
            releaseAvatar();
          }
        } else {
          if (!state.gesture && now >= state.nextGestureAt) chooseGesture(now);
          const frame = state.gesture ? playOneShot(state.gesture.name, now) : null;
          if (frame) showFrame(avatar, frame.row, frame.column);
          else releaseAvatar();
        }
      }
      state.animationFrame = requestAnimationFrame(tick);
    };

    state.observer = new MutationObserver(() => {
      if (!document.querySelector('[data-testid="codex-avatar"]')) releaseAvatar();
    });
    state.observer.observe(document.documentElement, { childList: true, subtree: true });
    state.cleanup = () => {
      if (state.animationFrame) cancelAnimationFrame(state.animationFrame);
      state.observer?.disconnect();
      state.channel?.close();
      window.removeEventListener("storage", state.onStorage);
      document.removeEventListener?.("pointerdown", state.onPointerDown, true);
      document.removeEventListener?.("pointerup", state.onPointerUp, true);
      document.removeEventListener?.("pointercancel", state.onPointerUp, true);
      releaseAvatar();
      document.getElementById(OVERLAY_STYLE_ID)?.remove();
      delete window[OVERLAY_STATE_KEY];
      return true;
    };
    window[OVERLAY_STATE_KEY] = state;
    state.animationFrame = requestAnimationFrame(tick);
    return { installed: true, version: VERSION, kind: "avatar-overlay" };
  }

  window[BRIDGE_STATE_KEY]?.cleanup?.();
  const channel = typeof BroadcastChannel === "function" ? new BroadcastChannel(CHANNEL_NAME) : null;
  let lastBusyCount = null;
  let lastPointerSentAt = 0;
  const publish = (payload) => {
    channel?.postMessage(payload);
    if (payload.type === "status") {
      try { localStorage.setItem(STORAGE_KEY, JSON.stringify(payload)); } catch {}
    }
  };
  const syncWorkState = (force = false) => {
    const sidebar = document.querySelector("aside.app-shell-left-panel");
    const busyRows = sidebar?.querySelectorAll
      ? [...sidebar.querySelectorAll(".animate-spin")].filter((spinner) =>
        spinner.closest("button,[role='button'],a") && getComputedStyle(spinner).display !== "none")
      : [];
    const busyCount = busyRows.length;
    if (!force && busyCount === lastBusyCount) return;
    lastBusyCount = busyCount;
    publish({ type: "status", working: busyCount > 0, busyCount, timestamp: Date.now() });
  };
  const onPointerMove = (event) => {
    const now = performance.now();
    if (now - lastPointerSentAt < 33) return;
    lastPointerSentAt = now;
    publish({
      type: "pointer",
      screenX: Number.isFinite(event.screenX) ? event.screenX : window.screenX + event.clientX,
      screenY: Number.isFinite(event.screenY) ? event.screenY : window.screenY + event.clientY,
      timestamp: Date.now(),
    });
  };
  document.addEventListener?.("pointermove", onPointerMove, { passive: true });
  const timer = setInterval(() => syncWorkState(true), 1000);
  const state = {
    version: VERSION,
    kind: "main",
    get busyCount() { return lastBusyCount ?? 0; },
    cleanup: () => {
      clearInterval(timer);
      document.removeEventListener?.("pointermove", onPointerMove);
      publish({ type: "status", working: false, busyCount: 0, timestamp: Date.now() });
      channel?.close();
      delete window[BRIDGE_STATE_KEY];
      return true;
    },
  };
  window[BRIDGE_STATE_KEY] = state;
  syncWorkState(true);
  return { installed: true, version: VERSION, kind: "main" };
})();
