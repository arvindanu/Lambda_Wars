#!/usr/bin/env bash
# Creates a release keystore for signing Lambda Wars and prints the values to store as GitHub secrets.
#
#   ./tools/make_keystore.sh [output-file] [alias]
#
# Keep the generated file and passwords somewhere safe. If you lose the key you can never publish
# updates to the same Google Play listing (unless you use Play App Signing, which is recommended).
set -euo pipefail

OUT="${1:-lambda-wars-release.keystore}"
ALIAS="${2:-lambdawars}"

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found. Install a JDK (17 or newer) first." >&2
  exit 1
fi
if [ -e "$OUT" ]; then
  echo "Refusing to overwrite existing file: $OUT" >&2
  exit 1
fi

read -r -s -p "Choose a keystore password (min 6 chars, used for the store AND the key): " PASS
echo
read -r -s -p "Repeat password: " PASS2
echo
if [ "$PASS" != "$PASS2" ]; then
  echo "Passwords do not match." >&2
  exit 1
fi
if [ "${#PASS}" -lt 6 ]; then
  echo "Password must be at least 6 characters." >&2
  exit 1
fi

read -r -p "Your name or studio (for the certificate) [TermorganWorks]: " CN
CN="${CN:-TermorganWorks}"

# PKCS12 keystores use one password for both the store and the key, which is what Godot expects.
keytool -genkeypair -v \
  -keystore "$OUT" \
  -storetype PKCS12 \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=$CN, OU=Games, O=$CN, C=US"

if base64 --help 2>&1 | grep -q -- "-w"; then
  B64="$(base64 -w 0 "$OUT")"
else
  B64="$(base64 < "$OUT" | tr -d '\n')"
fi

echo
echo "Keystore created: $OUT"
echo
echo "Add these repository secrets (Settings > Secrets and variables > Actions):"
echo "  ANDROID_KEYSTORE_BASE64    = (the long base64 string printed below)"
echo "  ANDROID_KEYSTORE_ALIAS     = $ALIAS"
echo "  ANDROID_KEYSTORE_PASSWORD  = (the password you just typed)"
echo
echo "----- ANDROID_KEYSTORE_BASE64 -----"
echo "$B64"
echo "-----------------------------------"
