# ai-docker/Dockerfile
# Pinned: 2026-02-19 — refresh quarterly via: docker manifest inspect ubuntu:24.04
FROM ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54

ARG AI_DOCKER_VERSION=0.0.0
LABEL ai-docker.version="${AI_DOCKER_VERSION}"
ENV DEBIAN_FRONTEND=noninteractive \
    AI_DOCKER_VERSION="${AI_DOCKER_VERSION}"

RUN printf '%s\n' "$AI_DOCKER_VERSION" > /etc/ai-docker-version

# Install dependencies FIRST (without nodejs yet)
RUN apt-get update && apt-get install -y \
    sudo \
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    unzip \
    zip \
    nano \
    vim \
    less \
    file \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    tree \
    cron \
    # iproute2 provides `ss`, the port probe used by the AI router wrappers,
    # configure_tools.sh and health checks. Installed explicitly so the probe
    # can never silently disappear (absence is treated as an error, not "free").
    iproute2 \
    # Mobile access support (optional - enabled via ENABLE_MOBILE_ACCESS=1)
    openssh-server \
    mosh \
    tmux \
    locales \
    # Security: fail2ban protects SSH from brute force attacks
    fail2ban \
    iptables \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Configure locale (required for Mosh)
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Tailscale (secure remote access - no exposed ports)
# Download script first to avoid curl-pipe-shell supply-chain risk
RUN curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh && \
    bash /tmp/tailscale-install.sh && \
    rm -f /tmp/tailscale-install.sh

# Install Node.js 22.x LTS from NodeSource (required for Gemini CLI)
# Download script first to avoid curl-pipe-shell supply-chain risk
RUN curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource-setup.sh && \
    bash /tmp/nodesource-setup.sh && \
    rm -f /tmp/nodesource-setup.sh && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Note: pipx was removed (SEC-005/DEP-017) — installed but never used


# Create working directory
WORKDIR /workspace

# Create lib directory for shared libraries
RUN mkdir -p /usr/local/lib

# Copy shared libraries
COPY lib/logging.sh /usr/local/lib/logging.sh
COPY lib/router_utils.sh /usr/local/lib/router_utils.sh
COPY lib/entrypoint_helpers.sh /usr/local/lib/entrypoint_helpers.sh

# Copy CLI tools installation scripts
COPY install_cli_tools.sh /usr/local/bin/install_cli_tools.sh
COPY auto_update.sh /usr/local/bin/auto_update.sh
COPY configure_tools.sh /usr/local/bin/configure_tools.sh

# Copy mobile access scripts and configuration
COPY setup_mobile_access.sh /usr/local/bin/setup_mobile_access.sh
COPY add_ssh_key.sh /usr/local/bin/add-ssh-key
COPY setup_remote_connection.sh /usr/local/bin/setup-remote-connection
COPY tmux.conf /etc/tmux.conf
COPY fail2ban-jail.local /etc/fail2ban/jail.d/sshd.local.template

# Copy and set up entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Fix line endings for all scripts (Windows CRLF -> Unix LF)
RUN sed -i 's/\r$//' /usr/local/bin/install_cli_tools.sh \
    /usr/local/bin/auto_update.sh \
    /usr/local/bin/configure_tools.sh \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/setup_mobile_access.sh \
    /usr/local/bin/add-ssh-key \
    /usr/local/bin/setup-remote-connection \
    /usr/local/lib/logging.sh \
    /usr/local/lib/router_utils.sh \
    /usr/local/lib/entrypoint_helpers.sh \
    /etc/tmux.conf

# Make all scripts executable and set library/config permissions
RUN chmod +x /usr/local/bin/install_cli_tools.sh \
    /usr/local/bin/auto_update.sh \
    /usr/local/bin/configure_tools.sh \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/setup_mobile_access.sh \
    /usr/local/bin/add-ssh-key \
    /usr/local/bin/setup-remote-connection \
    && chmod 644 /usr/local/lib/logging.sh \
    && chmod 644 /usr/local/lib/router_utils.sh \
    && chmod 644 /usr/local/lib/entrypoint_helpers.sh \
    && chmod 644 /etc/tmux.conf

# Default: run the entrypoint which creates user from env and keeps container running
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
