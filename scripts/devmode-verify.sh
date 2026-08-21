#!/usr/bin/env bash
# devmode-verify.sh -- does the phrase on stdin match the stored digest?
#
#   printf '%s' "<phrase>" | bash scripts/devmode-verify.sh
#
# Exits 0 on a match and 1 otherwise. Prints only MATCH or NO-MATCH, never the
# phrase and never any part of it.
#
# THE PHRASE ARRIVES ON STDIN, NEVER AS AN ARGUMENT. An argument would land in
# the shell history and be visible to any other process via `ps`.
#
# The verifier itself lives in devmode_verify.py rather than in a heredoc here.
# A heredoc would become this process's stdin, so python would read the script
# instead of the phrase and every check would fail closed. That bug was written
# and caught on 2026-08-21; keeping the python in its own file makes it
# impossible to reintroduce.
#
# WHAT THIS IS AND IS NOT. It is a salted PBKDF2-SHA256 verifier, so the repo
# can check the phrase without containing it: the digest is not reversible.
# It is NOT access control. A skill is instructions to an agent, and anyone
# holding this repo can read what dev mode does and do the same things by hand.
# The gate records the owner's intent. Treat it as a switch, not a lock. It also
# cannot rescue a guessable phrase: PBKDF2 raises the cost per guess, it does
# not make a common sentence uncommon.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIGEST_FILE="${DEVMODE_DIGEST:-$HERE/devmode.digest.json}"
VERIFIER="$HERE/devmode_verify.py"

# Never fail open: any missing piece is NO-MATCH.
if [ ! -r "$DIGEST_FILE" ] || [ ! -r "$VERIFIER" ] || ! command -v python3 >/dev/null 2>&1; then
	echo "NO-MATCH"
	exit 1
fi

DEVMODE_DIGEST_FILE="$DIGEST_FILE" exec python3 "$VERIFIER"
