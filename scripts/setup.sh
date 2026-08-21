#!/usr/bin/env bash
# amarel-vscode setup — macOS / Linux
#
# Purpose: One-shot bootstrap of SSH key auth + VS Code Server on Amarel. Detects
#          the remote platform and, on the legacy CentOS 7 host, deploys a
#          custom-glibc sysroot; on RHEL 9 it relies on the native glibc.
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

# Amarel is migrating CentOS 7.9 → RHEL 9.6. The new RHEL 9 login node is the
# default target; override with AMAREL_HOST=… to point at the legacy host.
readonly DEFAULT_AMAREL_HOST="amarel-new.hpc.rutgers.edu"
readonly LEGACY_AMAREL_HOST="amarel.rutgers.edu"
readonly AMAREL_HOST="${AMAREL_HOST:-$DEFAULT_AMAREL_HOST}"
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
# Phase 0 — Preflight: local OS, tools, account info, VPN, VS Code
# ─────────────────────────────────────────────────────────────────────────────

phase_preflight() {
  heading "Phase 0 — Checking prerequisites"

  local os_name
  case "$(uname -s)" in
    Darwin) os_name="macOS" ;;
    Linux)  os_name="Linux" ;;
    *)
      die "Unsupported local OS: $(uname -s). On Windows, run: powershell scripts/setup.ps1"
      ;;
  esac
  info "Local OS detected: $os_name"

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

  # The scanned SHA256 fingerprint (field 2 of `ssh-keygen -lf`).
  local scanned
  scanned="$(ssh-keygen -lf "$tmp" 2>/dev/null | awk 'NR==1{print $2}')"

  # Pinned reference for this host. Both transition hosts are pinned, so the happy
  # path verifies automatically; only a non-standard AMAREL_HOST override has no pin.
  local ref="" reftxt=""
  if [[ "$AMAREL_HOST" == "$LEGACY_AMAREL_HOST" ]]; then
    ref="SHA256:cN6l3kR3jbdOv6Ofz1b+KNCt3LaOCj9bq6yeHoR3eLs"; reftxt="legacy CentOS 7, recorded 2026-05-26"
  elif [[ "$AMAREL_HOST" == "$DEFAULT_AMAREL_HOST" ]]; then
    ref="SHA256:bKbfUNxVCu2nQvssMuNBFtzoR3J7BxXU5RSI9MjWi+E"; reftxt="RHEL 9.6, recorded 2026-06-05"
  fi

  say  ""
  say  "  Scanned host key fingerprint:"
  ssh-keygen -lf "$tmp" | sed 's/^/    /'
  say  ""

  if [[ -n "$ref" ]]; then
    say  "  Recorded reference for $AMAREL_HOST ($reftxt):"
    say  "    $ref"
    say  ""
    if [[ -n "$scanned" && "$scanned" == "$ref" ]]; then
      info "✓ Fingerprint matches the recorded reference — verified automatically."
    else
      rm -f "$tmp"
      err  "  Scanned:   ${scanned:-<none>}"
      err  "  Recorded:  $ref"
      die  "FINGERPRINT MISMATCH — possible man-in-the-middle. Do NOT continue; contact Rutgers OARC."
    fi
  else
    # Non-standard host (AMAREL_HOST override) with no pinned reference — verify by hand.
    say  "  No reference fingerprint is recorded for $AMAREL_HOST (non-standard host)."
    human "Compare the fingerprint above against what Rutgers OARC publishes. Only continue if they match. A mismatch means a possible man-in-the-middle attack."
    if ! confirm "Does the fingerprint match?"; then
      rm -f "$tmp"
      die "Fingerprint mismatch or unverified — aborting."
    fi
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

  # Already passwordless and key accepted?
  # We read our public key locally and search for it in ~/.ssh/authorized_keys on Amarel.
  # This avoids false positives where another key in ssh-agent authenticates successfully
  # but our newly generated key is not yet installed on Amarel.
  local pubkey
  if [[ -f "${SSH_KEY_PATH}.pub" ]]; then
    pubkey="$(cat "${SSH_KEY_PATH}.pub")"
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes \
         "${AMAREL_USER}@${AMAREL_HOST}" "grep -qxF '$pubkey' ~/.ssh/authorized_keys" >/dev/null 2>&1; then
      info "Key-based login already works — skipping ssh-copy-id"
      return 0
    fi
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
  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes \
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
  ensure_sequoia_zshrc_fix
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

