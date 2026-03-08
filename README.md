# OpenClaw LXC install

## Host prerequisites

Already installed and configured on host:

- LXC
- LXC download template
- container networking/bridge
- `/dev/net/tun` available on host

The script does **not** install or configure LXC on host.

## Required files

- `/root/openclaw-env/.env`
- `/root/openclaw-env/wireguard_vpn.conf`
- `/root/openclaw-env/owner-ssh.pub`
- `/root/openclaw-env/.kubeconfig` (optional)

## Required `.env`

```env
BASE_DOMAIN=example.com
OPENAI_API_MODEL=gpt-4.1-mini
OPENAI_API_KEY=sk-...
OPENAI_API_BASE=https://your-openai-compatible-endpoint/v1
OPENCLAW_CONTEXT_WINDOW=128000
