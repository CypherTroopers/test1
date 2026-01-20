#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Ubuntu 24.04 (root) - Cypher node prerequisite setup
# - Go: fixed version, GO111MODULE=off (GOPATH mode)
# - Node: install via 'n' (stable), then purge apt nodejs/npm
# - UFW: allow required ports, enable if not enabled
# =========================================================

# -------- config --------
GO_VER="1.25.6"
GO_ARCH="amd64"
GO_OS="linux"
GO_TGZ="go${GO_VER}.${GO_OS}-${GO_ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_TGZ}"

GOPATH_DIR="/root/go"

# If your SSH port is NOT 22, change this before running.
SSH_PORT="22"

# UFW ports to open (tcp/udp)
UFW_RULES=(
  "allow ${SSH_PORT}/tcp"
  "allow 8000/tcp"
  "allow 6000/tcp"
  "allow 6000/udp"
  "allow 7100/tcp"
  "allow 7100/udp"
  "allow 7002/tcp"
  "allow 7002/udp"
  "allow 30303/tcp"
  "allow 30303/udp"
  "allow 30301/tcp"
  "allow 30301/udp"
  "allow 8546/tcp"
  "allow 9090/tcp"
  "allow 9090/udp"
  "allow 9600/tcp"
  "allow 9600/udp"
)

# -------- helpers --------
log() { echo -e "\n[setup] $*"; }

die() { echo -e "\n[setup][FATAL] $*" >&2; exit 1; }

on_err() {
  local ec=$?
  echo -e "\n[setup][ERROR] exit_code=${ec} at line=${BASH_LINENO[0]} cmd: ${BASH_COMMAND}" >&2
  exit "${ec}"
}
trap on_err ERR

need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Please run as root."
}

retry() {
  # retry <tries> <command...>
  local tries="$1"; shift
  local n=1
  until "$@"; do
    if (( n >= tries )); then
      return 1
    fi
    log "retry ${n}/${tries} failed; sleeping..."
    sleep $((n * 2))
    n=$((n + 1))
  done
}

append_once() {
  # append_once <file> <line>
  local f="$1"; shift
  local line="$1"; shift
  mkdir -p "$(dirname "$f")"
  touch "$f"
  grep -qxF "$line" "$f" || echo "$line" >> "$f"
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

# -------- start --------
need_root

log "Apt update + full-upgrade"
retry 3 apt-get update -y
retry 3 apt-get full-upgrade -y

log "Install base packages"
retry 3 apt_install \
  ca-certificates curl wget git nano rsync ufw \
  build-essential gcc cmake m4 bzip2 texinfo pkg-config \
  libssl-dev openssl libgmp-dev libc-dev \
  python3 python3-venv python3-pip python3-dev \
  nodejs npm pcscd

log "Apt cleanup"
apt-get autoremove -y
apt-get autoclean -y

log "Install Go ${GO_VER}"
retry 3 wget -4 -O "/tmp/${GO_TGZ}" "${GO_URL}"
rm -rf /usr/local/go
tar -C /usr/local -xzf "/tmp/${GO_TGZ}"
rm -f "/tmp/${GO_TGZ}"

# Export for current shell
export PATH="/usr/local/go/bin:/usr/local/bin:${PATH}"
export GOPATH="${GOPATH_DIR}"
export GO111MODULE=off

# Persist to /root/.bashrc (keep PATH in one line to avoid duplication/ordering bugs)
BASHRC="/root/.bashrc"
append_once "${BASHRC}" 'export PATH=/usr/local/go/bin:/usr/local/bin:$PATH'
append_once "${BASHRC}" "export GOPATH=${GOPATH_DIR}"
append_once "${BASHRC}" 'export GO111MODULE=off'

mkdir -p "${GOPATH_DIR}/src"

# Persist Go env (explicitly as requested)
go env -w GO111MODULE=off

log "Verify Go install"
command -v go >/dev/null
go version
go env GOPATH GO111MODULE

log "Upgrade Node.js via 'n' (stable)"
# npm exists from apt nodejs/npm at this point
retry 3 npm install -g n
retry 3 n stable

# Ensure /usr/local/bin wins (n installs there). Refresh command hash.
hash -r

log "Verify Node/NPM after 'n stable'"
command -v node >/dev/null
command -v npm >/dev/null
node -v
npm -v

log "Purge apt nodejs/npm (keep 'n' installed Node)"
# Purge only AFTER verifying /usr/local/bin/node and npm are alive.
retry 3 apt-get purge -y nodejs npm || true
apt-get autoremove -y
apt-get autoclean -y

hash -r

log "Install pm2"
retry 3 npm install -g pm2
command -v pm2 >/dev/null
pm2 -v || true

log "Configure UFW rules"
for rule in "${UFW_RULES[@]}"; do
  # shellcheck disable=SC2086
  ufw ${rule} >/dev/null || true
done

# Enable UFW only if not already enabled (avoid surprises)
if ufw status | head -n1 | grep -qi "inactive"; then
  log "Enable UFW"
  ufw --force enable
else
  log "UFW already enabled; keep as-is"
fi

ufw status numbered || true

log "DONE"
