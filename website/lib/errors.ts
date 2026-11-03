// Errors in the visitor's browser go to GlitchTip (errors.ericdahl.dev, run on the developer's own server), project
// showrecorder-web (ADR 0007, #1026). A few lines inline, like the PostHog loader, instead of an SDK: only uncaught errors
// and unhandled promise rejections from this site's own scripts, at most MAX_REPORTS_PER_PAGE per page, with the page
// address but never its query string. Sent as text/plain so the browser needs no CORS preflight; GlitchTip accepts it.
// The DSN is GlitchTip's public key, meant to be in page source; it can only send events.

export const GLITCHTIP_HOST = "https://errors.ericdahl.dev";
export const GLITCHTIP_DSN = `https://8c584ae34c414187b3db70abb76e7e8a@errors.ericdahl.dev/13`;
export const MAX_REPORTS_PER_PAGE = 5;

export function glitchtipStoreUrl(dsn: string = GLITCHTIP_DSN): string {
  const url = new URL(dsn);
  const project = url.pathname.replace(/^\//, "");
  return `${url.protocol}//${url.host}/api/${project}/store/?sentry_key=${url.username}&sentry_version=7`;
}

export function errorReportingScript(): string {
  return `(function () {
  var url = ${JSON.stringify(glitchtipStoreUrl())};
  var sent = 0;
  function id() {
    var s = "";
    for (var i = 0; i < 32; i++) s += Math.floor(Math.random() * 16).toString(16);
    return s;
  }
  function send(type, value, stack) {
    if (sent >= ${MAX_REPORTS_PER_PAGE}) return;
    sent++;
    var loc = window.location;
    var body = JSON.stringify({
      event_id: id(),
      platform: "javascript",
      level: "error",
      logger: "showrecorder.app",
      exception: { values: [{ type: String(type || "Error").slice(0, 100), value: String(value).slice(0, 500) }] },
      request: { url: loc.origin + loc.pathname },
      tags: { host: loc.host },
      extra: { stack: String(stack || "").slice(0, 4000) }
    });
    try {
      if (navigator.sendBeacon && navigator.sendBeacon(url, new Blob([body], { type: "text/plain" }))) return;
      fetch(url, { method: "POST", body: body, keepalive: true, mode: "no-cors", headers: { "Content-Type": "text/plain" } });
    } catch (e) {}
  }
  window.addEventListener("error", function (e) {
    if (!e || !e.filename || e.filename.indexOf(window.location.origin + "/") !== 0) return;
    var err = e.error;
    send(err && err.name, (err && err.message) || e.message, err && err.stack);
  });
  window.addEventListener("unhandledrejection", function (e) {
    var r = e && e.reason;
    send((r && r.name) || "UnhandledRejection", (r && r.message) || r, r && r.stack);
  });
})();`;
}
