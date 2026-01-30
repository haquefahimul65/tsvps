FROM ubuntu:22.04

# Install Tailscale + SSH cleanly
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    python3 \
    openssh-server && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && apt-get install -y tailscale

# Configure SSH
RUN mkdir -p /var/run/sshd && \
    printf 'PermitRootLogin yes\nPasswordAuthentication no\nChallengeResponseAuthentication no\n' >> /etc/ssh/sshd_config

# Create robust startup script (no escaping hell)
RUN cat > /startup.sh << 'EOF'
#!/bin/bash
set -e

##################
python3 -c 'import http.server,socketserver;http.server.SimpleHTTPRequestHandler.do_GET=lambda s:[s.send_response(200),s.send_header("Content-type","text/plain"),s.end_headers(),s.wfile.write(b"Hello World")][0];socketserver.TCPServer.allow_reuse_address=True;socketserver.TCPServer(("0.0.0.0",7860),http.server.SimpleHTTPRequestHandler).serve_forever()' &
####################
echo "🚀 Starting Tailscale SSH container..."

# Ensure state directory exists
mkdir -p /var/lib/tailscale

# Start tailscaled in background
echo "▸ Starting tailscaled..."
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state &
TAILSCALED_PID=$!

# Wait for daemon readiness (max 15 seconds)
echo "▸ Waiting for tailscaled to be ready..."
for i in {1..30}; do
  if tailscale status >/dev/null 2>&1; then
    echo "✅ tailscaled ready"
    break
  fi
  sleep 0.5
done

# Validate auth key
if [ -z "$TS_AUTHKEY" ]; then
  echo "❌ ERROR: TS_AUTHKEY environment variable not set!" >&2
  exit 1
fi

# Connect to tailnet with SSH enabled
echo "▸ Authenticating with Tailscale (SSH enabled)..."
tailscale up \
  --authkey="$TS_AUTHKEY" \
  --hostname="saas-shell-$(hostname | head -c 8)" \
  --ssh \
  --advertise-exit-node \
  --timeout=60s

echo ""
echo "✅ SUCCESS: Container connected to Tailscale!"
echo "   Tailscale IP: $(tailscale ip -4)"
echo "   Hostname: $(tailscale status --self | grep -oP '^\S+')"
echo ""
echo "   🔑 From your laptop (with Tailscale running):"
echo "      ssh root@saas-shell-$(hostname | head -c 8)"
echo ""

# Start SSH daemon in foreground (keeps container alive)
exec /usr/sbin/sshd -D -e
EOF

RUN chmod +x /startup.sh

CMD ["/startup.sh"]
