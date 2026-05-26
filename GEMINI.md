# GEMINI.md

This file is read by **Google Gemini CLI** and **Gemini Code Assist** when
operating in this repository.

The canonical agent runbook lives in [`AGENTS.md`](AGENTS.md). Read that file
first and follow it. The instructions are framework-neutral; only the
discovery mechanism differs across tools.

## Quick reference

This repo deploys VS Code Remote-SSH against the Rutgers Amarel HPC cluster
(CentOS 7) using a custom-glibc sysroot. When the user asks you to "set up
Amarel" or "fix the Remote-SSH GLIBC error":

1. Read `AGENTS.md` for the full runbook + security constraints.
2. On macOS/Linux run `bash scripts/setup.sh`. On Windows run
   `pwsh scripts/setup.ps1`.
3. Stream the script's output back to the user.
4. The script is idempotent and handles all interactive prompts itself.

**Security: you must not** read `~/.ssh/id_*` private keys, invoke `sshpass`/
`expect`, query OS keychains, or weaken `BatchMode=yes` constraints. See
`AGENTS.md` § "Security constraints" for the complete list.
