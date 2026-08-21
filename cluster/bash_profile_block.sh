# >>> amarel-vscode phase 13 >>>
# Installed by the Amarel VS Code setup. Everything between these markers is
# managed; a `full` reset deletes the block by matching them, so do not remove
# or reword the marker lines.

# Refuse to host an editor remote-server on a login node (OARC policy).
#
# Cursor/VS Code bootstrap their server with `ssh -T <host> bash --login -c bash`,
# which is a LOGIN but NON-INTERACTIVE shell. Normal interactive logins have `i`
# in $-, and the amarel-dev ProxyCommand runs amarel-dev-connect without
# sourcing this file at all, so neither is affected. Verified empirically
# before enabling.
#
# Without this, a mis-targeted reconnect silently lands a ~145-thread extension
# host on the login node and nobody notices for hours. This makes it fail loudly.
#
# Escape hatch: touch ~/.allow-login-node-server to disable this guard.
#
# THE TEST KEYS ON HOSTNAME, and that is a deliberate compromise. A cgroup test
# would be more durable, except that SLURM_JOB_ID is unset in adopted SSH
# sessions, so it is not available. Login nodes are amarel3 and amarel4;
# compute nodes are hal*, halc*, halk*, gpuk*. Correct today, site-specific,
# and it would misfire on a compute node named amarel-something.
#
# TWO DETAILS THAT MUST NOT BE "TIDIED", both load-bearing:
#   * `hostname -s`, never bare `hostname`. Compute nodes have FQDNs like
#     halk0022.amarel.rutgers.edu, which CONTAIN "amarel". The short name is
#     halk0022 and does not.
#   * `== amarel*` (prefix-anchored), never `== *amarel*`. A substring match
#     would refuse every compute node and break the only sanctioned path.
# Either protection alone is sufficient; both are kept deliberately. A change
# that breaks both makes amarel-dev unreachable.
if [[ $- != *i* && "$(hostname -s)" == amarel* && ! -e "$HOME/.allow-login-node-server" ]]; then
	echo "REFUSED: this is an Amarel login node." >&2
	echo "Editor remote-servers must run on a compute node. Connect to 'amarel-dev' instead." >&2
	echo "If you really need this, run: touch ~/.allow-login-node-server" >&2
	exit 1
fi

# Thread cap for tooling spawned on a COMPUTE node.
#
# Sized to the allocation, not the machine. The SSH session is not adopted into
# the job cgroup (verified: session lands in user.slice, affinity 0-63), so
# thread pools size themselves to all 64 visible cores rather than the 4 that
# were requested. That is where chroma-mcp's 64 threads came from: an uncapped
# process reading an uncapped machine, not a claude-mem setting.
#
# SLURM_CPUS_ON_NODE is NOT set in an adopted SSH session (verified
# empirically), hence the literal fallback. Keep both.
#
# Guarded to non-login hosts: on amarel* the seatbelt in ~/.bashrc pins these
# to 1, and this must not override that. .bash_profile sources ~/.bashrc first,
# so an unguarded export here would silently undo the login-node cap.
if [[ "$(hostname -s)" != amarel* ]]; then
	_ncap="${SLURM_CPUS_PER_TASK:-${SLURM_CPUS_ON_NODE:-4}}"
	export OMP_NUM_THREADS="$_ncap" OPENBLAS_NUM_THREADS="$_ncap" \
		MKL_NUM_THREADS="$_ncap" NUMEXPR_NUM_THREADS="$_ncap" \
		RAYON_NUM_THREADS="$_ncap" VECLIB_MAXIMUM_THREADS="$_ncap"
	export TOKENIZERS_PARALLELISM=false
	# TOKIO_WORKER_THREADS is the one that actually mattered. chroma-mcp's Rust
	# core runs on Tokio, which sizes its worker pool to visible CPUs and
	# ignores OMP_NUM_THREADS completely. Measured on halk0022, chroma-mcp
	# 0.2.6:
	#   no caps                     -> 131 threads (64 tokio-rt-worker)
	#   numeric caps only           ->  71 threads (64 tokio-rt-worker, unchanged)
	#   numeric caps + TOKIO_WORKER ->  11 threads (4 tokio-rt-worker)
	# The 64 threads OARC flagged were Tokio, not OpenMP or onnxruntime.
	export TOKIO_WORKER_THREADS="$_ncap"
	unset _ncap
fi
# <<< amarel-vscode phase 13 <<<
