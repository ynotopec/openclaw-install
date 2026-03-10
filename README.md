# OpenClaw LXC install

## Host prerequisites

Already installed and configured on host:

- LXC
- LXC download template
- container networking/bridge
- `/dev/net/tun` available on host

The script does **not** install or configure LXC on host.

## Required files

- `/root/openclaw-install-${OWNER_NAME}/.env`
- `/root/openclaw-install-${OWNER_NAME}/wireguard_vpn.conf`
- `/root/openclaw-install-${OWNER_NAME}/owner-ssh.pub`
- `/root/openclaw-install-${OWNER_NAME}/.kubeconfig` (optional)

## Required `.env`

```env
BASE_DOMAIN=example.com
OPENAI_API_MODEL=gpt-4.1-mini
OPENAI_API_KEY=sk-...
OPENAI_API_BASE=https://your-openai-compatible-endpoint/v1
OPENCLAW_CONTEXT_WINDOW=128000
````

## What it does

* creates or reuses a real LXC container
* enables `/dev/net/tun` in container config
* copies prepared files into container rootfs
* installs SSH server and WireGuard client
* adds owner SSH public key to `root`
* creates `openclaw` sudo user without password
* installs Node.js 22
* installs OpenCode and OpenClaw for `openclaw`
* writes explicit LLM config for OpenCode and OpenClaw
* syncs OpenCode/OpenClaw configs from `~/.config/openclaw/.env` at login
* copies optional kubeconfig

## Run

```bash
chmod +x install.sh
OWNER_NAME=ynotopec ./install.sh
```

or

```bash
./install.sh ynotopec
```

## Generated host files

* `/root/openclaw-install-${OWNER_NAME}/generated/openclaw.env`
* `/root/openclaw-install-${OWNER_NAME}/generated/wg0.conf`
* `/root/openclaw-install-${OWNER_NAME}/generated/authorized_keys`
* `/root/openclaw-install-${OWNER_NAME}/generated/env.sh`
* `/root/openclaw-install-${OWNER_NAME}/generated/sync-config.sh`
* `/root/openclaw-install-${OWNER_NAME}/generated/openclaw.json`
* `/root/openclaw-install-${OWNER_NAME}/generated/opencode.json`
* `/root/openclaw-install-${OWNER_NAME}/generated/container-install.sh`

## Main files inside container

* `/root/.ssh/authorized_keys`
* `/etc/wireguard/wg0.conf`
* `/root/container-install.sh`
* `/home/openclaw/.config/openclaw/.env`
* `/home/openclaw/.config/openclaw/env.sh`
* `/home/openclaw/.config/openclaw/sync-config.sh`
* `/home/openclaw/.openclaw/openclaw.json`
* `/home/openclaw/.config/opencode/opencode.json`
* `/home/openclaw/.kube/config` (optional)
