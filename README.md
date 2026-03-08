# OpenClaw LXC install

## Requirements

Host files:

- `/root/openclaw-env/.env`
- `/root/openclaw-env/wireguard_vpn.conf`
- `/root/openclaw-env/owner-ssh.pub`
- `/root/openclaw-env/.kubeconfig` (optional)

Required `.env` keys:

```env
BASE_DOMAIN=example.com
OPENAI_API_MODEL=gpt-4.1-mini
OPENAI_API_KEY=sk-...
OPENAI_API_BASE=https://...
OPENCLAW_CONTEXT_WINDOW=128000
````

## What it does

* creates or reuses a real LXC container
* installs latest Ubuntu LTS container image
* installs SSH server + WireGuard client
* adds owner SSH public key to `root`
* creates `openclaw` sudo user without password
* installs Node.js 22
* installs OpenCode and OpenClaw for `openclaw`
* writes explicit LLM config for OpenCode and OpenClaw
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

## Main files inside container

* `/root/.ssh/authorized_keys`
* `/etc/wireguard/wg0.conf`
* `/home/openclaw/.config/openclaw/.env`
* `/home/openclaw/.config/openclaw/env.sh`
* `/home/openclaw/.openclaw/openclaw.json`
* `/home/openclaw/.config/opencode/opencode.json`

## Notes

* generated files are built on host in `/root/openclaw-env/generated`
* container rootfs path used: `/var/lib/lxc/<owner>/rootfs`
* default OpenClaw context window comes from `OPENCLAW_CONTEXT_WINDOW`
```bash
