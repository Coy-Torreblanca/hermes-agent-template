FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ARG HERMES_REF=main

# Added 'supervisor' and 'syncthing' to the apt-get list
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl ca-certificates git tini supervisor syncthing unzip gettext-base && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Bun (required for GBrain)
RUN curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun

# [Existing Hermes Build Steps...]
RUN git clone --depth 1 --branch ${HERMES_REF} https://github.com/Coy-Torreblanca/hermes-agent.git /opt/hermes-agent && \
    cd /opt/hermes-agent && \
    uv pip install --system --no-cache -e ".[all]" && \
    cd /opt/hermes-agent/web && \
    npm install --silent && \
    npm run build && \
    cd /opt/hermes-agent/ui-tui && \
    npm install --silent --no-fund --no-audit --progress=false && \
    npm run build && \
    rm -rf /opt/hermes-agent/web /root/.npm

# Install GBrain
RUN git clone https://github.com/garrytan/gbrain.git /opt/gbrain && \
    cd /opt/gbrain && \
    bun install && \
    bun link

COPY requirements.txt /app/requirements.txt
RUN uv pip install --system --no-cache -r /app/requirements.txt

# Create directories for Hermes and Syncthing
# We'll use /data/syncthing for the Syncthing config and database
RUN mkdir -p /data/.hermes /data/syncthing /data/.gbrain /etc/supervisor/conf.d

COPY server.py /app/server.py
COPY templates/ /app/templates/
COPY hermes_start.sh /app/hermes_start.sh
COPY syncthing_config.sh /app/syncthing_config.sh
COPY gbrain_start.sh /app/gbrain_start.sh
COPY gbrain_sync.sh /app/gbrain_sync.sh
COPY gbrain_dream.sh /app/gbrain_dream.sh
COPY gbrain_check_update.sh /app/gbrain_check_update.sh
COPY gbrain_check_update_loop.sh /app/gbrain_check_update_loop.sh
COPY gbrain_weekly.sh /app/gbrain_weekly.sh
COPY gbrain_weekly_loop.sh /app/gbrain_weekly_loop.sh
COPY gbrain_dream_loop.sh /app/gbrain_dream_loop.sh
COPY gbrain_mcp.sh /app/gbrain_mcp.sh
COPY hermes_setup/ /app/hermes_setup/

# Create the supervisor config file
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chmod +x /app/hermes_start.sh /app/syncthing_config.sh /app/gbrain_start.sh /app/gbrain_sync.sh /app/gbrain_dream.sh /app/gbrain_weekly.sh /app/gbrain_weekly_loop.sh /app/gbrain_dream_loop.sh /app/gbrain_mcp.sh /app/hermes_setup/*

ENV HOME=/data
ENV PATH="/root/.bun/bin:$PATH"
ENV HERMES_HOME=/data/.hermes
ENV GBRAIN_HOME=/data/.gbrain

# Tini still acts as PID 1, but now it reaps Supervisor
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
