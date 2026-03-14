#!/usr/bin/env bash
# =============================================================
# EC2 Bootstrap Script
# Supports: Amazon Linux 2023 and Ubuntu 22.04 LTS
#
# Run once on a fresh instance:
#   sudo bash scripts/ec2-bootstrap.sh
# =============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Detect OS ────────────────────────────────────────────────
if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="$ID"
else
    error "Cannot detect OS — /etc/os-release not found."
fi

info "Detected OS: $OS_ID"

# ── Install Docker ────────────────────────────────────────────
install_docker_amazon_linux() {
    info "Installing Docker on Amazon Linux 2023…"
    dnf update -y
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
}

install_docker_ubuntu() {
    info "Installing Docker on Ubuntu…"
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    systemctl enable --now docker
    usermod -aG docker ubuntu
}

case "$OS_ID" in
    amzn)   install_docker_amazon_linux ;;
    ubuntu) install_docker_ubuntu ;;
    *)      error "Unsupported OS: $OS_ID. Install Docker manually." ;;
esac

docker --version && info "Docker installed successfully."

# ── Install AWS CLI v2 ────────────────────────────────────────
info "Installing AWS CLI v2…"
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp/awscli
/tmp/awscli/aws/install
rm -rf /tmp/awscliv2.zip /tmp/awscli
aws --version && info "AWS CLI installed successfully."

# ── Basic security hardening ──────────────────────────────────
info "Applying SSH hardening…"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'           /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true

# UFW firewall (Ubuntu)
if command -v ufw &>/dev/null; then
    info "Configuring UFW…"
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp    comment "SSH"
    ufw allow 80/tcp    comment "HTTP"
    ufw allow 443/tcp   comment "HTTPS"
    ufw allow 8000/tcp  comment "Gunicorn (direct, pre-Nginx)"
    ufw --force enable
    info "UFW configured."
fi

# ── Systemd service (ensures container restarts after reboot) ──
info "Creating systemd service for orbital…"
cat > /etc/systemd/system/orbital.service << 'UNIT'
[Unit]
Description=Django Application (Docker container)
After=docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=5
ExecStart=/usr/bin/docker start -a orbital
ExecStop=/usr/bin/docker stop -t 10 orbital

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
# Note: don't enable yet — container doesn't exist until first deploy

# ── Done ──────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Bootstrap complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "  Next steps:"
echo "  1. Attach an IAM role to this EC2 instance with:"
echo "       AmazonEC2ContainerRegistryReadOnly"
echo "  2. Add GitHub Secrets to your repository"
echo "     (see README.md → GitHub Secrets section)"
echo "  3. Push to main to trigger the first deploy"
echo ""
