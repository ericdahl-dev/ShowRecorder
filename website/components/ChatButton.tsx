"use client";

import { useId } from "react";
import { trackAttrs } from "@/lib/analytics";
import { useChat } from "@/lib/chat";
import { CONTACT_EMAIL } from "@/lib/site";

// "Chat with us" on /support. It shares the click-to-load chat with the bubble on every page (lib/chat.ts): nothing
// from the chat server loads until one of them is pressed, and the SDK is injected only once.
export function ChatButton() {
  const chat = useChat("support");
  const noteId = useId();
  const loading = chat.status === "loading" && chat.mine;

  return (
    <div className="chat">
      <button
        type="button"
        className="chat-button"
        onClick={chat.open}
        aria-busy={loading}
        aria-describedby={noteId}
        {...trackAttrs("chat_opened")}
      >
        {loading ? "Loading chat..." : "Chat with us"}
      </button>
      <p id={noteId} className="chat-note" aria-live="polite">
        {chat.status === "failed" && chat.mine ? (
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