ensure_sequoia_zshrc_fix() {
  # macOS Sequoia broke persistent keychain auto-load; re-add silently on each shell.
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  local zshrc="${HOME}/.zshrc"
  if grep -q 'id_ed25519_amarel' "$zshrc" 2>/dev/null; then
    info "~/.zshrc already has Amarel ssh-add line"
    return 0
  fi
  cat >> "$zshrc" <<'EOF'

# Amarel HPC — re-load SSH key from Keychain on each shell (macOS Sequoia fix)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_amarel 2>/dev/null
EOF
  info "~/.zshrc updated with Sequoia keychain fix"
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
# Phase 5.5 — Detect the remote platform (glibc) and choose the install path
#
# Amarel is migrating CentOS 7.9 (glibc 2.17) → RHEL 9.6 (glibc 2.34). VS Code
# Server 1.99+ needs glibc >= 2.28, so:
#   glibc >= 2.28  → NATIVE  (RHEL 9): skip the sysroot + signature workarounds
#   glibc <  2.28  → LEGACY  (CentOS 7): install the custom-glibc sysroot
# Routing is on the REMOTE glibc, not the hostname, so pointing at either host
# (or a transition DNS alias) always picks the correct path. An inconclusive
# probe defaults to LEGACY — a safe superset that, at worst, installs an unneeded
# sysroot on RHEL 9 rather than stranding a real CentOS 7 user.
# ─────────────────────────────────────────────────────────────────────────────

phase_detect_platform() {
  heading "Phase 5.5 — Detect remote platform"

  local probe glibc osrel
  probe="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "${AMAREL_USER}@${AMAREL_HOST}" \
            'ldd --version 2>/dev/null | head -1; . /etc/os-release 2>/dev/null; printf "OSREL=%s-%s\n" "${ID:-?}" "${VERSION_ID:-?}"')" \
    || die "Could not probe the remote platform over SSH (Phase 5 passed, so just re-run; if it persists, check the VPN/connection)."

  # First ldd/libc line's last field is the bare glibc version (e.g. "2.34").
  glibc="$(printf '%s\n' "$probe" | awk '/[0-9]+\.[0-9]+/ && (/libc/ || /ldd/ || /GLIBC/){print $NF; exit}')"
  osrel="$(printf '%s\n'  "$probe" | awk -F= '/^OSREL=/{print $2; exit}')"

  if [[ -n "$glibc" ]] && awk -v v="$glibc" 'BEGIN{split(v,a,"."); exit !(((a[1]+0)>2)||((a[1]+0)==2&&(a[2]+0)>=28))}'; then
    PLATFORM="NATIVE"
    info "Remote platform: NATIVE — glibc ${glibc}${osrel:+ ($osrel)}; VS Code Server runs natively (skipping sysroot Phases 6–9)"
  elif [[ -n "$glibc" ]]; then
    PLATFORM="LEGACY"
    info "Remote platform: LEGACY — glibc ${glibc}${osrel:+ ($osrel)}; installing the custom-glibc sysroot"
  else
    PLATFORM="LEGACY"
    warn "Could not read the remote glibc version; defaulting to the LEGACY sysroot path (safe — at worst installs an unneeded sysroot on RHEL 9)."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 5.6 — Native host: strip any legacy sysroot residue (NATIVE only)
# A prior LEGACY run on a shared $HOME leaves the custom-glibc loader in ~/.bashrc
# (it sources ~/.vscode-server/sysroot.sh, which exports VSCODE_SERVER_CUSTOM_GLIBC_*).
# VS Code honors those env vars on RHEL 9 and shows the "unsupported OS" dialog +
# forces the sysroot code path even though native glibc 2.34 needs none of it. So on
# NATIVE we proactively remove the loader, the sysroot, and any server that was
# patchelf'd against it (it would fail to start natively). data/ is preserved.
# ─────────────────────────────────────────────────────────────────────────────

phase_native_cleanup() {
  heading "Phase 5.6 — Native host: remove any legacy sysroot residue"

  if ! ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" 'bash -se' <<'REMOTE'
set -u
cleaned=0
if [ -f "$HOME/.bashrc" ] && grep -q 'vscode-server/sysroot\.sh' "$HOME/.bashrc" 2>/dev/null; then
  sed -i.bak -e '/# VS Code Server custom glibc workaround/d' -e '\#vscode-server/sysroot\.sh#d' "$HOME/.bashrc"
  cleaned=1
fi
if [ -e "$HOME/.vscode-server/sysroot" ] || [ -e "$HOME/.vscode-server/sysroot.sh" ] || [ -e "$HOME/sysroot.sh" ]; then
  rm -rf "$HOME/.vscode-server/sysroot" "$HOME/.vscode-server/sysroot.sh" "$HOME/sysroot.sh"
  cleaned=1
fi
if [ "$cleaned" = 1 ]; then
  # The server was patchelf'd against the now-removed sysroot; drop the binaries so
  # VS Code reinstalls a clean native server. Machine/settings.json (data/) is kept.
  rm -rf "$HOME/.vscode-server/bin" "$HOME/.vscode-server/cli" 2>/dev/null
  echo "✓ Removed legacy sysroot residue (~/.bashrc loader, sysroot, patched server) — VS Code will reinstall natively"
else
  echo "✓ No legacy sysroot residue — clean native host"
fi
REMOTE
  then
    warn "Native cleanup probe failed (non-fatal). If VS Code shows an 'unsupported OS' dialog, run a full reset on Amarel."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 6 — Download + verify sysroot tarball
# ─────────────────────────────────────────────────────────────────────────────

phase_download_tarball() {
  heading "Phase 6 — Download sysroot tarball"

  mkdir -p "$(dirname "$TARBALL_LOCAL")"

  reap_prefetch wait   # if a background prefetch is in flight, finish it before checking the cache

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
  verify_tarball_intact "$TARBALL_LOCAL"
}

verify_tarball_intact() {
  # Catches truncated downloads that slipped past the hash check (e.g. when
  # checksums.txt still holds a placeholder, or curl was interrupted).
  # `tar tzf` decompresses + lists without touching the filesystem.
  local file="$1"
  if ! tar tzf "$file" >/dev/null 2>&1; then
    err "Tarball is corrupt or truncated: $file"
    err "Delete it and re-run, or rebuild with ./scripts/build-sysroot.sh"
    die "Refusing to extract a corrupt tarball."
  fi
  info "Tarball is well-formed (tar tzf passed)"
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

# Architecture guard: catch wrong-arch tarballs (e.g. someone uploaded an
# arm64 build by accident) before they fail mysteriously inside VS Code.
if command -v file >/dev/null 2>&1; then
  PE_INFO="$(file "$HOME/.vscode-server/sysroot/usr/bin/patchelf")"
  case "$PE_INFO" in
    *x86-64*|*x86_64*) : ;;
    *) echo "ERR: patchelf is not x86_64 — got: $PE_INFO" >&2; exit 1 ;;
  esac
fi

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
# Phase 9 — Disable VS Code Server extension signature verification on Amarel
#
# Why: VS Code Server's signature crypto crashes ("signature verification
# failed with UnknownError") when the node binary is patchelf'd against a
# custom glibc on CentOS 7. Disabling the second-layer VSIX check is the
# documented workaround. HTTPS to the marketplace still authenticates the
# download.
#
# The merge is idempotent and preserves any existing settings the user has.
# ─────────────────────────────────────────────────────────────────────────────

phase_disable_signature_check() {
  heading "Phase 9 — Disable extension signature verification on Amarel"

  ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" 'bash -se' <<'REMOTE'
set -euo pipefail
SETTINGS_DIR="$HOME/.vscode-server/data/Machine"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"

# Merge {"extensions.verifySignature": false} into the existing JSON without
# overwriting other keys. Prefer python3 (always present), fall back to jq.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS_FILE" <<'PY'
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            sys.exit(f"ERR: {path} is not valid JSON ({exc}); refusing to overwrite")
    if not isinstance(data, dict):
        sys.exit(f"ERR: {path} root is not a JSON object; refusing to overwrite")
data["extensions.verifySignature"] = False
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
os.replace(tmp, path)
PY
elif command -v jq >/dev/null 2>&1; then
  TMP="$(mktemp)"
  if [ -s "$SETTINGS_FILE" ]; then
    jq '. + {"extensions.verifySignature": false}' "$SETTINGS_FILE" > "$TMP" \
      || { echo "ERR: $SETTINGS_FILE is not valid JSON; refusing to overwrite" >&2; rm -f "$TMP"; exit 1; }
  else
    printf '{\n    "extensions.verifySignature": false\n}\n' > "$TMP"
  fi
  mv "$TMP" "$SETTINGS_FILE"
else
  echo "ERR: neither python3 nor jq available on Amarel; cannot safely merge settings.json" >&2
  exit 1
fi

# Post-write verification — confirm the key we set actually round-trips.
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d.get('extensions.verifySignature') is False, d; print('verified:', json.dumps(d))" "$SETTINGS_FILE" 2>/dev/null \
  || jq -e '.["extensions.verifySignature"] == false' "$SETTINGS_FILE" >/dev/null \
  || { echo "ERR: post-write check failed" >&2; exit 1; }
REMOTE

  info "Extension signature verification disabled (Install in SSH will now work for marketplace extensions)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 9.5 — Point VS Code at a modern git on Amarel (Source Control fix)
#
# VS Code Server's repo-detection probe (`git rev-parse --git-dir
# --git-common-dir`; --git-common-dir needs git >= 2.5) fails when the server
# resolves an ancient git, so Source Control registers 0 repositories.
#
#   LEGACY (CentOS 7): stock /usr/bin/git is 1.8.3.1. Point the machine-scoped
#     `git.path` at a modern git (an Lmod module) via a wrapper that loads it,
#     merged into the same Machine settings.json as Phase 9.
#   NATIVE (RHEL 9): the system git (~2.43) already passes the probe, so we run
#     the self-test and write NOTHING unless it somehow fails.
#
# Surfaced as "Phase 11" in the guided runbooks (SKILL.md / AGENTS.md), which
# walk the user through the post-connect reload + verify. Idempotent. Non-fatal:
# if no modern git is found the rest of the setup still completes.
# ─────────────────────────────────────────────────────────────────────────────

phase_configure_git() {
  heading "Phase 9.5 — Point VS Code at a modern git (Source Control)"

  local rc=0

  if [[ "${PLATFORM:-LEGACY}" == "NATIVE" ]]; then
    # RHEL 9 native path: the system git (~2.43) already satisfies VS Code's
    # repo-detection probe. Test it in a clean, server-like env and write git.path
    # ONLY if the probe fails — a healthy RHEL 9 host gets no override at all.
    # Seeds settings.json with {} (never the verifySignature key — legacy-only).
    ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" 'bash -se' <<'REMOTE' || rc=$?
set -uo pipefail
SETTINGS_DIR="$HOME/.vscode-server/data/Machine"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

ge25() { awk -v v="${1:-0.0}" 'BEGIN{split(v,a,"."); exit !(((a[1]+0)>2)||((a[1]+0)==2&&(a[2]+0)>=5))}'; }

SYS_GIT="$(command -v git 2>/dev/null || true)"
CLEAN_VER="$([ -n "$SYS_GIT" ] && env -i PATH=/usr/bin:/bin HOME="$HOME" "$SYS_GIT" --version 2>/dev/null | awk '/^git version/{print $3; exit}')"

# VS Code uses the configured git.path if one is set, else bare git. Test exactly
# that "effective" git — a stale legacy git.path from a shared $HOME (an Lmod
# wrapper or /projects/community path that may not resolve on RHEL 9; OARC warns
# module paths can differ) must not silently win and break Source Control.
CONFIGURED=""
[ -s "$SETTINGS_FILE" ] && CONFIGURED="$(sed -n 's/.*"git\.path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SETTINGS_FILE" 2>/dev/null | head -1)"
EFFECTIVE="${CONFIGURED:-$SYS_GIT}"
TESTREPO="$(mktemp -d "${TMPDIR:-/tmp}/amarel-scm.XXXXXX")"
"${EFFECTIVE:-/usr/bin/git}" init -q "$TESTREPO" 2>/dev/null || /usr/bin/git init -q "$TESTREPO" 2>/dev/null || true
if [ -n "$EFFECTIVE" ] \
   && ( cd "$TESTREPO" && env -i PATH=/usr/bin:/bin HOME="$HOME" "$EFFECTIVE" rev-parse --git-dir --git-common-dir ) >/dev/null 2>&1; then
  rm -rf "$TESTREPO"
  if [ -n "$CONFIGURED" ]; then
    echo "✓ configured git.path ($CONFIGURED) passes VS Code's repo-detection probe — Source Control OK"
  else
    echo "✓ system git ${CLEAN_VER:-?} passes VS Code's repo-detection probe — no git.path override needed"
  fi
  exit 0
fi
rm -rf "$TESTREPO"

# The effective git failed the probe (system git missing/old, or a stale legacy
# git.path that doesn't resolve on RHEL 9). Pin git.path at the system git,
# overwriting any stale value, then re-test.
GITPATH="${SYS_GIT:-/usr/bin/git}"
mkdir -p "$SETTINGS_DIR"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS_FILE" "$GITPATH" <<'PY' || { echo "ERR: settings.json merge failed" >&2; exit 1; }
import json, os, sys
path, gp = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            sys.exit(f"ERR: {path} is not valid JSON ({exc}); refusing to overwrite")
    if not isinstance(data, dict):
        sys.exit(f"ERR: {path} root is not a JSON object; refusing to overwrite")
data["git.path"] = gp
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
os.replace(tmp, path)
PY
elif command -v jq >/dev/null 2>&1; then
  TMP="$(mktemp "$SETTINGS_DIR/settings.json.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT
  if [ -s "$SETTINGS_FILE" ]; then
    jq --arg gp "$GITPATH" '. + {"git.path": $gp}' "$SETTINGS_FILE" > "$TMP" \
      || { echo "ERR: $SETTINGS_FILE is not valid JSON; refusing to overwrite" >&2; exit 1; }
  else
    jq -n --arg gp "$GITPATH" '{"git.path": $gp}' > "$TMP"
  fi
  mv -f "$TMP" "$SETTINGS_FILE"
else
  echo "ERR: neither python3 nor jq on Amarel; cannot merge settings.json" >&2
  exit 1
fi

# Re-run the probe through the pinned git.path.
TESTREPO="$(mktemp -d "${TMPDIR:-/tmp}/amarel-scm.XXXXXX")"
"$GITPATH" init -q "$TESTREPO" 2>/dev/null || /usr/bin/git init -q "$TESTREPO" 2>/dev/null || true
if ( cd "$TESTREPO" && env -i PATH=/usr/bin:/bin HOME="$HOME" "$GITPATH" rev-parse --git-dir --git-common-dir ) >/dev/null 2>&1; then
  rm -rf "$TESTREPO"
  echo "✓ git.path set to $GITPATH + repo-detection self-test PASSED"
else
  rm -rf "$TESTREPO"
  echo "✓ git.path set to $GITPATH"
  echo "SELFTEST_FAIL: VS Code repo-detection probe did not pass via git.path" >&2
  exit 4
fi
REMOTE
  else
  ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" 'bash -se' <<'REMOTE' || rc=$?
set -uo pipefail
VSROOT="$HOME/.vscode-server"
SETTINGS_DIR="$VSROOT/data/Machine"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
WRAPPER="$VSROOT/git-modern.sh"

# git >= 2.5 ? (needs --git-common-dir, which VS Code's repo probe uses)
ge25() { awk -v v="${1:-0.0}" 'BEGIN{split(v,a,"."); exit !(((a[1]+0)>2)||((a[1]+0)==2&&(a[2]+0)>=5))}'; }

# Make Lmod usable in THIS non-interactive shell, then load a modern git.
if ! command -v module >/dev/null 2>&1; then
  for i in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
    [ -f "$i" ] && . "$i" 2>/dev/null && break
  done
fi
# Amarel's git modules live in the community tree, NOT on the default MODULEPATH;
# add it before `module load git`, or the load silently finds nothing and we drop
# to NO_MODERN_GIT even though a modern git is sitting right there.
if command -v module >/dev/null 2>&1; then
  [ -d /projects/community/modulefiles ] && module use /projects/community/modulefiles 2>/dev/null || true
  module load git >/dev/null 2>&1 || true
fi
MODERN_GIT="$(command -v git 2>/dev/null || true)"
MODERN_VER="$([ -n "$MODERN_GIT" ] && "$MODERN_GIT" --version 2>/dev/null | awk '/^git version/{print $3; exit}')"
# Version when the modern git runs in a CLEAN, server-like env (no Lmod, no
# module libs) -- exactly how VS Code Server invokes it. Empty/old here means the
# binary needs its module environment to run.
CLEAN_VER="$([ -n "$MODERN_GIT" ] && env -i PATH=/usr/bin:/bin HOME="$HOME" "$MODERN_GIT" --version 2>/dev/null | awk '/^git version/{print $3; exit}')"

mkdir -p "$VSROOT"
if [ -n "$MODERN_GIT" ] && ge25 "$CLEAN_VER"; then
  # Best case (true on Amarel): the modern git is self-sufficient -- runs
  # standalone with no module libraries -- so point git.path straight at the
  # binary. No per-call Lmod cost, and it can NEVER silently fall back to the
  # stock git if a future module load fails (a missing binary fails loudly).
  rm -f "$WRAPPER"
  GITPATH="$MODERN_GIT"
  CHOSEN="absolute path $MODERN_GIT -> git $MODERN_VER (runs standalone; no wrapper needed)"
elif [ -n "$MODERN_GIT" ] && ge25 "$MODERN_VER"; then
  # The modern git works only with its module environment (it needs libraries the
  # module provides -- CLEAN_VER came back empty/old). Write a wrapper that
  # re-creates that env, then execs the modern git by its ABSOLUTE path (never a
  # bare `git`), so a failed module load still can't resolve to stock 1.8.3.1.
  cat > "$WRAPPER" <<WRAP
#!/usr/bin/env bash
# Written by amarel-vscode. VS Code Server calls this as git.path in a
# non-interactive context where Lmod is not initialised. Set up the module
# environment (this git needs its module libraries), then exec the modern git by
# ABSOLUTE path -- never bare 'git', so a failed module load can't make VS Code
# silently fall back to the CentOS 7 stock git (1.8.3.1). Keep stdout clean:
# only git may write to it (some Lmod sites log to stdout).
{
  if ! command -v module >/dev/null 2>&1; then
    for i in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
      [ -f "\$i" ] && . "\$i" 2>/dev/null && break
    done
  fi
  if command -v module >/dev/null 2>&1; then
    [ -d /projects/community/modulefiles ] && module use /projects/community/modulefiles 2>/dev/null
    module load git 2>/dev/null
  fi
} >/dev/null 2>&1
exec "${MODERN_GIT}" "\$@"
WRAP
  chmod +x "$WRAPPER"
  WRAP_VER="$(env -i PATH=/usr/bin:/bin HOME="$HOME" bash "$WRAPPER" --version 2>/dev/null | awk '/^git version/{print $3; exit}')"
  if ge25 "$WRAP_VER"; then
    GITPATH="$WRAPPER"; CHOSEN="wrapper (module env) -> git $WRAP_VER [binary needs module libs]"
  else
    rm -f "$WRAPPER"
    echo "NO_MODERN_GIT" >&2
    echo "Found git $MODERN_VER but it would not run via the module wrapper in a clean env." >&2
    echo "Run 'module use /projects/community/modulefiles && module spider git' on Amarel, then set git.path manually." >&2
    exit 3
  fi
else
  rm -f "$WRAPPER"
  echo "NO_MODERN_GIT" >&2
  echo "No git >= 2.5 found (system git: $(/usr/bin/git --version 2>/dev/null))." >&2
  echo "Run 'module use /projects/community/modulefiles && module spider git' on Amarel, then set git.path manually." >&2
  exit 3
fi

# Merge git.path into the remote Machine settings.json (preserve all other keys).
mkdir -p "$SETTINGS_DIR"
if ! command -v python3 >/dev/null 2>&1; then
  command -v module >/dev/null 2>&1 && { module load python3 2>/dev/null || module load python 2>/dev/null || true; }
fi
if command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS_FILE" "$GITPATH" <<'PY' || { echo "ERR: settings.json merge failed" >&2; exit 1; }
import json, os, sys
path, gp = sys.argv[1], sys.argv[2]
data = {"extensions.verifySignature": False}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            sys.exit(f"ERR: {path} is not valid JSON ({exc}); refusing to overwrite")
    if not isinstance(data, dict):
        sys.exit(f"ERR: {path} root is not a JSON object; refusing to overwrite")
data["git.path"] = gp
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
os.replace(tmp, path)
PY
elif command -v jq >/dev/null 2>&1; then
  TMP="$(mktemp "$SETTINGS_DIR/settings.json.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT
  if [ -s "$SETTINGS_FILE" ]; then
    jq --arg gp "$GITPATH" '. + {"git.path": $gp}' "$SETTINGS_FILE" > "$TMP" \
      || { echo "ERR: $SETTINGS_FILE is not valid JSON; refusing to overwrite" >&2; exit 1; }
  else
    jq -n --arg gp "$GITPATH" '{"extensions.verifySignature": false, "git.path": $gp}' > "$TMP"
  fi
  mv -f "$TMP" "$SETTINGS_FILE"
else
  echo "ERR: neither python3 nor jq on Amarel; cannot merge settings.json" >&2
  exit 1
fi
# Self-test: reproduce VS Code's repo-detection probe through the chosen git.path,
# in a throwaway repo + clean (server-like) env. Non-fatal signal (exit 4) if it
# does not pass, so the caller can warn without aborting the run.
TESTREPO="$(mktemp -d "${TMPDIR:-/tmp}/amarel-scm.XXXXXX")"
/usr/bin/git init -q "$TESTREPO" 2>/dev/null || true
if ( cd "$TESTREPO" && env -i PATH=/usr/bin:/bin HOME="$HOME" "$GITPATH" rev-parse --git-dir --git-common-dir ) >/dev/null 2>&1; then
  rm -rf "$TESTREPO"
  echo "✓ git.path set + repo-detection self-test PASSED: $CHOSEN"
else
  rm -rf "$TESTREPO"
  echo "✓ git.path set: $CHOSEN"
  echo "SELFTEST_FAIL: VS Code repo-detection probe did not pass via git.path" >&2
  exit 4
fi
REMOTE
  fi

  if [[ $rc -eq 0 ]]; then
    info "Source Control ready — VS Code will detect your repositories"
  elif [[ $rc -eq 3 ]]; then
    warn "No git >= 2.5 found on Amarel; Source Control needs a modern git."
    warn "Run 'module use /projects/community/modulefiles && module spider git' on Amarel, then set git.path in VS Code's Remote settings (see README troubleshooting)."
  elif [[ $rc -eq 4 ]]; then
    warn "git.path was set, but the repo-detection self-test did not pass."
    warn "Verify in VS Code (Developer: Reload Window), or see README troubleshooting."
  else
    warn "Could not configure git.path (non-fatal). Set it later via the skill's Phase 11, or VS Code Remote settings."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 9.6 — Compute-node dev session
# Surfaced as "Phase 13" in the guided runbooks (SKILL.md / AGENTS.md).
#
# Installs the cluster-side scripts that let the user open a Remote Window on
# `amarel-dev` and land on a COMPUTE node instead of a login node. OARC kills
# editor servers on login nodes, and the editor is not a thin client: its
# extension host alone ran 145 threads on amarel3.
#
# ORDER INSIDE THIS PHASE IS LOAD-BEARING. The cluster scripts are installed and
# self-tested FIRST; the ssh_config blocks are written LAST, only after
# `amarel-dev-connect --selftest` passes. Otherwise a failure mid-phase leaves a
# working-looking alias whose first click dies with "No such file or directory".
#
# Idempotent. Non-fatal: a failure here leaves the login-node setup intact.
# ─────────────────────────────────────────────────────────────────────────────

phase_compute_session() {
  heading "Phase 9.6 — Compute-node dev session (amarel-dev)"

  local rc=0

  # ── Skip probe ─────────────────────────────────────────────────────────────
  if grep -q "^Host amarel-jump$" "$SSH_CONFIG_PATH" 2>/dev/null &&
     grep -q "^Host amarel-dev$"  "$SSH_CONFIG_PATH" 2>/dev/null &&
     ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" \
         'bin/amarel-dev-connect --selftest' >/dev/null 2>&1; then
    info "amarel-dev already set up and self-testing clean"
    COMPUTE_SESSION_READY=1
    return 0
  fi

  # ── Hard gate: the remote shell must be silent on stdout ───────────────────
  # Every byte a chatty ~/.bashrc writes to stdout is fed into the SSH byte
  # stream. Measured 2026-08-21: a single clean line before the SSH banner is
  # actually tolerated, because RFC 4253 section 4.2 requires clients to process
  # lines sent before the identification string. Output after the banner, a
  # partial line, or a line starting with "SSH-" is not tolerated.
  #
  # This stays a refusal rather than a warning anyway: the difference is not
  # worth betting a connection on, and the noise is printed to the user on every
  # connect.
  # `|| true` on every probe in this phase: setup.sh runs under `set -e`, and a
  # failed assignment or a short-circuited && would abort the whole script.
  local noise=""
  noise="$(ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" true 2>/dev/null || true)"
  if [[ -n "$noise" ]]; then
    err "Your Amarel shell prints to stdout on a plain 'ssh <host> true':"
    printf '%s\n' "$noise" | sed 's/^/      /'
    err "That output rides on the amarel-dev tunnel, so Phase 9.6 is stopping here."
    say "  Fix: wrap the offending lines in your Amarel ~/.bashrc with"
    say "       case \$- in *i*) ;; *) return ;; esac"
    say "  then re-run this script."
    return 0
  fi

  # ── Ask, only when there is no conf yet ────────────────────────────────────
  # An existing ~/.amarel-dev.conf is the user's and is preserved, which is also
  # what keeps a re-run quiet.
  local have_conf=0
  if ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" \
         'test -f ~/.amarel-dev.conf' >/dev/null 2>&1; then
    have_conf=1
  fi

  local partition="" walltime="3-00:00:00"
  if [[ $have_conf -eq 1 ]]; then
    info "Keeping your existing ~/.amarel-dev.conf"
  else
    # Partition access is DETECTED, never assumed. `sbatch --test-only` predicts
    # a start time and a node without submitting anything.
    say "  Checking which partitions you can submit to…"
    # THE HEREDOC IS READ INTO A VARIABLE FIRST, DELIBERATELY. Do not "simplify"
    # this back to a heredoc inside $( ), i.e.
    #     probe="$(ssh ... 'bash -se' <<'REMOTE' ... REMOTE
    #     )"
    # macOS ships bash 3.2.57 as /bin/bash, which is what `#!/usr/bin/env bash`
    # resolves to on a stock Mac. Bash 3.2 mis-parses a quoted heredoc inside a
    # command substitution when the body contains unbalanced ")" characters: the
    # `case ... p_*)` patterns below supply exactly that, the scanner loses the
    # heredoc boundary, and it expands the body LOCALLY. Under `set -euo
    # pipefail` that aborts the whole installer with
    #     setup.sh: line NNNN: out: unbound variable
    # Measured 2026-08-21 on bash 3.2.57(1)-release (arm64-apple-darwin25).
    # Bash 5 parses it correctly, so this fails only for users without a newer
    # bash, which is most Mac users.
    local probe remote_script
    IFS= read -r -d '' remote_script <<'REMOTE' || true
set -uo pipefail
for p in $(sinfo -h -o '%R' | sort -u); do
  out=$(sbatch --test-only -p "$p" -c 4 --mem=16G --time=1-00:00:00 \
        --job-name=amarel-dev-probe --wrap true 2>&1) || continue
  case "$out" in *"to start at"*) ;; *) continue ;; esac
  t=$(printf '%s' "$out" | sed -e 's/.*to start at //' -e 's/ .*//')
  e=$(date -d "$t" +%s 2>/dev/null) || continue
  d=$(scontrol show partition "$p" 2>/dev/null | tr ' ' '\n')
  tier=$(printf '%s' "$d" | awk -F= '/^PriorityTier=/{print $2; exit}')
  ovs=$(printf '%s' "$d" | awk -F= '/^OverSubscribe=/{print $2; exit}')
  # OverSubscribe=FORCE:n shares each CPU n ways. Fine for a short GUI job,
  # wrong for an editor session that should feel responsive, so it sorts last.
  case "$ovs" in FORCE*) share=1 ;; *) share=0 ;; esac
  case "$p" in p_*) lab=lab ;; *) lab=general ;; esac
  printf '%s %s %s %s %s\n' "$p" "$e" "$lab" "${tier:-0}" "$share"
