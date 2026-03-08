Do an install.sh script idempotent for Openclaw :
```
* requirements : /root/openclaw-env/.env (with BASE_DOMAIN, OPENAI_API_MODEL, OPENAI_API_KEY, OPENAI_API_BASE), /root/openclaw-env/wireguard_vpn.conf, /root/openclaw-env/owner-ssh.pub file, /root/openclaw-env/.kubeconfig file optional
* LXC container $owner_name (last LTS Ubuntu, real LXC no LXD)
* VPN client
* ssh server
* add ssh owner public key to root
* add openclaw user sudo without password (do not forget /etc/skel)
* install opencode with openclaw user
* install openclaw with openclaw user
```
