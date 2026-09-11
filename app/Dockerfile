# syntax=docker/dockerfile:1

FROM node:20.18.1-alpine3.20 AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev --no-audit --no-fund

FROM node:20.18.1-alpine3.20 AS runtime
WORKDIR /app
ENV NODE_ENV=production

# The base image ships npm/npx/corepack (with their own vendored
# dependencies - tar, minimatch, pacote, sigstore, etc.) for build-time
# use. We only need the `node` binary at runtime, so drop them: smaller
# image, and it stops Trivy from reporting CVEs in tooling this container
# never executes.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack

COPY --from=deps /app/node_modules ./node_modules
COPY src ./src
COPY package.json ./

# Official node images already ship a non-root "node" user - use it instead
# of running as root.
USER node

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:8080/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "src/server.js"]
