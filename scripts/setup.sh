#!/usr/bin/env bash
# amarel-vscode setup — macOS / Linux
#
# Purpose: One-shot bootstrap of SSH key auth + VS Code Server sysroot on Amarel.
# Idempotent: re-running this is safe and skips already-completed steps.
#
# Security contract:
#   - NEVER reads ~/.ssh/id_* private key contents
#   - NEVER captures passwords from stdin pipes (sshpass/expect forbidden)
#   - Every command that could prompt for a password uses BatchMode=yes after key setup
#   - User types each secret directly into a TTY prompt the OS owns
#
# Usage:
#   ./setup.sh                    # interactive, asks for username
#   AMAREL_USER=sj1136 ./setup.sh # non-interactive username

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────

readonly AMAREL_HOST="amarel.rutgers.edu"
readonly SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_amarel"
readonly SSH_CONFIG_PATH="${HOME}/.ssh/config"
readonly KNOWN_HOSTS_PATH="${HOME}/.ssh/known_hosts"

# Where the sysroot tarball lives. Override with TARBALL_URL env var if needed.
readonly DEFAULT_TARBALL_URL="https://github.com/solomonsjoseph/amarel-vscode/releases/latest/download/vscode-sysroot-x86_64-linux-gnu.tgz"
readonly TARBALL_URL="${TARBALL_URL:-$DEFAULT_TARBALL_URL}"
readonly TARBALL_LOCAL="${SKILL_DIR}/build/vscode-sysroot-x86_64-linux-gnu.tgz"

readonly CHECKSUMS_FILE="${SKILL_DIR}/assets/checksums.txt"
readonly SYSROOT_SCRIPT="${SKILL_DIR}/assets/sysroot.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

c_red()    { printf '\033[31m%s\033[0m' "$*"; }
c_green()  { printf '\033[32m%s\033[0m' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m' "$*"; }
c_bold()   { printf '\033[1m%s\033[0m' "$*"; }

say()      { printf '%s\n' "$*"; }
info()     { printf '  %s %s\n' "$(c_green '✓')" "$*"; }
warn()     { printf '  %s %s\n' "$(c_yellow '!')" "$*"; }
err()      { printf '  %s %s\n' "$(c_red '✗')" "$*" >&2; }
human()    { printf '\n%s\n' "$(c_bold "🔒 YOUR TURN: $*")"; }
heading()  { printf '\n%s %s\n' "$(c_bold "›")" "$(c_bold "$*")"; }

confirm() {
  local prompt="$1"
  local reply
  while true; do
    read -r -p "$(c_yellow "  ?") $prompt [y/N]: " reply </dev/tty
    case "$reply" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]|"")  return 1 ;;
      *) say "    please answer yes or no" ;;
    esac
  done
}