done | sort -k5,5n -k4,4nr -k2,2n
REMOTE
    probe="$(printf '%s' "$remote_script" |
      ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" 'bash -se' 2>/dev/null || true)"
    # SORTED BY PriorityTier DESCENDING, then by predicted start. Every Amarel
    # partition is PreemptMode=REQUEUE (verified 2026-08-21), so tier is what
    # decides whether a higher-tier job can requeue this session out from under
    # the user with no warning. Measured the same day: main/cmain/nonpre are
    # tier 10, cmem 20, graphical and the lab partitions 40. Picking purely by
    # "starts soonest" chose cmain, the most preemptible option there is.
    # Issue #21 called this out and it was right.
    local lab_part general_part general_tier
    lab_part="$(printf '%s\n' "$probe"     | awk '$3=="lab"     {print $1; exit}')"
    general_part="$(printf '%s\n' "$probe" | awk '$3=="general" {print $1; exit}')"
    general_tier="$(printf '%s\n' "$probe" | awk '$3=="general" {print $4; exit}')"

    if [[ -n "$lab_part" ]]; then
      info "You have access to the lab partition: $lab_part"
      if confirm "Use $lab_part for your dev sessions?"; then
        partition="$lab_part"
      fi
    fi
    if [[ -z "$partition" ]]; then
      partition="$general_part"
      if [[ -n "$partition" ]]; then
        info "Using $partition, the best general partition available to you"
        if [[ -n "$general_tier" && "$general_tier" -lt 40 ]]; then
          warn "$partition is PriorityTier=$general_tier and PreemptMode=REQUEUE."
          say  "  A higher-tier job can requeue your session with no warning, and"
          say  "  your editor just sees the connection die. If your group owns a"
          say  "  partition, use it instead: 'dev-session status' will keep warning"
          say  "  you while you are on a preemptible one."
        fi
      fi
    fi
    if [[ -z "$partition" ]]; then
      warn "No partition accepted a test submission. Skipping Phase 9.6."
      warn "Check 'sinfo' and your account associations, then re-run this script."
      return 0
    fi

    # Session length. The job holds its cores for the whole walltime whether or
    # not anyone is typing, and nothing releases it early except `dev-session
    # stop`, so this default is the only waste control there is.
    human "How long should your dev sessions be?"
    say ""
    say "    4h   a focused block. Starts fastest: short jobs fit into gaps a"
    say "         longer job cannot."
    say "    8h   a working day."
    say "    1d   overnight, or a run you want to leave going."
    say "    2d   a long stretch."
    say "    3d   the maximum on most general partitions."
    say ""
    say "    Or type a SLURM timespec yourself, for example 0-06:00:00."
    say ""
    say "    Your session holds its cores for the whole time you ask for,"
    say "    whether or not you are typing. It ends at that walltime or when you"
    say "    run 'dev-session stop'. Nothing renews it."
    say ""
    say "    There is no duration limit on Amarel. Asking for the shortest block"
    say "    that covers your work just leaves the cores free for someone else in"
    say "    between, and starting a new session is one click."
    say ""
    local answer=""
    read -r -p "$(c_yellow '  ?') Session length [4h/8h/1d/2d/3d or a timespec, default 3d]: " answer </dev/tty
    case "${answer:-3d}" in
      4h | 4H) walltime="0-04:00:00" ;;
      8h | 8H) walltime="0-08:00:00" ;;
      1d | 1D) walltime="1-00:00:00" ;;
      2d | 2D) walltime="2-00:00:00" ;;
      3d | 3D) walltime="3-00:00:00" ;;
      "")      walltime="3-00:00:00" ;;
      *)
        # A typed value must satisfy the same whitelist the cluster-side parser
        # uses, because it ends up on an sbatch command line. Anything else
        # falls back to the stated default rather than being passed through.
        if printf '%s' "$answer" | grep -Eq '^([0-9]+-)?[0-9]{1,2}(:[0-9]{2}){0,2}$'; then
          walltime="$answer"
        else
          warn "'$answer' is not a SLURM timespec (D-HH:MM:SS). Using the default 3d."
          walltime="3-00:00:00"
        fi
        ;;
    esac
    info "Sessions will request $walltime on $partition"
  fi

  # ── Install the cluster side ───────────────────────────────────────────────
  local cluster_dir="${SKILL_DIR}/cluster"
  for f in amarel-dev-lib dev-session amarel-dev-connect bash_profile_block.sh; do
    [[ -f "$cluster_dir/$f" ]] || { warn "Missing $cluster_dir/$f, skipping Phase 9.6."; return 0; }
  done

  ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" 'mkdir -p ~/bin' || {
    warn "Could not create ~/bin on Amarel (non-fatal)."; return 0; }

  scp -q "$cluster_dir/amarel-dev-lib" "$cluster_dir/dev-session" \
         "$cluster_dir/amarel-dev-connect" \
         "${AMAREL_USER}@${AMAREL_HOST}:bin/" || {
    warn "Could not copy the cluster scripts (non-fatal)."; return 0; }
  info "Installed ~/bin/{amarel-dev-lib,dev-session,amarel-dev-connect}"

  # scp does not carry the executable bit from a repo checkout reliably, so set
  # it explicitly rather than trusting the source file's mode.
  ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" \
      'chmod 755 ~/bin/dev-session ~/bin/amarel-dev-connect; chmod 644 ~/bin/amarel-dev-lib' || true

  if [[ $have_conf -eq 0 ]]; then
    # Unquoted delimiter on purpose: $partition and $walltime must expand HERE,
    # while \$HOME is escaped so it expands on the CLUSTER.
    # shellcheck disable=SC2087
    ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" 'bash -se' <<REMOTE || rc=$?
