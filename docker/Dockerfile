# ai-docker/Dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies in one layer with cleanup
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
    nodejs \
    npm \
    jq \
    httpie \
    bat \
    ripgrep \
    fd-find \
    fzf \
    tmux \
    htop \
    tree \
    ncdu \
    cron \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create symlinks for renamed packages
RUN ln -sf /usr/bin/batcat /usr/local/bin/bat && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd

# Upgrade pip and install pipx for isolated tool installations
RUN python3 -m pip install --upgrade pip setuptools wheel pipx && \
    python3 -m pipx ensurepath

# Create working directory
WORKDIR /workspace

# Copy CLI tools installation scripts
COPY install_cli_tools.sh /usr/local/bin/install_cli_tools.sh
COPY auto_update.sh /usr/local/bin/auto_update.sh
COPY configure_tools.sh /usr/local/bin/configure_tools.sh
COPY claude_wrapper.sh /usr/local/bin/claude

# Copy and set up entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make all scripts executable
RUN chmod +x /usr/local/bin/install_cli_tools.sh \
    /usr/local/bin/auto_update.sh \
    /usr/local/bin/configure_tools.sh \
    /usr/local/bin/claude \
    /usr/local/bin/entrypoint.sh

# Default: run the entrypoint which creates user from env and keeps container running
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
