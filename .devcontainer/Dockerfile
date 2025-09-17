FROM debian:latest

# Run as root
USER root

# Install additional OS packages
RUN apt update && apt upgrade -y && export DEBIAN_FRONTEND=noninteractive \
    && apt -y install --no-install-recommends \
    curl \
    git \
    nodejs \
    npm

# Install Node.js (latest LTS)
#RUN cd /tmp; curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
#    && apt install -y nodejs \
#    && npm install -g npm@latest

# Install Claude Code
#RUN npm install -g @anthropic-ai/claude-code

# Set up the workspace
#WORKDIR /workspace
