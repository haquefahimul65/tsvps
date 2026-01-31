FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    curl gnupg openssh-server xrdp xfce4 xfce4-goodies \
    papirus-icon-theme materia-gtk-theme \
    dbus-x11 && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && apt-get install -y tailscale && \
    echo "root:root" | chpasswd && \
    echo "startxfce4" > /root/.xsession && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd && printf 'PermitRootLogin yes\nPasswordAuthentication no\n' >> /etc/ssh/sshd_config

RUN cat > /startup.sh << 'EOF'
#!/bin/bash
set -e
mkdir -p /var/run/dbus /var/run/xrdp
dbus-daemon --system --fork
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state &
sleep 2
until tailscale status >/dev/null 2>&1; do sleep 0.5; done
[ -z "$TS_AUTHKEY" ] && { echo "❌ TS_AUTHKEY missing"; exit 1; }
tailscale up --authkey="$TS_AUTHKEY" --hostname="saas-shell-$(hostname | head -c 8)" --ssh
echo "✅ Online! RDP: $(tailscale ip -4 | head -1):3389 (root/root)"
/usr/sbin/xrdp-sesman &
/usr/sbin/xrdp &
exec /usr/sbin/sshd -D -e
EOF

RUN chmod +x /startup.sh
CMD ["/startup.sh"]
