import { useSyncExternalStore } from "react";

// Click-to-load support chat (Chatwoot, self-hosted at chatwoot.ericdahl.dev), shared by the chat bubble on every page
// (components/ChatBubble.tsx) and the "Chat with us" button on /support (components/ChatButton.tsx). Nothing from the
// chat server loads, and nothing is stored in the browser, until the visitor presses one of them: no prefetch, no
// preconnect, no preload. Chatwoot then keeps a visitor ID in a cookie and local storage, which the privacy page says.
// The website token is public by design. The CSP in nginx.conf allows the chat host for script-src, frame-src,
// connect-src and img-src.
//
// One loader for the whole page: the SDK script is injected at most once, whichever control is pressed first. After
// that, either control just opens the chat. Chatwoot shows its own launcher (hideMessageBubble: false) in the same
// spot as our bubble, which hides itself once the chat has loaded, so there is only ever one launcher.
export const CHATWOOT_BASE_URL = "https://chatwoot.ericdahl.dev";
export const CHATWOOT_WEBSITE_TOKEN = "2Esh9of1eCKs1kXoMVVfy1oY";
export const CHATWOOT_SETTINGS = { hideMessageBubble: false, position: "right", type: "standard" } as const;
// If the widget has not said it is ready by then (blocked, offline, server down), offer email instead.
export const READY_TIMEOUT_MS = 15000;

// Which control started the last load, so only that one shows the email fallback if it fails.
export type ChatSource = "bubble" | "support";
export type ChatStatus = "idle" | "loading" | "loaded" | "failed";
export type ChatState = { status: ChatStatus; source: ChatSource | null };

type ChatwootWindow = Window & {
  chatwootSettings?: Record<string, unknown>;
  chatwootSDK?: { run: (options: { websiteToken: string; baseUrl: string }) => void };
  $chatwoot?: { toggle: (state?: "open" | "close") => void };
};

const IDLE: ChatState = { status: "idle", source: null };
let state: ChatState = IDLE;
const listeners = new Set<() => void>();
let script: HTMLScriptElement | null = null;
let timer: number | undefined;
let listening = false;

function set(next: ChatState) {
  state = next;
  for (const listener of listeners) listener();
}

function chatwoot(): ChatwootWindow {
  return window as ChatwootWindow;
}

function onReady() {
  window.clearTimeout(timer);
  const waiting = state.status === "loading";
  set({ ...state, status: "loaded" });
  // Open it for the click that asked. A widget that turns up after the timeout just becomes available.
  if (waiting) chatwoot().$chatwoot?.toggle("open");
}

function onFail() {
  if (state.status === "loaded") return;
  window.clearTimeout(timer);
  set({ ...state, status: "failed" });
}

/** Loads the chat on the first call (from a click) and opens it; later calls just open it. */
export function openChat(source: ChatSource): void {
  if (state.status === "loaded") {
    chatwoot().$chatwoot?.toggle("open");
    return;
  }
  if (state.status === "loading") return;
  set({ status: "loading", source });

  if (!listening) {
    window.addEventListener("chatwoot:ready", onReady);
    window.addEventListener("chatwoot:error", onFail);
    listening = true;
  }
  timer = window.setTimeout(onFail, READY_TIMEOUT_MS);
  // A try that timed out leaves its script on the page: wait for it again rather than inject a second one.
  if (script) return;

  const w = chatwoot();
  w.chatwootSettings = { ...CHATWOOT_SETTINGS };
  script = document.createElement("script");
  script.src = `${CHATWOOT_BASE_URL}/packs/js/sdk.js`;
  script.async = true;
  script.onload = () => {
    try {
      w.chatwootSDK?.run({ websiteToken: CHATWOOT_WEBSITE_TOKEN, baseUrl: CHATWOOT_BASE_URL });
      if (!w.chatwootSDK) onFail();
    } catch {
      onFail();
    }
  };
  script.onerror = () => {
    // Blocked or offline: drop it so a later click can try again.
    script?.remove();
    script = null;
    onFail();
  };
  document.body.appendChild(script);
}

export function subscribeChat(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function chatState(): ChatState {
  return state;
}

/** The shared chat state for a component, plus openChat bound to that component. */
export function useChat(source: ChatSource): ChatState & { open: () => void; mine: boolean } {
  const current = useSyncExternalStore(subscribeChat, chatState, () => IDLE);
  return { ...current, open: () => openChat(source), mine: current.source === source };
}
