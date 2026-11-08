#!/usr/bin/env bash
# One-time setup: create the key that signs your apt repository.
#
#   scripts/make-signing-key.sh "My apt repo"
#
# The key is made in a throwaway GnuPG home (your own keyring is untouched).
# Outputs, in ./keys/:
#   archive-keyring.gpg   public key — commit it, and install it on your machines
#   signing-key.private.asc   PRIVATE — upload as the APT_SIGNING_KEY secret, then delete
set -euo pipefail
source "$(dirname "$0")/lib.sh"

uid="${1:-$LABEL} <apt@invalid>"
out="$REPO_ROOT/keys"
mkdir -p "$out"
[[ -e "$out/signing-key.private.asc" ]] && die "keys/signing-key.private.asc already exists"

GNUPGHOME="$(mktemp -d)"; export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT

# ed25519 signing-only key, no passphrase (CI has to use it unattended), no expiry.
gpg --batch --quiet --passphrase '' --quick-gen-key "$uid" ed25519 sign never
fpr="$(gpg --list-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}')"

gpg --export "$fpr" > "$out/archive-keyring.gpg"
gpg --armor --export "$fpr" > "$out/archive-keyring.asc"
(umask 077; gpg --armor --export-secret-keys "$fpr" > "$out/signing-key.private.asc")

cat <<EOF

Key fingerprint: $fpr

Next:
  gh secret set APT_SIGNING_KEY < keys/signing-key.private.asc
  shred -u keys/signing-key.private.asc     # or keep an offline backup first
  git add keys/archive-keyring.gpg keys/archive-keyring.asc && git commit -m "Add repo signing key"

On each machine that will use the repo:
  sudo install -m644 keys/archive-keyring.gpg /usr/share/keyrings/$ORIGIN.gpg
EOF
