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
RUN CLAWDBOT_A2UI_SKIP_MISSING=1 pnpm build
ENV CLAWDBOT_PREFER_PNPM=1
RUN pnpm ui:install
RUN pnpm ui:build

ENV NODE_ENV=production

# State dir = persistent volume mount point; create with node ownership
# so Docker initializes new volumes with correct permissions
RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node/.openclaw
ENV CLAWDBOT_STATE_DIR=/home/node/.openclaw

USER node

# Startup: run onboard on first launch (no moltbot.json), then start gateway.
# Pass secrets via env vars: CLAWDBOT_OPENROUTER_API_KEY and OPENCLAW_GATEWAY_TOKEN.
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