set -uo pipefail
cat > "\$HOME/.amarel-dev.conf" <<CONF
# ~/.amarel-dev.conf, written by the amarel-vscode setup, Phase 13.
# Safe to edit. Parsed as KEY=VALUE, never sourced as shell.
AMAREL_DEV_PARTITION=${partition}
AMAREL_DEV_CPUS=4
AMAREL_DEV_MEM=16G
AMAREL_DEV_WALLTIME=${walltime}
AMAREL_DEV_LOG_DIR=\$HOME/.amarel-dev-logs
CONF
chmod 600 "\$HOME/.amarel-dev.conf"
REMOTE
    if [[ $rc -eq 0 ]]; then info "Wrote ~/.amarel-dev.conf"; else warn "Could not write ~/.amarel-dev.conf"; fi
  fi

  # The login-node guard. Appended once, between markers so a reset can strip it.
  if ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" \
        'grep -q "^# >>> amarel-vscode phase 13 >>>$" ~/.bash_profile 2>/dev/null'; then
    info "~/.bash_profile already has the login-node guard"
  else
    if ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" \
           'cat >> ~/.bash_profile' < "$cluster_dir/bash_profile_block.sh"; then
      info "Appended the login-node guard to ~/.bash_profile"
    else
      warn "Could not append the login-node guard (non-fatal)."
    fi
  fi

  # ── Selftest gate. Nothing local is written until this passes. ─────────────
  if ! ssh -o BatchMode=yes "${AMAREL_USER}@${AMAREL_HOST}" \
          'bin/amarel-dev-connect --selftest'; then
    warn "The cluster-side selftest did not pass, so no ssh_config changes were made."
    warn "Fix what it reported above, then re-run this script."
    return 0
  fi
  info "Cluster-side selftest passed"

  # ── Local side: two ssh_config blocks, jump first ──────────────────────────
  ensure_ssh_jump_entry
  ensure_ssh_dev_entry

  if ssh -G amarel-dev 2>/dev/null | grep -q '^proxycommand ssh -q amarel-jump bin/amarel-dev-connect$'; then
    info "~/.ssh/config resolves amarel-dev through the cluster-side connect script"
    COMPUTE_SESSION_READY=1
  else
    warn "amarel-dev did not resolve as expected; check ~/.ssh/config by hand."
  fi
}

