# ai-docker/Dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies in one layer with cleanup
RUN apt-get update && apt-get install -y \
    sudo \
    curl \
    git \
    ca-certificates \
    gnupg \
    unzip \
    nano \
    less \
    file \
    python3 \
    python3-pip \
    nodejs \
    npm \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create working directory
WORKDIR /workspace

# Copy and set up entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Default: run the entrypoint which creates user from env and keeps container running
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
