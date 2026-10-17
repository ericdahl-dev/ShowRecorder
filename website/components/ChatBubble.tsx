"use client";

import { usePathname } from "next/navigation";
import { useState } from "react";
import { trackAttrs } from "@/lib/analytics";
import { bubbleVisible, useChat } from "@/lib/chat";
import { CONTACT_EMAIL } from "@/lib/site";

// The chat launcher in the bottom-right corner of every page (rendered once by app/layout.tsx). It is our own static
// button, not Chatwoot's: nothing from the chat server loads, and nothing is stored, until it is pressed (lib/chat.ts).
// It sits where Chatwoot's launcher goes (64 px, 20 px from the right and bottom; smaller on narrow screens), and once the chat has loaded, from
// here or from "Chat with us" on /support, it hides itself and Chatwoot's launcher takes over opening and closing.
export function ChatBubble() {
  const chat = useChat("bubble");
  const pathname = usePathname();
  const [dismissed, setDismissed] = useState(false);
  if (chat.status === "loaded") return null;
  // Not on /support, which has its own "Chat with us" button.
  if (!bubbleVisible(pathname)) return null;

  const loading = chat.status === "loading" && chat.mine;
  const failed = chat.status === "failed" && chat.mine && !dismissed;

  return (
    <div className="chat-bubble">
      <div className="chat-bubble-live" aria-live="polite">
        {loading && <span className="sr-only">Loading chat...</span>}
        {failed && (
          <div className="chat-bubble-note">
            <p>
              The chat didn&apos;t load. Email{" "}
              <a href={`mailto:${CONTACT_EMAIL}`} {...trackAttrs("contact_email_clicked")}>
                {CONTACT_EMAIL}
              </a>{" "}
              instead.
            </p>
            <button type="button" className="chat-bubble-dismiss" aria-label="Dismiss" onClick={() => setDismissed(true)}>
              <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
                <path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" strokeWidth="2" strokeLinecap="round" fill="none" />
              </svg>
            </button>
          </div>
        )}
      </div>
      <button
        type="button"
        className="chat-bubble-button"
        aria-label="Chat with ShowRecorder support"
        aria-busy={loading}
        onClick={() => {
          setDismissed(false);
          chat.open();
        }}
        {...trackAttrs("chat_opened")}
      >
        {loading ? (
          <svg className="chat-bubble-spinner" viewBox="0 0 24 24" width="28" height="28" aria-hidden="true">
            <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.3" strokeWidth="2.5" fill="none" />
            <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" fill="none" />
          </svg>
        ) : (
          <svg viewBox="0 0 24 24" width="28" height="28" aria-hidden="true">
            <path
              d="M12 3.5c-5 0-9 3.4-9 7.6 0 2.3 1.2 4.4 3.1 5.8L5.4 20.5l4.2-2.2c.8.2 1.6.3 2.4.3 5 0 9-3.4 9-7.5S17 3.5 12 3.5z"
              fill="currentColor"
            />
          </svg>
        )}
      </button>
    </div>
  );
}