# The ssh_config work canNOT go inside ensure_ssh_config_entry(): that function
# returns early whenever the "Host <FQDN>" block is present, which is true for
# every existing user, so anything appended below its guard would never be
# written. These are siblings with their own guards.
#
# Jump before dev: OpenSSH takes the FIRST matching value per keyword, and the
# dev block's ProxyCommand hops through the jump host.

ensure_ssh_jump_entry() {
  mkdir -p "$(dirname "$SSH_CONFIG_PATH")" "${HOME}/.ssh/cm"
  touch "$SSH_CONFIG_PATH"
  chmod 600 "$SSH_CONFIG_PATH"

  if grep -q "^Host amarel-jump$" "$SSH_CONFIG_PATH"; then
    info "~/.ssh/config already has Host amarel-jump"
    return 0
  fi

  local use_keychain=""
  if [[ "$(uname -s)" == "Darwin" ]]; then
    use_keychain="  UseKeychain yes"
  fi

  cat >> "$SSH_CONFIG_PATH" <<EOF

# Added by amarel-vscode Phase 13 on $(date +%F)
# Plumbing only. This is what the amarel-dev ProxyCommand hops through to reach
# the cluster. DO NOT POINT YOUR EDITOR AT THIS ENTRY: it is a login node, and
# connecting an editor here is the exact behaviour OARC objected to. The
# cluster's ~/.bash_profile guard refuses an editor bootstrap here anyway, but
# do not rely on that as the only defence.
#
# No ControlMaster here, deliberately. Measured 2026-08-07: the jump hop was a
# flat 1.0s all afternoon while the compute leg swung 4-233s, so multiplexing it
# would serialize a leg that is already fast and parallel.
Host amarel-jump
  HostName $AMAREL_HOST
  User $AMAREL_USER
  IdentityFile $SSH_KEY_PATH
  IdentitiesOnly yes
  AddKeysToAgent yes
$use_keychain
  ServerAliveInterval 60
EOF
  info "~/.ssh/config: added Host amarel-jump"
}

