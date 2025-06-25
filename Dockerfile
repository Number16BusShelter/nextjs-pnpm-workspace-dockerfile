# -------------------------------------------------------- #
# 0. Build Arguments
# -------------------------------------------------------- #

ARG NODE_VERSION=20.18
ARG PNPM_VERSION=10.10
ARG SERVICE=example-service
ARG PNPM_HOME="/pnpm"
ARG PATH="${PNPM_HOME}:${PATH}"
ARG PNPM_STORE="/pnpm/store"
ARG APP_PORT=3000

ARG NODE_ENV
ARG USE_CDN
ARG UPLOAD_ENV

# -------------------------------------------------------- #
# 1. Base system environment
# -------------------------------------------------------- #
FROM node:${NODE_VERSION}-alpine AS core-os
LABEL stage=core
RUN apk update
RUN apk add --no-cache libc6-compat curl

# -------------------------------------------------------- #
# 2. Core tooling setup (Turbo, PNPM, etc.)
# -------------------------------------------------------- #
FROM core-os as base
ARG PNPM_STORE
ARG SERVICE
LABEL builder=true

RUN npm install -g corepack@latest
RUN corepack enable && corepack prepare pnpm@${PNPM_VERSION} --activate
RUN npm install -g turbo cross-env

RUN --mount=type=cache,id=pnpm,target=${PNPM_STORE} pnpm config set store-dir ${PNPM_STORE}
RUN turbo telemetry disable

# -------------------------------------------------------- #
# 3. Prune unused packages
# -------------------------------------------------------- #
FROM base AS pruner
ARG SERVICE
LABEL stage=builder

WORKDIR /app
COPY . .

RUN turbo prune --scope=@your-org/${SERVICE} --docker

# -------------------------------------------------------- #
# 4. Build application
# -------------------------------------------------------- #
FROM base AS build
ARG SERVICE
LABEL stage=builder

ARG NODE_ENV
ARG USE_CDN
ARG UPLOAD_ENV

WORKDIR /app

ENV CI=true
ENV NEXT_TELEMETRY_DISABLED=1
ENV SLS_TELEMETRY_DISABLED=1
ENV SLS_NOTIFICATIONS_MODE=off

COPY --from=pruner /app/tsconfig.base.json ./
COPY --from=pruner /app/out/pnpm-lock.yaml ./
COPY --from=pruner /app/out/pnpm-workspace.yaml ./
COPY --from=pruner /app/out/json/ .

RUN --mount=type=cache,id=pnpm,target=${PNPM_STORE} \
    pnpm install --frozen-lockfile

COPY --from=pruner /app/out/full/ .

RUN printf '%s\n' \
  "NODE_ENV=production" \
  "USE_CDN=${USE_CDN}" \
  "UPLOAD_ENV=${UPLOAD_ENV}" \
  > ./services/${SERVICE}/.env.production

RUN pnpm run build --filter=./services/${SERVICE}
RUN pnpm --filter=./services/${SERVICE} run upload-assets

RUN rm ./services/${SERVICE}/.env.production

# -------------------------------------------------------- #
# 5. Extract prod dependencies
# -------------------------------------------------------- #
FROM build AS dependencies
ARG SERVICE
LABEL stage=builder
WORKDIR /app

RUN pnpm --filter=./services/${SERVICE} deploy --legacy --prod --ignore-scripts --no-optional /dependencies \
    && pnpm prune --prod --no-optional

# -------------------------------------------------------- #
# 6. Runtime container
# -------------------------------------------------------- #
FROM core-os AS runner
ARG SERVICE
ARG APP_PORT
LABEL stage=runner

ENV NODE_ENV=production
ENV PORT=${APP_PORT:-3000}

WORKDIR /app

COPY --from=build --chown=nextjs:nodejs /app/services/${SERVICE}/.next/standalone/services/${SERVICE} ./
COPY --from=build --chown=nextjs:nodejs /app/services/${SERVICE}/.next/static ./.next/static
COPY --from=build --chown=nextjs:nodejs /app/services/${SERVICE}/public ./public
COPY --from=dependencies --chown=remix:nodejs /dependencies/node_modules/ ./node_modules/

# Ensure writable .next/cache
RUN mkdir -p .next/cache && chown -R 1001:1001 .next
RUN mkdir -p .next/cache/fetch-cache && chown -R 1001:1001 .next

RUN apk del curl gcc make python3 g++ || true \
  && rm -rf /usr/lib/node_modules/npm /usr/local/lib/node_modules/npm ~/.npm

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
USER nextjs

CMD ["node", "./server.js"]
EXPOSE ${APP_PORT:-3000}
