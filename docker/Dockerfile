# ai-docker/Dockerfile
# Pinned: 2026-02-19 — refresh quarterly via: docker manifest inspect ubuntu:24.04
FROM ubuntu:24.04@sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9

ENV DEBIAN_FRONTEND=noninteractive

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

# Upgrade pip and install pipx for isolated tool installations
RUN python3 -m pip install --no-cache-dir --break-system-packages pipx


# Create working directory
WORKDIR /workspace

# Create lib directory for shared libraries
RUN mkdir -p /usr/local/lib

# Copy shared libraries
COPY lib/logging.sh /usr/local/lib/logging.sh

# Copy CLI tools installation scripts
COPY install_cli_tools.sh /usr/local/bin/install_cli_tools.sh
COPY auto_update.sh /usr/local/bin/auto_update.sh
COPY configure_tools.sh /usr/local/bin/configure_tools.sh
COPY claude_wrapper.sh /usr/local/bin/claude

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
    /usr/local/bin/claude \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/setup_mobile_access.sh \
    /usr/local/bin/add-ssh-key \
    /usr/local/bin/setup-remote-connection \
    /usr/local/lib/logging.sh \
    /etc/tmux.conf

# Make all scripts executable and set library/config permissions
RUN chmod +x /usr/local/bin/install_cli_tools.sh \
    /usr/local/bin/auto_update.sh \
    /usr/local/bin/configure_tools.sh \
    /usr/local/bin/claude \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/setup_mobile_access.sh \
    /usr/local/bin/add-ssh-key \
    /usr/local/bin/setup-remote-connection \
    && chmod 644 /usr/local/lib/logging.sh \
    && chmod 644 /etc/tmux.conf

# Default: run the entrypoint which creates user from env and keeps container running
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
