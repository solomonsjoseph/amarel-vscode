"""Verify a dev-mode phrase against the stored salted digest.

Reads the phrase from stdin, prints MATCH or NO-MATCH, exits 0 or 1.
Never prints the phrase or any part of it. Fails closed on every error.
"""
import base64
import hashlib
import hmac
import json
import os
import re
import sys


def normalize(s: str) -> str:
    """Lowercase, drop everything but a-z 0-9 and spaces, collapse whitespace.

    So capitalisation and trailing punctuation do not matter. This widens what
    counts as a match, which is deliberate: the phrase is typed by a human, and
    the gate records intent rather than guarding a secret.
    """
    s = s.strip().lower()
    s = re.sub(r"[^a-z0-9 ]+", "", s)
    s = re.sub(r"\s+", " ", s)
    return s


def main() -> int:
    path = os.environ.get("DEVMODE_DIGEST_FILE", "")
    try:
        with open(path) as fh:
            cfg = json.load(fh)
        phrase = sys.stdin.read()
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            normalize(phrase).encode(),
            base64.b64decode(cfg["salt_b64"]),
            int(cfg["iterations"]),
        )
        expected = base64.b64decode(cfg["digest_b64"])
    except Exception:
        print("NO-MATCH")
        return 1

    # compare_digest, not ==, so the comparison time does not leak how much of
    # the digest matched.
    if hmac.compare_digest(digest, expected):
        print("MATCH")
        return 0
    print("NO-MATCH")
    return 1


if __name__ == "__main__":
    sys.exit(main())
