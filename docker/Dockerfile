# ai-docker/Dockerfile
FROM ubuntu:24.04

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
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Configure locale (required for Mosh)
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Node.js 20.x from NodeSource (required for Gemini CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
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
COPY tmux.conf /etc/tmux.conf

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
    && chmod 644 /usr/local/lib/logging.sh \
    && chmod 644 /etc/tmux.conf

# Default: run the entrypoint which creates user from env and keeps container running
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