ensure_ssh_dev_entry() {
  if grep -q "^Host amarel-dev$" "$SSH_CONFIG_PATH"; then
    info "~/.ssh/config already has Host amarel-dev"
    return 0
  fi

  cat >> "$SSH_CONFIG_PATH" <<EOF

# Added by amarel-vscode Phase 13 on $(date +%F)
# The ONLY host your editor should target. The ProxyCommand runs on the CLUSTER
# and resolves the current allocation's compute node at connect time, so this
# keeps working when the job moves. It also provisions one when none is running,
# which is why a first click works with no setup step of its own.
#
# KEEPALIVE IS TUNED FOR THE STALE-MASTER CASE. Do not raise it back to 60/10 to
# "reduce chatter". When an allocation ends, the compute node's sshd dies but no
# TCP reset reaches the laptop, because the connection runs through the login
# node. The master is left holding a half-open socket and 'ssh -O check' still
# says "Master running", wrongly. Measured 2026-08-20 by cancelling a job under
# a live master:
#     no ServerAlive   a connect attempt HUNG with no output (killed at 20s)
#     60 x 10          master cleared at ~105-120s
#     15 x 3 (this)    master cleared at 15-30s, socket removed cleanly
# The editor's ceiling is 300s, so 15x3 clears well inside it and the next click
# is a normal cold connect. Manual reset: ssh -O exit amarel-dev
#
# ServerAliveInterval 15 IS COUPLED TO 'nc -i 120s' in amarel-dev-connect on the
# cluster. The 120s idle timeout only survives because this side sends a
# keepalive every 15s. Change one and you must change the other.
#
# YES, THIS REINTRODUCES ControlMaster, WHICH ISSUE #16 REMOVED. #16 was about
# the LOGIN-NODE block, where ControlMaster bought nothing and a dead socket
# left VS Code hanging on "Unable to resolve resource", twice on 2026-06-05.
# That block still has no ControlMaster and must not get one. Here it is
# load-bearing for a different reason, and both of #16's failure modes were
# re-tested on 2026-08-21 against this config:
#   persist window expires   socket removed cleanly, next connect 2s, no hang
#   job cancelled under it   "read from master failed: Broken pipe", ssh falls
#                            back to a fresh connect and reprovisions, no hang
# The difference from #16 is this block's ControlPath (a %C hash, not a path
# built from %r@%h:%p) and the 15x3 keepalive above. If you remove the keepalive
# you are back to #16.
#
# Removing ControlPersist would let a failing ProxyCommand's message reach the
# user, which it otherwise cannot: see amarel-dev-connect's header. It was
# measured and rejected on 2026-08-21, because without it the first window owns
# the master and closing that window kills every other window.
Host amarel-dev
  User $AMAREL_USER
  IdentityFile $SSH_KEY_PATH
  IdentitiesOnly yes
  ProxyCommand ssh -q amarel-jump bin/amarel-dev-connect
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  ServerAliveInterval 15
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/cm/%C
  ControlPersist 30m
EOF
  info "~/.ssh/config: added Host amarel-dev"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 10 — Final instructions (VS Code GUI is human-only)
# ─────────────────────────────────────────────────────────────────────────────

phase_finish() {
  heading "Phase 10 — Open VS Code"

  # Once Phase 9.6 has installed amarel-dev, pointing the user at the login-node
  # host would undo the whole point of it: OARC kills editor servers there, and
  # the cluster's own ~/.bash_profile guard now refuses that connection anyway.
  # So the instruction names amarel-dev instead, and says what the other entry
  # is for.
  if [[ "${COMPUTE_SESSION_READY:-0}" -eq 1 ]]; then
    cat <<EOM

  $(c_green '✓ Server-side setup complete.')

  $(c_bold 'YOUR TURN — finish in VS Code:')

    1. Open VS Code
    2. Cmd+Shift+P (Mac) / Ctrl+Shift+P (Win/Linux)
    3. Type: $(c_bold 'Remote-SSH: Connect to Host')
    4. Pick: $(c_bold 'amarel-dev')

  That lands you on a COMPUTE node. If no job is running, one is submitted for
  you and the connection waits for it, which takes a few seconds.

  The other two entries are plumbing, not editor targets:
    ${AMAREL_HOST}   a login node. Your Amarel ~/.bash_profile now
      refuses an editor server here, because that is what OARC objected to.
    amarel-jump   what amarel-dev hops through to reach the cluster.

  Your session holds its cores until its walltime runs out. Nothing renews it
  and nothing warns you before it ends. To see or release it:

    ssh amarel-jump bin/dev-session status
    ssh amarel-jump bin/dev-session stop

  A click refuses during an Amarel maintenance window. That is expected; the
  message names the dates.

EOM
    return 0
  fi

  cat <<EOM

  $(c_green '✓ Server-side setup complete.')

  $(c_bold 'YOUR TURN — finish in VS Code:')

    1. Open VS Code
    2. Cmd+Shift+P (Mac) / Ctrl+Shift+P (Win/Linux)
    3. Type: $(c_bold 'Remote-SSH: Connect to Host')
    4. Pick: $(c_bold "${AMAREL_HOST}")  (or type ${AMAREL_USER}@${AMAREL_HOST})
    5. Legacy CentOS 7 host only: click $(c_bold 'Allow') on the "OS unsupported"
       warning the first time (RHEL 9 / amarel-new shows no such warning)

  After that, the bottom-left status bar shows: $(c_green "SSH: ${AMAREL_HOST}")

  If anything fails, open the Remote-SSH output panel (View → Output → Remote-SSH)
  and re-run this skill with the log output.

EOM
}

# ─────────────────────────────────────────────────────────────────────────────
# main
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Optional speed-up: prefetch the sysroot tarball in the BACKGROUND so the
# (LEGACY-only) download overlaps the interactive auth phases instead of blocking
# Phase 6. This is purely a cache warm-up, keyed on the target *hostname* as a hint
# (the legacy host is the one that needs the tarball) — it does NOT decide the
# install path; Phase 5.5 still routes on the remote glibc. If the hint is wrong (a
# legacy hostname already upgraded to RHEL 9) the prefetched file just sits cached,
# unused. Phase 6's checksum verification still gates correctness.
# ─────────────────────────────────────────────────────────────────────────────
PREFETCH_PID=""

prefetch_tarball_bg() {
  [[ -f "$TARBALL_LOCAL" ]] && return 0                       # already cached
  [[ "$AMAREL_HOST" == "$LEGACY_AMAREL_HOST" ]] || return 0   # native default: nothing to fetch
  command -v curl >/dev/null 2>&1 || return 0
  mkdir -p "$(dirname "$TARBALL_LOCAL")"
  ( curl -fsSL "$TARBALL_URL" -o "$TARBALL_LOCAL.partial" 2>/dev/null \
      && mv -f "$TARBALL_LOCAL.partial" "$TARBALL_LOCAL" ) &
  PREFETCH_PID=$!
  info "Prefetching the sysroot tarball in the background while you authenticate…"
}

# Reap the background prefetch: 'wait' to consume its result (LEGACY needs it),
# 'kill' to discard it (NATIVE probed on a legacy hostname — tarball not needed).
reap_prefetch() {
  [[ -n "$PREFETCH_PID" ]] || return 0
  [[ "${1:-wait}" == "kill" ]] && kill "$PREFETCH_PID" 2>/dev/null
  wait "$PREFETCH_PID" 2>/dev/null || true
  PREFETCH_PID=""
  rm -f "$TARBALL_LOCAL.partial" 2>/dev/null || true
}

main() {
  cat <<EOM
$(c_bold '==========================================')
$(c_bold ' amarel-vscode — Remote-SSH setup for Amarel')
$(c_bold '==========================================')

  This will:
    • Generate an SSH keypair for Amarel (if missing)
    • Install your public key on Amarel (one password prompt)
    • Save your key's passphrase in the OS keychain or ssh-agent
    • Detect the remote platform (RHEL 9 vs legacy CentOS 7)
    • On legacy CentOS 7 only: deploy a custom-glibc sysroot + wire ~/.bashrc

  You'll type two things during setup:
    • Amarel password — once, into ssh-copy-id's prompt
    • Key passphrase — once, into ssh-add's prompt
    After that: zero password typing forever.

EOM

  PLATFORM=LEGACY   # safe default until Phase 5.5 probes the remote host
  COMPUTE_SESSION_READY=0   # set by Phase 9.6 when amarel-dev is usable

  phase_preflight
  prefetch_tarball_bg   # warm the tarball cache in the background during auth (LEGACY hint only)
  phase_keygen
  phase_known_host
  phase_copy_id
  phase_agent
  phase_verify_passwordless
  phase_detect_platform

  # Sysroot + signature workarounds are LEGACY-only (CentOS 7). On RHEL 9 the
  # native glibc/server make them unnecessary, so Phase 5.5 routes around them.
  if [[ "$PLATFORM" == "LEGACY" ]]; then
    phase_download_tarball
    phase_deploy
    phase_verify_env
    phase_disable_signature_check
  else
    phase_native_cleanup
  fi
  reap_prefetch kill   # discard any unconsumed prefetch (e.g. legacy hostname that probed NATIVE)

  phase_configure_git
  phase_compute_session
  phase_finish
}

main "$@"
