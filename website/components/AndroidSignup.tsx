"use client";

import { useEffect, useRef } from "react";
import { BUTTONDOWN_ACTION, SIGNUP_INTEREST } from "@/lib/androidSignup";

type PostHog = { capture: (event: string) => void };

// Counts form views and submits as two named events (autocapture is off; see lib/analytics.ts).
// The form itself needs no JavaScript.
function track(event: string) {
  (window as unknown as { posthog?: PostHog }).posthog?.capture(event);
}

export function AndroidSignup() {
  const form = useRef<HTMLFormElement>(null);

  useEffect(() => {
    const el = form.current;
    if (!el || !("IntersectionObserver" in window)) return;
    const seen = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        track("android_signup_view");
        seen.disconnect();
      }
    });
    seen.observe(el);
    return () => seen.disconnect();
  }, []);

  return (
    <form
      ref={form}
      className="signup"
      action={BUTTONDOWN_ACTION}
      method="post"
      onSubmit={() => track("android_signup_submit")}
    >
      <label htmlFor="android-email">Email</label>
      <div className="signup-row">
        <input
          id="android-email"
          type="email"
          name="email"
          required
          autoComplete="email"
          inputMode="email"
          placeholder="you@example.com"
        />
        <input type="hidden" name="metadata__interest" value={SIGNUP_INTEREST} />
        <input type="hidden" name="embed" value="1" />
        <button type="submit">Notify me</button>
      </div>
      <p className="signup-note">
        One email from Eric Dahl, the developer, if ShowRecorder comes to Android. You&apos;ll confirm your
        address first, and every email has a one-click unsubscribe. See the <a href="/privacy">privacy policy</a>.
      </p>
    </form>
  );
}
