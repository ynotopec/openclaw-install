#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Idempotent OpenClaw installer in a real LXC container
###############################################################################

ENV_DIR="${ENV_DIR:-/root/openclaw-env}"
OWNER_NAME="${OWNER_NAME:-${1:-ynotopec}}"
OPENCLAW_USER="${OPENCLAW_USER:-openclaw}"

REQUIRED_ENV_FILE="${ENV_DIR}/.env"
REQUIRED_WG_FILE="${ENV_DIR}/wireguard_vpn.conf"
REQUIRED_OWNER_SSH_FILE="${ENV_DIR}/owner-ssh.pub"
OPTIONAL_KUBECONFIG="${ENV_DIR}/.kubeconfig"

GENERATED_DIR="${ENV_DIR}/generated"

LXC_PATH="${LXC_PATH:-/var/lib/lxc}"
CONTAINER_NAME="${OWNER_NAME}"
CONTAINER_DIR="${LXC_PATH}/${CONTAINER_NAME}"
CONTAINER_ROOTFS="${CONTAINER_DIR}/rootfs"
CONFIG_FILE="${CONTAINER_DIR}/config"

UBUNTU_DIST="${UBUNTU_DIST:-ubuntu}"
UBUNTU_RELEASE="${UBUNTU_RELEASE:-noble}"
UBUNTU_ARCH="${UBUNTU_ARCH:-amd64}"

