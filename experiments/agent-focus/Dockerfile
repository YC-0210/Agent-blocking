FROM node:22.18.0-bookworm-slim

WORKDIR /app
COPY package.json package-lock.json ./
# The relay needs no browser bundle or development dependencies.
RUN npm ci --omit=dev --ignore-scripts
COPY src ./src

ENV NODE_ENV=production HOST=0.0.0.0 DO_CARD_DATABASE=/data/agent-focus.sqlite
CMD ["node", "src/relay-main.mjs"]
