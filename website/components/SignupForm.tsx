"use client";

import { useEffect, useRef } from "react";
import { BUTTONDOWN_ACTION, DEFAULT_INTEREST, SIGNUP_INTERESTS } from "@/lib/signup";

type PostHog = { capture: (event: string, props?: Record<string, string>) => void };

// Counts form views and submits as two named events (autocapture is off; see lib/analytics.ts).
// The form itself needs no JavaScript.
function track(event: string, props?: Record<string, string>) {
  (window as unknown as { posthog?: PostHog }).posthog?.capture(event, props);
}

export function SignupForm() {
  const form = useRef<HTMLFormElement>(null);

  useEffect(() => {
    const el = form.current;
    if (!el || !("IntersectionObserver" in window)) return;
    const seen = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        track("signup_view");
        seen.disconnect();
      }
    });
    seen.observe(el);
    return () => seen.disconnect();
  }, []);

  return (
    <form
      ref={form}
      id="launch-email"
      className="signup"
      action={BUTTONDOWN_ACTION}
      method="post"
      onSubmit={(e) => {
        const interest = new FormData(e.currentTarget).get("metadata__interest");
        track("signup_submit", { interest: String(interest) });
      }}
    >
      <label htmlFor="signup-email">Not ready to install? Get the launch email.</label>
      <div className="signup-row">
        <input
          id="signup-email"
          type="email"
          name="email"
          required
          autoComplete="email"
          inputMode="email"
          placeholder="you@example.com"
        />
        <input type="hidden" name="embed" value="1" />
        <button type="submit">Email me</button>
      </div>
      <fieldset className="signup-interests">
        <legend>Tell me about</legend>
        {SIGNUP_INTERESTS.map((i) => (
          <label key={i.value}>
            <input
              type="radio"
              name="metadata__interest"
              value={i.value}
              defaultChecked={i.value === DEFAULT_INTEREST}
            />
            {i.label}
          </label>
        ))}
      </fieldset>
      <p className="signup-note">
        At most two emails, from Eric Dahl, the developer. You&apos;ll confirm your address first, and every email
        has a one-click unsubscribe. See the <a href="/privacy">privacy policy</a>.
      </p>
    </form>
  );
}
