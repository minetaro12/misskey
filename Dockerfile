ARG NODE_VERSION=18.13.0-bullseye

FROM node:${NODE_VERSION} AS builder

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
	build-essential

RUN corepack enable

WORKDIR /misskey

COPY ["pnpm-lock.yaml", "pnpm-workspace.yaml", "package.json", "./"]
COPY ["scripts", "./scripts"]
COPY ["packages/backend/package.json", "./packages/backend/"]
COPY ["packages/frontend/package.json", "./packages/frontend/"]
COPY ["packages/sw/package.json", "./packages/sw/"]

RUN pnpm i --frozen-lockfile

COPY . ./

WORKDIR /

RUN wget -O - https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2 | tar -xj && \
  cd /jemalloc-5.3.0 && \
  ./configure && \
  make -j2

WORKDIR /misskey
ARG NODE_ENV=production

RUN git submodule update --init
RUN pnpm build

FROM node:${NODE_VERSION}-slim AS runner

ARG UID="991"
ARG GID="991"

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
	ffmpeg tini \
	&& apt-get -y clean \
	&& rm -rf /var/lib/apt/lists/* \
	&& corepack enable \
	&& groupadd -g "${GID}" misskey \
	&& useradd -l -u "${UID}" -g "${GID}" -m -d /misskey misskey

USER misskey
WORKDIR /misskey

COPY --chown=misskey:misskey --from=builder /misskey/node_modules ./node_modules
COPY --chown=misskey:misskey --from=builder /misskey/built ./built
COPY --chown=misskey:misskey --from=builder /misskey/packages/backend/node_modules ./packages/backend/node_modules
COPY --chown=misskey:misskey --from=builder /misskey/packages/backend/built ./packages/backend/built
COPY --chown=misskey:misskey --from=builder /misskey/packages/frontend/node_modules ./packages/frontend/node_modules
COPY --chown=misskey:misskey --from=builder /misskey/fluent-emojis /misskey/fluent-emojis
COPY --from=builder /jemalloc-5.3.0/lib/libjemalloc.so.2 /usr/local/lib/
COPY --chown=misskey:misskey . ./

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so.2

ENV NODE_ENV=production
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["pnpm", "run", "migrateandstart"]
