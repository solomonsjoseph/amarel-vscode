# VS Code Server custom glibc workaround — env vars consumed by Remote-SSH
# Sourced by ~/.bashrc on Amarel. Loaded into every non-interactive SSH session
# so the VS Code Server installer can patch its node binary against newer glibc.

# Path to the dynamic linker in the sysroot (used for --set-interpreter with patchelf)
export VSCODE_SERVER_CUSTOM_GLIBC_LINKER=$HOME/.vscode-server/sysroot/lib/ld-linux-x86-64.so.2

# Library search path in the sysroot (used as --set-rpath with patchelf)
export VSCODE_SERVER_CUSTOM_GLIBC_PATH=$HOME/.vscode-server/sysroot/usr/lib:$HOME/.vscode-server/sysroot/lib

# Path to patchelf binary on the remote host (must be >=0.18.0 per Microsoft FAQ)
export VSCODE_SERVER_PATCHELF_PATH=$HOME/.vscode-server/sysroot/usr/bin/patchelf
