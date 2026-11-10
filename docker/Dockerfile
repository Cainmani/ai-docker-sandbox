# ai-docker/Dockerfile
# Pinned: 2026-02-19 — refresh quarterly via: docker manifest inspect ubuntu:24.04
FROM ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54 AS git-builder

# Relative worktree links require Git >= 2.48 on every participating client.
# Build into the image instead of depending on a running-container upgrade.
# Source checksum: https://www.kernel.org/pub/software/scm/git/sha256sums.asc
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl xz-utils perl pkg-config \
    libcurl4-openssl-dev libexpat1-dev libssl-dev libpcre2-dev zlib1g-dev
WORKDIR /build
RUN curl --fail --show-error --location --proto '=https' \
      https://www.kernel.org/pub/software/scm/git/git-2.56.0.tar.xz -o git.tar.xz \
    && echo '26c56c296b38c0695b26fa95f475f1d01704d2d38e73465ca30b0b2f5dc789d3  git.tar.xz' | sha256sum --check --strict \
    && tar -xJf git.tar.xz --strip-components=1 \
    && make -j"$(nproc)" prefix=/usr/local NO_RUST=1 NO_TCLTK=1 \
      NO_GETTEXT=1 USE_LIBPCRE2=YesPlease SKIP_DASHED_BUILT_INS=1 all \
    && make prefix=/usr/local DESTDIR=/opt/git NO_RUST=1 NO_TCLTK=1 \
      NO_GETTEXT=1 USE_LIBPCRE2=YesPlease SKIP_DASHED_BUILT_INS=1 install

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
    # Runtime libraries for the source-built Git (Ubuntu Git uses GnuTLS).
    libcurl4t64 \
    libexpat1 \
    libpcre2-8-0 \
    zlib1g \
    perl \
    ca-certificates \
    # Codex uses bubblewrap for its Linux/WSL2 workspace sandbox.
    bubblewrap \
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

# Keep Ubuntu Git available at /usr/bin/git; select the image build by normal
# /usr/local/bin PATH precedence. No workspace binaries or startup downloads.
COPY --from=git-builder /opt/git/usr/local/ /usr/local/
RUN test "$(command -v git)" = /usr/local/bin/git \
    && test "$(git --version)" = 'git version 2.56.0' \
    && test -x "$(git --exec-path)/git-remote-https"

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
COPY ai_docker.sh /usr/local/bin/ai-docker

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
    /usr/local/bin/ai-docker \
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
    /usr/local/bin/ai-docker \
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
