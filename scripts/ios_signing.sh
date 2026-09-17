#!/usr/bin/env bash
# One-time signing setup on the build Mac, driven entirely by the App
# Store Connect API key: a dedicated build keychain, an Apple Distribution
# certificate issued for that keychain's key, and an App Store provisioning
# profile for com.commutescout.drive. Idempotent; safe to rerun.
set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"
ASC_KEY_ID="${ASC_KEY_ID:-N9LBMSST5A}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-ff12bb27-b0e6-4510-a862-0e199730f09e}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
DIR="$HOME/.appstoreconnect/cs-build"
KC="$HOME/Library/Keychains/cs-build.keychain-db"
PROFILE_NAME="CommuteScout Drive AppStore"
BUNDLE_ID="com.commutescout.drive"
mkdir -p "$DIR" && chmod 700 "$DIR"

if [ ! -f "$DIR/keychain.pw" ]; then
  openssl rand -hex 24 > "$DIR/keychain.pw"; chmod 600 "$DIR/keychain.pw"
fi
PW="$(cat "$DIR/keychain.pw")"

if [ ! -f "$KC" ]; then
  security create-keychain -p "$PW" "$KC"
  security set-keychain-settings "$KC"          # never auto-lock
fi
security unlock-keychain -p "$PW" "$KC"
# Keep the login keychain first so nothing else changes; add ours to the search list once.
if ! security list-keychains -d user | grep -q cs-build; then
  security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
fi

if [ ! -f "$DIR/dist.key" ]; then
  openssl genrsa -out "$DIR/dist.key" 2048 2>/dev/null
  openssl req -new -key "$DIR/dist.key" -out "$DIR/dist.csr" -subj "/CN=CommuteScout Build/O=Nicholas Glazkov/C=US"
fi

python3 - "$DIR" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH" "$PROFILE_NAME" "$BUNDLE_ID" <<'PY'
import sys, time, json, base64, subprocess, os
d, kid, iss, kpath, pname, bid = sys.argv[1:]
sys.path.insert(0, os.path.expanduser("~/src/asc-setup/venv/lib/python3.13/site-packages"))
import glob
for p in glob.glob(os.path.expanduser("~/src/asc-setup/venv/lib/python3*/site-packages")): sys.path.insert(0, p)
import jwt, requests
tok = jwt.encode({"iss": iss, "iat": int(time.time()), "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
                 open(kpath).read(), algorithm="ES256", headers={"kid": kid})
H = {"Authorization": "Bearer " + tok, "Content-Type": "application/json"}
B = "https://api.appstoreconnect.apple.com/v1"
state = json.load(open(f"{d}/state.json")) if os.path.exists(f"{d}/state.json") else {}
if "cert_id" not in state:
    csr = open(f"{d}/dist.csr").read()
    r = requests.post(B + "/certificates", headers=H, json={"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION", "csrContent": csr}}})
    r.raise_for_status()
    c = r.json()["data"]
    open(f"{d}/dist.cer", "wb").write(base64.b64decode(c["attributes"]["certificateContent"]))
    state["cert_id"] = c["id"]; json.dump(state, open(f"{d}/state.json", "w"))
    print("certificate", c["id"], c["attributes"]["name"])
bundle = requests.get(B + f"/bundleIds?filter[identifier]={bid}", headers=H).json()["data"][0]["id"]
if "profile_id" not in state:
    r = requests.get(B + f"/profiles?filter[name]={requests.utils.quote(pname)}", headers=H).json()
    for p in r.get("data", []):
        requests.delete(B + f"/profiles/{p['id']}", headers=H)
    r = requests.post(B + "/profiles", headers=H, json={"data": {"type": "profiles", "attributes": {
        "name": pname, "profileType": "IOS_APP_STORE"}, "relationships": {
        "bundleId": {"data": {"type": "bundleIds", "id": bundle}},
        "certificates": {"data": [{"type": "certificates", "id": state["cert_id"]}]}}}})
    r.raise_for_status()
    p = r.json()["data"]
    open(f"{d}/appstore.mobileprovision", "wb").write(base64.b64decode(p["attributes"]["profileContent"]))
    state["profile_id"] = p["id"]; state["profile_uuid"] = p["attributes"]["uuid"]
    json.dump(state, open(f"{d}/state.json", "w"))
    print("profile", p["id"], p["attributes"]["uuid"])
print("state", state)
PY

# Apple's WWDR intermediate completes the chain for codesign.
[ -f "$DIR/AppleWWDRCAG3.cer" ] || curl -sS -o "$DIR/AppleWWDRCAG3.cer" https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security import "$DIR/AppleWWDRCAG3.cer" -k "$KC" -T /usr/bin/codesign >/dev/null 2>&1 || true
# security(1) only takes the key as PKCS#12, so bundle key and certificate.
if [ ! -f "$DIR/dist.p12" ]; then
  openssl x509 -in "$DIR/dist.cer" -inform DER -out "$DIR/dist.pem"
  openssl pkcs12 -export -inkey "$DIR/dist.key" -in "$DIR/dist.pem" -out "$DIR/dist.p12" -passout pass:cs -name "CommuteScout Build"
fi
security import "$DIR/dist.p12" -k "$KC" -P cs -A -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1 || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
security find-identity -v -p codesigning "$KC"

UUID="$(python3 -c "import json;print(json.load(open('$DIR/state.json'))['profile_uuid'])")"
for P in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$P"; cp "$DIR/appstore.mobileprovision" "$P/$UUID.mobileprovision"
done
echo "profile installed as $UUID"