die() {
  err "$*"
  exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 0 — Preflight: tools, account info, VPN, VS Code
# ─────────────────────────────────────────────────────────────────────────────

phase_preflight() {
  heading "Phase 0 — Checking prerequisites"

  # OpenSSH client tools
  local missing=()
  for cmd in ssh scp ssh-keygen ssh-add ssh-copy-id ssh-keyscan; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing OpenSSH tools: ${missing[*]}. On macOS these ship by default; on Linux install openssh-client."
  fi
  info "OpenSSH tools present: ssh, scp, ssh-keygen, ssh-add, ssh-copy-id, ssh-keyscan"

  # VS Code (warn-only)
  if command -v code >/dev/null 2>&1; then
    info "VS Code CLI present: $(code --version 2>/dev/null | head -1)"
    if code --list-extensions 2>/dev/null | grep -q '^ms-vscode-remote.remote-ssh$'; then
      info "Remote-SSH extension installed"
    else
      warn "Remote-SSH extension not installed. Install via: code --install-extension ms-vscode-remote.remote-ssh"
    fi
  else
    warn "VS Code 'code' command not on PATH. Install VS Code and run 'Shell Command: Install code command in PATH' from Cmd+Shift+P."
  fi

  # Amarel username
  if [[ -z "${AMAREL_USER:-}" ]]; then
    read -r -p "$(c_yellow '  ?') Your Amarel username: " AMAREL_USER </dev/tty
  fi
  [[ -n "$AMAREL_USER" ]] || die "Amarel username required."
  export AMAREL_USER
  info "Amarel target: ${AMAREL_USER}@${AMAREL_HOST}"

  # VPN reachability — try to resolve + TCP connect to port 22
  if ! command -v nc >/dev/null 2>&1; then
    warn "Skipping VPN reachability check (netcat 'nc' not found)."
  else
    if nc -z -w 5 "$AMAREL_HOST" 22 >/dev/null 2>&1; then
      info "Amarel reachable on port 22 (VPN appears active)"
    else
      err  "Cannot reach ${AMAREL_HOST}:22"
      err  "Connect to the Rutgers VPN first, then re-run this skill."
      die  "VPN check failed."
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1 — SSH key creation (interactive; passphrase typed by user)
# ─────────────────────────────────────────────────────────────────────────────

phase_keygen() {
  heading "Phase 1 — SSH key"

  if [[ -f "$SSH_KEY_PATH" ]]; then
    info "Existing key found at $SSH_KEY_PATH — reusing"
    return 0
  fi

  human "I'll launch ssh-keygen interactively. Pick a passphrase you'll remember. The passphrase NEVER leaves your terminal — I cannot see what you type."
  say  ""
  say  "  Command: ssh-keygen -t ed25519 -f \"$SSH_KEY_PATH\" -C \"amarel-vscode-$(whoami)@$(hostname)\""
  say  ""

  if ! confirm "Run ssh-keygen now?"; then
    die "Aborted by user."
  fi

  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -C "amarel-vscode-$(whoami)@$(hostname)" </dev/tty

  [[ -f "$SSH_KEY_PATH" && -f "${SSH_KEY_PATH}.pub" ]] || die "Key generation failed."
  chmod 600 "$SSH_KEY_PATH"
  chmod 644 "${SSH_KEY_PATH}.pub"
  info "Key created: $SSH_KEY_PATH"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 — Host key fingerprint verification (out-of-band, human-only)
# ─────────────────────────────────────────────────────────────────────────────

phase_known_host() {
  heading "Phase 2 — Verify Amarel's host fingerprint"

  if grep -q "^${AMAREL_HOST} " "$KNOWN_HOSTS_PATH" 2>/dev/null \
  || grep -q "^|1|.*${AMAREL_HOST}" "$KNOWN_HOSTS_PATH" 2>/dev/null; then
    info "$AMAREL_HOST already in known_hosts — skipping fingerprint check"
    return 0
  fi

  say  "Fetching $AMAREL_HOST host key…"
  local tmp
  tmp="$(mktemp)"
  ssh-keyscan -t ed25519 "$AMAREL_HOST" 2>/dev/null > "$tmp" \
    || die "Could not retrieve host key from $AMAREL_HOST. (Are you on the VPN?)"

  say  ""
  say  "  Host key fingerprint (verify this against Rutgers OARC's published value):"
  ssh-keygen -lf "$tmp" | sed 's/^/    /'
  say  ""
  say  "  Reference fingerprint (recorded 2026-05-26 during initial setup):"
  say  "    SHA256:cN6l3kR3jbdOv6Ofz1b+KNCt3LaOCj9bq6yeHoR3eLs"
  say  ""

  human "Compare the fingerprint above against what Rutgers OARC publishes. Only continue if they match. A mismatch means a possible man-in-the-middle attack."

  if ! confirm "Does the fingerprint match?"; then
    rm -f "$tmp"
    die "Fingerprint mismatch or unverified — aborting."
  fi

  mkdir -p "$(dirname "$KNOWN_HOSTS_PATH")"
  touch "$KNOWN_HOSTS_PATH"
  chmod 600 "$KNOWN_HOSTS_PATH"
  cat "$tmp" >> "$KNOWN_HOSTS_PATH"
  rm -f "$tmp"
  info "Host key recorded in $KNOWN_HOSTS_PATH"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Install public key on Amarel (one-time password prompt)
# ─────────────────────────────────────────────────────────────────────────────

phase_copy_id() {
  heading "Phase 3 — Install public key on Amarel"

  # Already passwordless?
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$SSH_KEY_PATH" \
       "${AMAREL_USER}@${AMAREL_HOST}" 'true' >/dev/null 2>&1; then
    info "Key-based login already works — skipping ssh-copy-id"
    return 0
  fi

  human "ssh-copy-id will now run. When it prompts for ${AMAREL_USER}@${AMAREL_HOST}'s password, type your Amarel password into the terminal. This is the ONLY time you'll need to type it. I cannot see what you type."
  say  ""

  if ! confirm "Run ssh-copy-id now?"; then
    die "Aborted by user."
  fi

  # Force interactive auth path so password prompt hits the TTY.
  ssh-copy-id \
    -i "${SSH_KEY_PATH}.pub" \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "${AMAREL_USER}@${AMAREL_HOST}" </dev/tty

  # Re-verify with BatchMode (no fallback to password).
  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$SSH_KEY_PATH" \
        "${AMAREL_USER}@${AMAREL_HOST}" 'true' >/dev/null 2>&1; then
    die "ssh-copy-id appeared to succeed but key auth still fails. Inspect ~/.ssh/authorized_keys on Amarel."
  fi
  info "Public key installed and verified"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4 — ssh-agent + keychain (one-time passphrase prompt)
# ─────────────────────────────────────────────────────────────────────────────

phase_agent() {
  heading "Phase 4 — Save passphrase to OS keychain"

  # macOS uses --apple-use-keychain; Linux uses plain ssh-add (works with gnome-keyring).
  local add_args=()
  if [[ "$(uname -s)" == "Darwin" ]]; then
    add_args=(--apple-use-keychain)
  fi

  if ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$SSH_KEY_PATH" | awk '{print $2}')"; then
    info "Key already loaded in ssh-agent"
  else
    human "ssh-add will prompt for your key passphrase. After this, the OS keychain stores it and you'll never type it again."
    if ! confirm "Run ssh-add now?"; then
      die "Aborted by user."
    fi
    ssh-add "${add_args[@]}" "$SSH_KEY_PATH" </dev/tty
    info "Key added to ssh-agent"
  fi

  # SSH config — ensure VS Code's ssh uses keychain + agent forwarding cleanly.
  ensure_ssh_config_entry
}

ensure_ssh_config_entry() {
  mkdir -p "$(dirname "$SSH_CONFIG_PATH")"
  touch "$SSH_CONFIG_PATH"
  chmod 600 "$SSH_CONFIG_PATH"

  if grep -q "^Host $AMAREL_HOST$" "$SSH_CONFIG_PATH"; then
    info "~/.ssh/config already has entry for $AMAREL_HOST"
    return 0
  fi

  local use_keychain=""
  if [[ "$(uname -s)" == "Darwin" ]]; then
    use_keychain="  UseKeychain yes"
  fi

  cat >> "$SSH_CONFIG_PATH" <<EOF

# Added by amarel-vscode skill on $(date +%F)
Host $AMAREL_HOST
  User $AMAREL_USER
  IdentityFile $SSH_KEY_PATH
  IdentitiesOnly yes
  AddKeysToAgent yes
$use_keychain
EOF
  info "~/.ssh/config entry added"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 5 — Verify passwordless SSH end-to-end
# ─────────────────────────────────────────────────────────────────────────────

phase_verify_passwordless() {
  heading "Phase 5 — Verify passwordless SSH"

  if ssh -o BatchMode=yes -o ConnectTimeout=10 \
        "${AMAREL_USER}@${AMAREL_HOST}" 'echo ok; hostname; whoami' >/dev/null 2>&1; then
    info "Passwordless SSH works"
  else
    die "Passwordless SSH still failing. Inspect: ssh -v ${AMAREL_USER}@${AMAREL_HOST}"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 6 — Download + verify sysroot tarball
# ─────────────────────────────────────────────────────────────────────────────

phase_download_tarball() {
  heading "Phase 6 — Download sysroot tarball"

  mkdir -p "$(dirname "$TARBALL_LOCAL")"

  if [[ -f "$TARBALL_LOCAL" ]]; then
    info "Tarball already present locally: $TARBALL_LOCAL"
  else
    say "Downloading from: $TARBALL_URL"
    if ! curl -fL --progress-bar "$TARBALL_URL" -o "$TARBALL_LOCAL"; then
      err "Tarball download failed."
      err "Either the release hasn't been published yet, or your network blocks it."
      err "Build locally instead: ./scripts/build-sysroot.sh"
      die "Cannot continue without tarball."
    fi
    info "Tarball downloaded"
  fi

  verify_sha256 "$TARBALL_LOCAL" "vscode-sysroot-x86_64-linux-gnu.tgz"
}

verify_sha256() {
  local file="$1"
  local lookup_name="$2"
  local expected actual

  expected="$(awk -v n="$lookup_name" '$2==n {print $1}' "$CHECKSUMS_FILE" 2>/dev/null || true)"
  if [[ -z "$expected" || "$expected" =~ ^0+$ ]]; then
    warn "No checksum recorded for $lookup_name — skipping verification (maintainer hasn't populated $CHECKSUMS_FILE)"
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    actual="$(sha256sum "$file" | awk '{print $1}')"
  fi

  if [[ "$expected" == "$actual" ]]; then
    info "SHA-256 verified for $lookup_name"
  else
    err "SHA-256 mismatch for $lookup_name"
    err "  expected: $expected"
    err "  actual:   $actual"
    die "Refusing to install a tarball that doesn't match its recorded hash."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 7 — Deploy sysroot on Amarel
# ─────────────────────────────────────────────────────────────────────────────

phase_deploy() {
  heading "Phase 7 — Deploy sysroot on Amarel"

  local tarball_remote="vscode-sysroot-x86_64-linux-gnu.tgz"

  # Upload tarball and embedded sysroot.sh
  say "scp tarball → ${AMAREL_USER}@${AMAREL_HOST}:~/"
  scp -q "$TARBALL_LOCAL" "${AMAREL_USER}@${AMAREL_HOST}:~/${tarball_remote}"
  say "scp sysroot.sh → ${AMAREL_USER}@${AMAREL_HOST}:~/"
  scp -q "$SYSROOT_SCRIPT" "${AMAREL_USER}@${AMAREL_HOST}:~/sysroot.sh"
  info "Files uploaded"

  # Remote extraction and configuration
  ssh "${AMAREL_USER}@${AMAREL_HOST}" 'bash -se' <<'REMOTE'
set -euo pipefail

# Idempotent cleanup — remove any prior half-installed server
if [[ -d "$HOME/.vscode-server/sysroot" ]]; then
  chmod -R u+w "$HOME/.vscode-server" 2>/dev/null || true
fi
rm -rf "$HOME/.vscode-server/cli" "$HOME/.vscode-server/extensions" 2>/dev/null || true

mkdir -p "$HOME/.vscode-server"

# Extract (only if not already extracted with sysroot.sh present)
if [[ ! -d "$HOME/.vscode-server/sysroot" ]]; then
  tar zxf "$HOME/vscode-sysroot-x86_64-linux-gnu.tgz" -C "$HOME/.vscode-server"
fi

mv -f "$HOME/sysroot.sh" "$HOME/.vscode-server/sysroot.sh"
rm -f "$HOME/vscode-sysroot-x86_64-linux-gnu.tgz"

# Sanity check
test -f "$HOME/.vscode-server/sysroot/lib/ld-linux-x86-64.so.2" || { echo "ERR: linker missing"; exit 1; }
test -x "$HOME/.vscode-server/sysroot/usr/bin/patchelf"        || { echo "ERR: patchelf missing or not exec"; exit 1; }
test -f "$HOME/.vscode-server/sysroot.sh"                      || { echo "ERR: sysroot.sh missing"; exit 1; }

# Wire into ~/.bashrc if not already there
if ! grep -q '\.vscode-server/sysroot\.sh' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'BRC'

# VS Code Server custom glibc workaround (added by amarel-vscode skill)
[ -f "$HOME/.vscode-server/sysroot.sh" ] && source "$HOME/.vscode-server/sysroot.sh"
BRC
fi

# Show the env vars under a non-interactive shell (mimics VS Code)
bash -c '. "$HOME/.bashrc"; echo "VSCODE_SERVER_CUSTOM_GLIBC_LINKER=$VSCODE_SERVER_CUSTOM_GLIBC_LINKER"'
REMOTE

  info "Remote extraction + configuration complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 8 — Verify env vars survive a non-interactive SSH session
# ─────────────────────────────────────────────────────────────────────────────

phase_verify_env() {
  heading "Phase 8 — Verify env vars in non-interactive SSH"

  local result
  result="$(ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" 'echo "$VSCODE_SERVER_PATCHELF_PATH"')"
  if [[ "$result" == "/home/${AMAREL_USER}/.vscode-server/sysroot/usr/bin/patchelf" ]]; then
    info "Env vars load correctly in non-interactive shells"
  else
    err  "Got: '$result'"
    err  "Expected: /home/${AMAREL_USER}/.vscode-server/sysroot/usr/bin/patchelf"
    die  "Env vars not loading — VS Code Remote-SSH will still fail. Check ~/.bashrc on Amarel."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 9 — Final instructions (VS Code GUI is human-only)
# ─────────────────────────────────────────────────────────────────────────────

phase_finish() {
  heading "Phase 9 — Open VS Code"
  cat <<EOM

  $(c_green '✓ Server-side setup complete.')

  $(c_bold 'YOUR TURN — finish in VS Code:')

    1. Open VS Code
    2. Cmd+Shift+P (Mac) / Ctrl+Shift+P (Win/Linux)
    3. Type: $(c_bold 'Remote-SSH: Connect to Host')
    4. Pick: $(c_bold "${AMAREL_HOST}")  (or type ${AMAREL_USER}@${AMAREL_HOST})
    5. First time only: click $(c_bold 'Allow') on the "OS unsupported" warning

  After that, the bottom-left status bar shows: $(c_green "SSH: ${AMAREL_HOST}")

  If anything fails, open the Remote-SSH output panel (View → Output → Remote-SSH)
  and re-run this skill with the log output.

EOM
}

# ─────────────────────────────────────────────────────────────────────────────
# main
# ─────────────────────────────────────────────────────────────────────────────

main() {
  cat <<EOM
$(c_bold '==========================================')
$(c_bold ' amarel-vscode — Remote-SSH setup for Amarel')
$(c_bold '==========================================')

  This will:
    • Generate an SSH keypair for Amarel (if missing)
    • Install your public key on Amarel (one password prompt)
    • Save your key's passphrase in macOS Keychain
    • Deploy a custom-glibc sysroot to your Amarel \$HOME
    • Wire it into ~/.bashrc so VS Code Server installs cleanly

  You'll type two things during setup:
    • Amarel password — once, into ssh-copy-id's prompt
    • Key passphrase — once, into ssh-add's prompt
    After that: zero password typing forever.

EOM

  phase_preflight
  phase_keygen
  phase_known_host
  phase_copy_id
  phase_agent
  phase_verify_passwordless
  phase_download_tarball
  phase_deploy
  phase_verify_env
  phase_finish
}

main "$@"
