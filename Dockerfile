FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG CLAWDBOT_DOCKER_APT_PACKAGES=""
RUN if [ -n "$CLAWDBOT_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $CLAWDBOT_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY package.json pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install

COPY . .

# extensions/composio excluded from workspace (moltbot peer dep not on npm), install separately
RUN cd extensions/composio && pnpm install --ignore-workspace

RUN CLAWDBOT_A2UI_SKIP_MISSING=1 pnpm build
ENV CLAWDBOT_PREFER_PNPM=1
RUN pnpm ui:install
RUN pnpm ui:build

ENV NODE_ENV=production

# State dir = persistent volume mount point
ENV CLAWDBOT_STATE_DIR=/home/node/.openclaw

# Runs as root so the startup script can write to the existing root-owned volume.
# Secrets via env vars: CLAWDBOT_OPENROUTER_API_KEY and OPENCLAW_GATEWAY_TOKEN.
CMD ["/bin/sh", "-c", \
  "if [ ! -f $CLAWDBOT_STATE_DIR/moltbot.json ]; then \
     node /app/dist/index.js onboard \
       --non-interactive --accept-risk \
       --auth-choice openrouter-api-key \
       --openrouter-api-key $CLAWDBOT_OPENROUTER_API_KEY \
       --gateway-token $OPENCLAW_GATEWAY_TOKEN \
       --skip-channels --skip-skills --skip-daemon --skip-health; \
   fi && \
   node /app/dist/index.js gateway"]
