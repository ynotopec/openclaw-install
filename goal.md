Do an install.sh script idempotent for Openclaw :
```
* requirements : /root/openclaw-install-${OWNER_NAME}/.env (with BASE_DOMAIN, OPENAI_API_MODEL, OPENAI_API_KEY, OPENAI_API_BASE), /root/openclaw-install-${OWNER_NAME}/wireguard_vpn.conf, /root/openclaw-install-${OWNER_NAME}/owner-ssh.pub file, /root/openclaw-install-${OWNER_NAME}/.kubeconfig file optional
* LXC container $owner_name (last LTS Ubuntu, real LXC no LXD)
* VPN client
* ssh server
* add ssh owner public key to root
* add openclaw user sudo without password (do not forget /etc/skel)
* install opencode with openclaw user
* install openclaw with openclaw user
```