log()  { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
warn() { printf '\n[%s] WARNING: %s\n' "$(date '+%F %T')" "$*" >&2; }
die()  { printf '\n[%s] ERROR: %s\n' "$(date '+%F %T')" "$*" >&2; exit 1; }

need_file() {
  [[ -f "$1" ]] || die "Missing file: $1"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

container_exists() {
  [[ -d "${CONTAINER_DIR}" ]]
}

container_running() {
  lxc-info -n "${CONTAINER_NAME}" 2>/dev/null | grep -q '^State:[[:space:]]*RUNNING$'
}

lxc_exec() {
  lxc-attach -n "${CONTAINER_NAME}" -- bash -lc "$*"
}

wait_for_ip() {
  local timeout="${1:-90}" start now ip
  start="$(date +%s)"
  while true; do
    ip="$(lxc-info -n "${CONTAINER_NAME}" -iH 2>/dev/null | awk 'NF{print $1; exit}')"
    if [[ -n "${ip}" && "${ip}" != "-" ]]; then
      printf '%s\n' "${ip}"
      return 0
    fi
    now="$(date +%s)"
    (( now - start >= timeout )) && return 1
    sleep 2
  done
}

install_rootfs_file() {
  local src="$1" dst="$2" mode="${3:-0600}"
  install -D -m "${mode}" "${src}" "${CONTAINER_ROOTFS}${dst}"
}

append_unique_line() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -Fqx "$line" "$file" || printf '%s\n' "$line" >> "$file"
}

parse_env_value() {
  local key="$1"
  awk -F= -v k="$key" '
    /^[[:space:]]*#/ {next}
    /^[[:space:]]*$/ {next}
    $1==k {
      sub(/^[[:space:]]+/, "", $2)
      print substr($0, index($0, "=")+1)
      exit
    }
  ' "${REQUIRED_ENV_FILE}"
}

[[ $EUID -eq 0 ]] || die "Run as root."
[[ "${OWNER_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "Invalid OWNER_NAME: ${OWNER_NAME}"

need_file "${REQUIRED_ENV_FILE}"
need_file "${REQUIRED_WG_FILE}"
need_file "${REQUIRED_OWNER_SSH_FILE}"

BASE_DOMAIN="$(parse_env_value BASE_DOMAIN || true)"
OPENAI_API_MODEL="$(parse_env_value OPENAI_API_MODEL || true)"
OPENAI_API_KEY="$(parse_env_value OPENAI_API_KEY || true)"
OPENAI_API_BASE="$(parse_env_value OPENAI_API_BASE || true)"
OPENCLAW_CONTEXT_WINDOW="$(parse_env_value OPENCLAW_CONTEXT_WINDOW || true)"

[[ -n "${BASE_DOMAIN}" ]] || die "Missing BASE_DOMAIN in ${REQUIRED_ENV_FILE}"
[[ -n "${OPENAI_API_MODEL}" ]] || die "Missing OPENAI_API_MODEL in ${REQUIRED_ENV_FILE}"
[[ -n "${OPENAI_API_KEY}" ]] || die "Missing OPENAI_API_KEY in ${REQUIRED_ENV_FILE}"
[[ -n "${OPENAI_API_BASE}" ]] || die "Missing OPENAI_API_BASE in ${REQUIRED_ENV_FILE}"
OPENCLAW_CONTEXT_WINDOW="${OPENCLAW_CONTEXT_WINDOW:-128000}"

mkdir -p "${GENERATED_DIR}"

log "Installing host dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  lxc lxc-templates lxcfs uidmap debootstrap bridge-utils dnsmasq-base \
  curl wget ca-certificates gnupg jq rsync

if have_cmd systemctl; then
  systemctl enable --now lxc-net || true
fi

log "Generating files on host in ${GENERATED_DIR}"

cp -f "${REQUIRED_ENV_FILE}" "${GENERATED_DIR}/openclaw.env"
cp -f "${REQUIRED_WG_FILE}" "${GENERATED_DIR}/wg0.conf"
cp -f "${REQUIRED_OWNER_SSH_FILE}" "${GENERATED_DIR}/owner-ssh.pub"

cp -f "${REQUIRED_OWNER_SSH_FILE}" "${GENERATED_DIR}/authorized_keys"

cat > "${GENERATED_DIR}/env.sh" <<'EOF'
# generated from .env
set -a
[ -f "$HOME/.config/openclaw/.env" ] && . "$HOME/.config/openclaw/.env"
set +a
export PATH="$HOME/.local/bin:$PATH"
EOF

cat > "${GENERATED_DIR}/openclaw.json" <<EOF
{
  "models": {
    "mode": "replace",
    "providers": {
      "custom-openai": {
        "api": "openai-chat-completions",
        "baseUrl": "${OPENAI_API_BASE}",
        "apiKey": "${OPENAI_API_KEY}",
        "models": [
          {
            "id": "custom-openai/${OPENAI_API_MODEL}",
            "name": "custom-openai/${OPENAI_API_MODEL}",
            "api": "openai-chat-completions",
            "contextWindow": ${OPENCLAW_CONTEXT_WINDOW}
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": "custom-openai/${OPENAI_API_MODEL}",
      "models": [
        "custom-openai/${OPENAI_API_MODEL}"
      ],
      "contextTokens": ${OPENCLAW_CONTEXT_WINDOW}
    }
  }
}
EOF

cat > "${GENERATED_DIR}/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "custom-openai/${OPENAI_API_MODEL}",
  "provider": {
    "custom-openai": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Custom OpenAI Compatible",
      "options": {
        "baseURL": "${OPENAI_API_BASE}",
        "apiKey": "{env:OPENAI_API_KEY}"
      },
      "models": {
        "${OPENAI_API_MODEL}": {
          "name": "${OPENAI_API_MODEL}"
        }
      }
    }
  }
}
EOF

chmod 600 "${GENERATED_DIR}/openclaw.env" "${GENERATED_DIR}/wg0.conf"
chmod 644 "${GENERATED_DIR}/env.sh" "${GENERATED_DIR}/openclaw.json" "${GENERATED_DIR}/opencode.json" "${GENERATED_DIR}/authorized_keys"

if ! container_exists; then
  log "Creating container ${CONTAINER_NAME}"
  lxc-create -n "${CONTAINER_NAME}" -t download -- \
    -d "${UBUNTU_DIST}" -r "${UBUNTU_RELEASE}" -a "${UBUNTU_ARCH}"
else
  log "Container ${CONTAINER_NAME} already exists"
fi

touch "${CONFIG_FILE}"
if ! grep -q 'lxc.net.0.type[[:space:]]*=[[:space:]]*veth' "${CONFIG_FILE}"; then
  cat >> "${CONFIG_FILE}" <<'EOF'

# added by install.sh
lxc.net.0.type = veth
lxc.net.0.link = lxcbr0
lxc.net.0.flags = up
EOF
fi

log "Copying files into container rootfs"
install_rootfs_file "${GENERATED_DIR}/authorized_keys" "/root/.ssh/authorized_keys" 0600
install_rootfs_file "${GENERATED_DIR}/wg0.conf" "/etc/wireguard/wg0.conf" 0600
install_rootfs_file "${GENERATED_DIR}/openclaw.env" "/home/${OPENCLAW_USER}/.config/openclaw/.env" 0600
install_rootfs_file "${GENERATED_DIR}/env.sh" "/home/${OPENCLAW_USER}/.config/openclaw/env.sh" 0644
install_rootfs_file "${GENERATED_DIR}/openclaw.json" "/home/${OPENCLAW_USER}/.openclaw/openclaw.json" 0644
install_rootfs_file "${GENERATED_DIR}/opencode.json" "/home/${OPENCLAW_USER}/.config/opencode/opencode.json" 0644

if [[ -f "${OPTIONAL_KUBECONFIG}" ]]; then
  install_rootfs_file "${OPTIONAL_KUBECONFIG}" "/home/${OPENCLAW_USER}/.kube/config" 0600
fi

if ! container_running; then
  log "Starting container ${CONTAINER_NAME}"
  lxc-start -n "${CONTAINER_NAME}"
else
  log "Container ${CONTAINER_NAME} already running"
fi

IP="$(wait_for_ip 90 || true)"
[[ -n "${IP:-}" ]] && log "Container IP: ${IP}" || warn "Container IP not detected"

log "Installing packages in container"
lxc_exec '
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y \
  sudo openssh-server wireguard wireguard-tools \
  curl wget ca-certificates gnupg git jq unzip xz-utils build-essential \
  iproute2 iptables procps nano bash-completion

mkdir -p /var/run/sshd
systemctl enable ssh
systemctl restart ssh
'

log "Installing Node.js 22 in container"
lxc_exec '
set -Eeuo pipefail

need_install=1
if command -v node >/dev/null 2>&1; then
  major="$(node -p "process.versions.node.split(\".\")[0]")"
  if [ "${major}" -ge 22 ]; then
    need_install=0
  fi
fi

if [ "${need_install}" -eq 1 ]; then
  install -d -m 0755 /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/nodesource.gpg ]; then
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    chmod 0644 /etc/apt/keyrings/nodesource.gpg
  fi

  cat >/etc/apt/sources.list.d/nodesource.list <<EOF
deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main
EOF

  apt-get update -y
  apt-get install -y nodejs
fi
'

log "Creating user ${OPENCLAW_USER}"
lxc_exec "
set -Eeuo pipefail

if ! id -u '${OPENCLAW_USER}' >/dev/null 2>&1; then
  useradd -m -s /bin/bash '${OPENCLAW_USER}'
fi

usermod -aG sudo '${OPENCLAW_USER}'
install -d -m 0755 /etc/sudoers.d
cat >/etc/sudoers.d/90-${OPENCLAW_USER} <<'EOF'
${OPENCLAW_USER} ALL=(ALL) NOPASSWD:ALL
EOF
chmod 0440 /etc/sudoers.d/90-${OPENCLAW_USER}

install -d -m 0755 /etc/skel/.config/openclaw
install -d -m 0755 /etc/skel/.config/opencode
touch /etc/skel/.profile
grep -Fqx 'export PATH=\"\$HOME/.local/bin:\$PATH\"' /etc/skel/.profile || printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >> /etc/skel/.profile
grep -Fqx '[ -f \"\$HOME/.config/openclaw/env.sh\" ] && . \"\$HOME/.config/openclaw/env.sh\"' /etc/skel/.profile || printf '%s\n' '[ -f "$HOME/.config/openclaw/env.sh" ] && . "$HOME/.config/openclaw/env.sh"' >> /etc/skel/.profile

install -d -o '${OPENCLAW_USER}' -g '${OPENCLAW_USER}' -m 0700 /home/'${OPENCLAW_USER}'/.ssh
install -d -o '${OPENCLAW_USER}' -g '${OPENCLAW_USER}' -m 0755 /home/'${OPENCLAW_USER}'/.config/openclaw
install -d -o '${OPENCLAW_USER}' -g '${OPENCLAW_USER}' -m 0755 /home/'${OPENCLAW_USER}'/.config/opencode
install -d -o '${OPENCLAW_USER}' -g '${OPENCLAW_USER}' -m 0755 /home/'${OPENCLAW_USER}'/.openclaw

touch /home/'${OPENCLAW_USER}'/.profile
grep -Fqx 'export PATH=\"\$HOME/.local/bin:\$PATH\"' /home/'${OPENCLAW_USER}'/.profile || printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >> /home/'${OPENCLAW_USER}'/.profile
grep -Fqx '[ -f \"\$HOME/.config/openclaw/env.sh\" ] && . \"\$HOME/.config/openclaw/env.sh\"' /home/'${OPENCLAW_USER}'/.profile || printf '%s\n' '[ -f "$HOME/.config/openclaw/env.sh" ] && . "$HOME/.config/openclaw/env.sh"' >> /home/'${OPENCLAW_USER}'/.profile
chown '${OPENCLAW_USER}':'${OPENCLAW_USER}' /home/'${OPENCLAW_USER}'/.profile

if [ -f /home/'${OPENCLAW_USER}'/.kube/config ]; then
  chown -R '${OPENCLAW_USER}':'${OPENCLAW_USER}' /home/'${OPENCLAW_USER}'/.kube
  chmod 700 /home/'${OPENCLAW_USER}'/.kube
  chmod 600 /home/'${OPENCLAW_USER}'/.kube/config
fi

chown root:root /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

chown -R '${OPENCLAW_USER}':'${OPENCLAW_USER}' /home/'${OPENCLAW_USER}'/.config /home/'${OPENCLAW_USER}'/.openclaw
chmod 600 /home/'${OPENCLAW_USER}'/.config/openclaw/.env
"

log "Enabling WireGuard"
lxc_exec '
set -Eeuo pipefail
chmod 600 /etc/wireguard/wg0.conf
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0 || true
'

log "Installing OpenCode and OpenClaw"
lxc_exec "
set -Eeuo pipefail
su - '${OPENCLAW_USER}' -c '
  set -Eeuo pipefail
  mkdir -p \"\$HOME/.local/bin\"
  npm config set prefix \"\$HOME/.local\"
  export PATH=\"\$HOME/.local/bin:\$PATH\"

  npm install -g opencode-ai
  npm install -g openclaw@latest

  command -v opencode >/dev/null
  command -v openclaw >/dev/null
'
"

log "Final checks"
lxc_exec "
set -Eeuo pipefail
systemctl enable ssh
systemctl restart ssh
"
lxc_exec "su - '${OPENCLAW_USER}' -c 'export PATH=\"\$HOME/.local/bin:\$PATH\"; opencode --help >/dev/null 2>&1 || true; openclaw --help >/dev/null 2>&1 || true'"

echo
echo "Done"
echo "Container    : ${CONTAINER_NAME}"
echo "User         : ${OPENCLAW_USER}"
echo "Rootfs       : ${CONTAINER_ROOTFS}"
[[ -n "${IP:-}" ]] && echo "IP           : ${IP}"
echo
echo "Checks:"
echo "  lxc-attach -n ${CONTAINER_NAME} -- bash -lc 'systemctl status ssh --no-pager'"
echo "  lxc-attach -n ${CONTAINER_NAME} -- bash -lc 'systemctl status wg-quick@wg0 --no-pager || true'"
echo "  lxc-attach -n ${CONTAINER_NAME} -- su - ${OPENCLAW_USER} -c 'export PATH=\"\$HOME/.local/bin:\$PATH\"; opencode --help | head'"
echo "  lxc-attach -n ${CONTAINER_NAME} -- su - ${OPENCLAW_USER} -c 'export PATH=\"\$HOME/.local/bin:\$PATH\"; openclaw --help | head'"
echo
echo "Generated files on host:"
echo "  ${GENERATED_DIR}/openclaw.json"
echo "  ${GENERATED_DIR}/opencode.json"
echo "  ${GENERATED_DIR}/env.sh"
