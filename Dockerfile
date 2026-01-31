FROM ubuntu:22.04

# Install Tailscale + SSH + GUI/RDP stack (single apt layer = smaller image)
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    python3 \
    openssh-server \
    xrdp \
    cinnamon-core \
    cinnamon-settings-daemon \
    cinnamon-session \
    cinnamon-control-center \
    cinnamon-screensaver \
    cinnamon-translations \
    gir1.2-cinnamondesktop-3.0 \
    gir1.2-cinnamonmenu-3.0 \
    gir1.2-cinnamonscreensaver-1.0 \
    gir1.2-cinnamonwm-1.0 \
    gir1.2-meta-muffin-0.0 \
    muffin-common \
    nemo \
    nemo-fileroller \
    xdg-utils \
    papirus-icon-theme \
    materia-gtk-theme \
    fonts-noto-color-emoji && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && apt-get install -y tailscale && \
    # Set RDP password (root:root) + default session
    echo "root:root" | chpasswd && \
    mkdir -p /root && echo "cinnamon-session" > /root/.xsession && \
    # Cleanup
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure SSH (keys only — RDP uses password)
RUN mkdir -p /var/run/sshd && \
    printf 'PermitRootLogin yes\nPasswordAuthentication no\nChallengeResponseAuthentication no\n' >> /etc/ssh/sshd_config

# Startup script: tailscaled → xrdp → sshd
RUN cat > /startup.sh << 'EOF'
#!/bin/bash
set -e

##################
# Optional: Your Python HTTP server (uncomment if needed)
# python3 -c 'import http.server,socketserver;http.server.SimpleHTTPRequestHandler.do_GET=lambda s:[s.send_response(200),s.send_header("Content-type","text/plain"),s.end_headers(),s.wfile.write(b"Hello World")][0];socketserver.TCPServer.allow_reuse_address=True;socketserver.TCPServer(("0.0.0.0",7860),http.server.SimpleHTTPRequestHandler).serve_forever()' &
####################

echo "🚀 Starting Tailscale SSH + RDP container..."

# Ensure state directories exist
mkdir -p /var/lib/tailscale /var/run/xrdp /tmp/.X11-unix

# Start tailscaled in background
echo "▸ Starting tailscaled..."
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state &
TAILSCALED_PID=$!

# Wait for daemon readiness
for i in {1..30}; do
  if tailscale status >/dev/null 2>&1; then
    echo "✅ tailscaled ready"
    break
  fi
  sleep 0.5
done

# Authenticate to tailnet
if [ -z "$TS_AUTHKEY" ]; then
  echo "❌ ERROR: TS_AUTHKEY not set!" >&2
  exit 1
fi

tailscale up \
  --authkey="$TS_AUTHKEY" \
  --hostname="saas-shell-$(hostname | head -c 8)" \
  --ssh \
  --advertise-exit-node \
  --timeout=60s

echo ""
echo "✅ SUCCESS: Container online!"
echo "   Tailscale IP: $(tailscale ip -4)"
echo ""
echo "   🔑 SSH:  ssh root@saas-shell-$(hostname | head -c 8)"
echo "   💻 RDP: saas-shell-$(hostname | head -c 8):3389 (user: root / pass: root)"
echo ""

# Start xrdp BEFORE sshd (runs in background)
echo "▸ Starting xrdp..."
service xrdp start

# Keep container alive with sshd in foreground
exec /usr/sbin/sshd -D -e
EOF

RUN chmod +x /startup.sh

CMD ["/startup.sh"]
