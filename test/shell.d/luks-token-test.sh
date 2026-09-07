#!/bin/bash
# R-SEC-4: prove cryptsetup preserves the non-secret per-slot ownership token.
set -euo pipefail

if ! command -v cryptsetup >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "SKIP luks-token-test.sh: cryptsetup and jq are required"
  exit 0
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
image="$scratch/luks2.img"
key="$scratch/key"
token="$scratch/token.json"
truncate -s 32M "$image"
printf %s synthetic-issue-107-passphrase >"$key"
chmod 0600 "$key"

cryptsetup luksFormat --type luks2 --batch-mode --pbkdf pbkdf2 \
  --pbkdf-force-iterations 1000 --key-file "$key" "$image"
device_uuid="$(cryptsetup luksUUID "$image")"
jq -n --arg device "$device_uuid" '{
  type:"omarchy-kids", keyslots:["0"], account:"kid-ada",
  transaction:"11111111-1111-4111-8111-111111111111",
  owner:"22222222-2222-4222-8222-222222222222",
  device_uuid:$device, slot:0, schema:1
}' >"$token"
cryptsetup token import --token-id 0 --json-file "$token" "$image"
exported="$(cryptsetup token export --token-id 0 "$image")"
metadata_token="$(cryptsetup luksDump --dump-json-metadata "$image" | jq -cS '.tokens["0"]')"
jq -e --arg device "$device_uuid" '
  .type == "omarchy-kids" and .keyslots == ["0"] and
  .account == "kid-ada" and .device_uuid == $device and .slot == 0 and
  .schema == 1 and .transaction == "11111111-1111-4111-8111-111111111111" and
  .owner == "22222222-2222-4222-8222-222222222222"
' >/dev/null <<<"$exported"
[[ "$(jq -cS . <<<"$exported")" == "$metadata_token" ]]
printf 'device_uuid=%s\n' "$device_uuid"
printf 'exported_token=%s\n' "$(jq -cS . <<<"$exported")"
printf 'metadata_token=%s\n' "$metadata_token"
echo "luks-token-test RESULT: PASS ($(cryptsetup --version))"
