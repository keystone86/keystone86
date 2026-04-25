FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# --------------------------------------------------------------------
# Layer 1 — Base system and build tools
# --------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    build-essential \
    make \
    cmake \
    pkg-config \
    wget \
    curl \
    unzip \
    dos2unix \
    entr \
    ripgrep \
    jq \
    tree \
    xxd \
    xz-utils \
    libssl-dev \
    libreadline-dev \
    libffi-dev \
    zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------------
# Layer 2 — Simulation tools
# iverilog 11.0 on 22.04 — fully supports -g2012 for this project
# --------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    iverilog \
    verilator \
    gtkwave \
 && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------------
# Layer 3 — Python toolchain
# --------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
 && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
    pyyaml \
    jinja2 \
    click \
    pytest

# --------------------------------------------------------------------
# Layer 4 — OSS CAD Suite
# Includes: yosys, nextpnr-ecp5, prjtrellis/ecppack, sv2v,
#           symbiyosys, z3, yosys-smtbmc, openFPGALoader and more.
#
# This is the recommended distribution for this open source toolchain.
# All tools install to /opt/oss-cad-suite/bin
# --------------------------------------------------------------------
RUN OSS_DATE=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest \
      | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)".*/\1/') \
 && OSS_VERSION=$(echo $OSS_DATE | sed 's/-//g') \
 && echo "Installing OSS CAD Suite $OSS_DATE" \
 && curl -L \
    "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${OSS_DATE}/oss-cad-suite-linux-x64-${OSS_VERSION}.tgz" \
    -o /tmp/oss-cad-suite.tgz \
 && tar -xzf /tmp/oss-cad-suite.tgz -C /opt \
 && rm /tmp/oss-cad-suite.tgz

ENV PATH="/opt/oss-cad-suite/bin:${PATH}"

# --------------------------------------------------------------------
# Layer 5 — USB support for openFPGALoader (ECP5 hardware flashing)
# Use 'make dev-fpga' to enable USB passthrough
# --------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    libusb-1.0-0 \
    udev \
 && rm -rf /var/lib/apt/lists/*

# ECP5 udev rules so openFPGALoader can claim USB devices
RUN mkdir -p /etc/udev/rules.d \
 && echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0666", GROUP="plugdev"' \
    > /etc/udev/rules.d/99-openfpgaloader.rules \
 && echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", MODE="0666", GROUP="plugdev"' \
    >> /etc/udev/rules.d/99-openfpgaloader.rules

# --------------------------------------------------------------------
# Layer 6 — Claude Code
# Credentials are NOT baked in. Auth is handled per-developer via:
#   Local:      named Docker volume keystone86-claude-auth:/root/.claude
#   Codespaces: ANTHROPIC_API_KEY personal secret
# --------------------------------------------------------------------
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.local/bin:${PATH}"

# --------------------------------------------------------------------
# Layer 7 — OpenAI Codex CLI
# Coexists with Claude Code in the same dev image. Use one AI coding
# agent at a time from an interactive shell:
#
#   claude   # Claude Code
#   codex    # OpenAI Codex CLI
#
# Credentials are NOT baked in. Auth should be handled per-developer via:
#   Local:      named Docker volume keystone86-codex-auth:/root/.codex
#   Codespaces: OPENAI_API_KEY personal secret, or interactive Codex login
#
# The Makefile/devcontainer are responsible for mounting /root/.codex.
# --------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get update \
 && apt-get install -y --no-install-recommends nodejs \
 && npm install -g @openai/codex \
 && npm cache clean --force \
 && rm -rf /var/lib/apt/lists/*

# Color console — placed last to preserve build cache for heavy layers above
ENV TERM=xterm-256color
RUN echo 'export PS1="\[\033[01;32m\]\u@keystone86-dev\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /root/.bashrc \
 && echo 'alias ls="ls --color=auto"' >> /root/.bashrc \
 && echo 'alias grep="grep --color=auto"' >> /root/.bashrc \
 && echo 'force_color_prompt=yes' >> /root/.bashrc \
 && git config --global --add safe.directory /work

# --------------------------------------------------------------------
# Working directory
# The repo is mounted here at runtime: -v $(PWD):/work
# --------------------------------------------------------------------
WORKDIR /work

CMD ["/bin/bash"]