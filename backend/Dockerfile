# Builds the backend as a plain Node.js server (see src/server.ts).
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# The build is a single bundled file, so the runtime image needs no node_modules.
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=8080 USAGE_FILE=/data/usage.json
COPY --from=build /app/dist/server.js ./server.js
# Daily usage counts live here; mount a volume so they survive redeploys.
RUN mkdir -p /data && chown node:node /data
VOLUME /data
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/health || exit 1
CMD ["node", "server.js"]
