#!/usr/bin/env python3
"""Gets the App Store provisioning profile for the app, for the release workflow.

Uses the App Store Connect API with the same key the upload uses (Python standard library plus the
`openssl` tool, which is on every Mac). It looks up the bundle ID and the Apple Distribution certificate
(by serial number), reuses the CI profile if it is still valid for that certificate, otherwise makes a new
one, and installs it where Xcode looks.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID, CERT_SERIAL (hex, from the certificate in
the keychain), PROFILE_NAME. Prints "name=<profile name>" and "uuid=<profile uuid>" lines, for $GITHUB_OUTPUT.
Never prints the key or a token.
"""
import base64, json, os, plistlib, subprocess, sys, time, urllib.error, urllib.parse, urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """An ECDSA DER signature as the 64 raw bytes (r then s) a JWT wants."""
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        assert der[i] == 0x02
        n = der[i + 1]
        parts.append(int.from_bytes(der[i + 2 : i + 2 + n], "big").to_bytes(32, "big"))
        i += 2 + n
    return b"".join(parts)


def token() -> str:
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"}
    signing_input = b64url(json.dumps(header).encode()) + "." + b64url(json.dumps(claims).encode())
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
        input=signing_input.encode(), capture_output=True, check=True,
    ).stdout
    return signing_input + "." + b64url(der_to_raw(der))


def call(method: str, path: str, body=None, query=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    request = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None)
    request.add_header("Authorization", "Bearer " + token())
    if body:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        sys.exit(f"App Store Connect said {error.code} for {method} {path}: {error.read().decode()[:600]}")


def main():
    bundle_id = os.environ["BUNDLE_ID"]
    serial = os.environ["CERT_SERIAL"].upper().lstrip("0")
    name = os.environ["PROFILE_NAME"]

    bundles = call("GET", "/bundleIds", query={"filter[identifier]": bundle_id, "limit": 200})["data"]
    bundle = next((b for b in bundles if b["attributes"]["identifier"] == bundle_id), None) or sys.exit(f"No bundle ID {bundle_id}.")

    certs = call("GET", "/certificates", query={"filter[certificateType]": "DISTRIBUTION", "limit": 200})["data"]
    cert = next((c for c in certs if c["attributes"].get("serialNumber", "").upper().lstrip("0") == serial), None)
    if cert is None:
        sys.exit("The Apple Distribution certificate in the keychain isn't one App Store Connect knows (serial mismatch). Was it revoked?")

    profiles = call("GET", "/profiles", query={"filter[name]": name, "filter[profileType]": "IOS_APP_STORE", "include": "certificates", "limit": 50})
    profile = None
    for p in profiles["data"]:
        linked = [c["id"] for c in p["relationships"]["certificates"]["data"]]
        if p["attributes"]["profileState"] == "ACTIVE" and cert["id"] in linked:
            profile = p
            break
    if profile is None and os.environ.get("DRY_RUN"):
        print(f"dry run: would create profile {name} for certificate {cert['id']} and bundle {bundle['id']}")
        return
    if profile is None:
        # Our own CI profile, out of date: replace it. (Matched by exact name, only ever this one.)
        for p in profiles["data"]:
            if p["attributes"]["name"] == name:
                call("DELETE", f"/profiles/{p['id']}")
        profile = call("POST", "/profiles", body={"data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
            },
        }})["data"]

    content = base64.b64decode(profile["attributes"]["profileContent"])
    uuid = profile["attributes"]["uuid"]
    folder = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(folder, exist_ok=True)
    with open(f"{folder}/{uuid}.mobileprovision", "wb") as f:
        f.write(content)
    print(f"name={name}")
    print(f"uuid={uuid}")


if __name__ == "__main__":
    main()
