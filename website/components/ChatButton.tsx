"use client";

import { useEffect, useId, useRef, useState } from "react";
import { trackAttrs } from "@/lib/analytics";
import { CONTACT_EMAIL } from "@/lib/site";

// Click-to-load support chat (Chatwoot, self-hosted at chatwoot.ericdahl.dev). Nothing from the chat server loads, and
// nothing is stored in the browser, until the visitor presses the button: no prefetch, no preconnect. Chatwoot then
// keeps a visitor ID in a cookie and local storage, which the privacy page says. The website token is public by design.
// The CSP in nginx.conf allows the chat host for script-src, frame-src, connect-src and img-src.
export const CHATWOOT_BASE_URL = "https://chatwoot.ericdahl.dev";
export const CHATWOOT_WEBSITE_TOKEN = "2Esh9of1eCKs1kXoMVVfy1oY";
// If the widget has not said it is ready by then (blocked, offline, server down), offer email instead.
const READY_TIMEOUT_MS = 15000;

type ChatwootWindow = Window & {
  chatwootSettings?: Record<string, unknown>;
  chatwootSDK?: { run: (options: { websiteToken: string; baseUrl: string }) => void };
  $chatwoot?: { toggle: (state?: "open" | "close") => void };
};

type State = "idle" | "loading" | "open" | "failed";

export function ChatButton() {
  const [state, setState] = useState<State>("idle");
  const cleanup = useRef<() => void>(() => {});
  const noteId = useId();

  useEffect(() => () => cleanup.current(), []);

  function start() {
    const w = window as ChatwootWindow;
    // Already loaded (a second click): just open it again.
    if (w.$chatwoot) {
      w.$chatwoot.toggle("open");
      setState("open");
      return;
    }
    if (state === "loading") return;
    setState("loading");

    const fail = () => {
      cleanup.current();
      setState("failed");
    };
    const onReady = () => {
      cleanup.current();
      w.$chatwoot?.toggle("open");
      setState("open");
    };
    const timer = window.setTimeout(fail, READY_TIMEOUT_MS);
    window.addEventListener("chatwoot:ready", onReady);
    window.addEventListener("chatwoot:error", fail);
    cleanup.current = () => {
      window.clearTimeout(timer);
      window.removeEventListener("chatwoot:ready", onReady);
      window.removeEventListener("chatwoot:error", fail);
    };

    w.chatwootSettings = { hideMessageBubble: false, position: "right", type: "standard" };
    const script = document.createElement("script");
    script.src = `${CHATWOOT_BASE_URL}/packs/js/sdk.js`;
    script.async = true;
    script.onload = () => {
      try {
        w.chatwootSDK?.run({ websiteToken: CHATWOOT_WEBSITE_TOKEN, baseUrl: CHATWOOT_BASE_URL });
        if (!w.chatwootSDK) fail();
      } catch {
        fail();
      }
    };
    script.onerror = () => {
      script.remove();
      fail();
    };
    document.body.appendChild(script);
  }

  return (
    <div className="chat">
      <button
        type="button"
        className="chat-button"
        onClick={start}
        aria-busy={state === "loading"}
        aria-describedby={noteId}
        {...trackAttrs("chat_opened")}
      >
        {state === "loading" ? "Loading chat..." : "Chat with us"}
      </button>
      <p id={noteId} className="chat-note" aria-live="polite">
        {state === "failed" ? (
          <>
            The chat didn&apos;t load. Email{" "}
            <a href={`mailto:${CONTACT_EMAIL}`} {...trackAttrs("contact_email_clicked")}>
              {CONTACT_EMAIL}
            </a>{" "}
            instead.
          </>
        ) : (
          <>
            The chat loads only when you press the button. See the <a href="/privacy">privacy policy</a>.
          </>
        )}
      </p>
    </div>
  );
}
