FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# --------------------------------------------------------------------
# Layer 1 — Base system and build tools
# (your existing base, extended)
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
# Layer 4 — Yosys (synthesis frontend, used for both ECP5 and formal)
# --------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    yosys \
 && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------------
# Layer 5 — ECP5 toolchain (prjtrellis + nextpnr-ecp5)
# --------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    libtrellis-dev \
    prjtrellis \
    prjtrellis-tools \
    nextpnr-ecp5 \
 && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------------
# Layer 6 — sv2v (SystemVerilog to Verilog for tools that need it)
# --------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    haskell-stack \
 && rm -rf /var/lib/apt/lists/* \
 && stack install sv2v \
 && cp /root/.local/bin/sv2v /usr/local/bin/sv2v

# --------------------------------------------------------------------
# Layer 7 — Formal verification (SymbiYosys + solvers)
# --------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    symbiyosys \
    yosys-smtbmc \
    z3 \
    boolector \
 && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------------
# Layer 8 — openFPGALoader + USB framework for ECP5 hardware flashing
# (use 'make dev-fpga' to enable USB passthrough)
# --------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    openfpgaloader \
    libusb-1.0-0 \
    libusb-1.0-0-dev \
    udev \
 && rm -rf /var/lib/apt/lists/*

# Install ECP5 udev rules so openFPGALoader can claim USB devices
# without needing root inside the container
RUN mkdir -p /etc/udev/rules.d \
 && echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0666", GROUP="plugdev"' \
    > /etc/udev/rules.d/99-openfpgaloader.rules \
 && echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", MODE="0666", GROUP="plugdev"' \
    >> /etc/udev/rules.d/99-openfpgaloader.rules

# --------------------------------------------------------------------
# Layer 9 — Claude Code
# Credentials are NOT baked in. Auth is handled per-developer via:
#   Local:      named Docker volume keystone86-claude-auth:/root/.claude
#   Codespaces: ANTHROPIC_API_KEY personal secret
# --------------------------------------------------------------------
RUN curl -fsSL https://claude.ai/install.sh | sh

# --------------------------------------------------------------------
# Working directory
# The repo is mounted here at runtime: -v $(PWD):/work
# --------------------------------------------------------------------
WORKDIR /work

CMD ["/bin/bash"]
