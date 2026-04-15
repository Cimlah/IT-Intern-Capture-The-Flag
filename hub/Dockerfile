FROM node:20-bookworm-slim AS builder

# Build the C helpers and the Ink TUI in one stage.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libcrypt-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Helpers (tiny, no deps)
COPY helpers/ctf-verify.c /build/helpers/ctf-verify.c
COPY helpers/ctf-reveal.c /build/helpers/ctf-reveal.c
RUN gcc -O2 -Wall -Wextra -o /build/ctf-verify /build/helpers/ctf-verify.c && \
    gcc -O2 -Wall -Wextra -o /build/ctf-reveal /build/helpers/ctf-reveal.c -lcrypt

# Ink TUI
WORKDIR /build/app
COPY app/package.json app/package-lock.json* ./
RUN npm install --no-audit --no-fund
COPY app/tsconfig.json ./tsconfig.json
COPY app/src ./src
RUN npm run build

# ----------------------------------------------------------------------------
FROM node:20-bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    nmap \
    curl wget \
    netcat-openbsd \
    dnsutils \
    python3 python3-pip \
    jq xxd openssl \
    iproute2 iputils-ping \
    nano vim-tiny less \
    grep gawk sed findutils file tree \
    gettext-base \
    tmux \
    ca-certificates \
    libcrypt1 \
    sudo \
    ssh-client \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/sshd /var/ctf/state /etc/ctf /opt/ctf-hub

# Ink app
COPY --from=builder /build/app/dist /opt/ctf-hub/dist
COPY --from=builder /build/app/node_modules /opt/ctf-hub/node_modules
COPY --from=builder /build/app/package.json /opt/ctf-hub/package.json

# Setuid helpers
COPY --from=builder /build/ctf-verify /usr/local/bin/ctf-verify
COPY --from=builder /build/ctf-reveal /usr/local/bin/ctf-reveal
RUN chown root:root /usr/local/bin/ctf-verify /usr/local/bin/ctf-reveal && \
    chmod 4755 /usr/local/bin/ctf-verify /usr/local/bin/ctf-reveal

# Login shell wrapper + sshd config + motd
COPY bin/hub-shell /usr/local/bin/hub-shell
COPY sshd_config /etc/ssh/sshd_config
COPY motd /etc/ctf/motd
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/hub-shell /entrypoint.sh

# Intern user — fixed password "ctf"; SSH is not part of the challenge
RUN useradd -m -s /usr/local/bin/hub-shell intern \
 && echo 'intern:ctf' | chpasswd \
 && install -d -o intern -g intern /var/ctf/state /home/intern/solutions

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
