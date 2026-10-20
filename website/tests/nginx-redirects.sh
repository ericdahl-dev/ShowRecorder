#!/usr/bin/env bash
# Runs website/nginx.conf in the Dockerfile's nginx image against a tiny static root and checks
# that no redirect leaves the site (#873). Needs Docker. Usage: website/tests/nginx-redirects.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
image="$(sed -n 's/^FROM \(nginx:[^ ]*\).*/\1/p' "$here/Dockerfile")"
root="$(mktemp -d)"
echo privacy >"$root/privacy.html"
echo missing >"$root/404.html"
echo home >"$root/index.html"
name="showrecorder-nginx-test-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -r "$root"' EXIT
docker run -d --name "$name" -p 127.0.0.1::80 \
  -v "$here/nginx.conf:/etc/nginx/conf.d/default.conf:ro" -v "$root:/usr/share/nginx/html:ro" \
  "$image" >/dev/null
port="$(docker port "$name" 80 | head -1 | sed 's/.*://')"
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$port/" && break; sleep 0.1; done

fail=0
# check <path> <expected status> <expected Location, or "" for none>
check() {
  local out status loc
  out="$(curl -s -o /dev/null -D - --path-as-is "http://127.0.0.1:$port$1")"
  status="$(printf '%s' "$out" | head -1 | awk '{print $2}')"
  loc="$(printf '%s' "$out" | sed -n 's/^[Ll]ocation: //p' | tr -d '\r')"
  if [[ "$status" == "$2" && "$loc" == "$3" ]]; then
    echo "ok   $1 -> $status ${loc:-(no location)}"
  else
    echo "FAIL $1 -> $status ${loc:-(no location)}  (want $2 ${3:-(no location)})"
    fail=1
  fi
}
check '/privacy/' 301 '/privacy'
check '/privacy' 200 ''
check '/%5Cexample.com/' 404 ''
check '/%5C%5Cexample.com/' 404 ''
check '//example.com/' 301 '/example.com'
check '/%09/example.com/' 404 ''
exit "$fail"
