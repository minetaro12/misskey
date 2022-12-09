FROM node:18.12.1-bullseye AS builder

ARG NODE_ENV=production

WORKDIR /misskey

COPY . ./

RUN apt-get update && \
  apt-get install -y build-essential && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  cd / && \
  wget -O - https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2 | tar -xj && \
  cd /jemalloc-5.3.0 && \
  ./configure && \
  make -j2 && \
  cd /misskey && \
	git submodule update --init && \
	yarn install --immutable && \
	yarn build && \
  rm -rf .git

FROM node:18.12.1-bullseye-slim AS runner

WORKDIR /misskey

RUN apt-get update && \
  apt-get install -y ffmpeg tini && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

COPY --from=builder /misskey/.yarn/install-state.gz ./.yarn/install-state.gz
COPY --from=builder /misskey/node_modules ./node_modules
COPY --from=builder /misskey/built ./built
COPY --from=builder /misskey/packages/backend/node_modules ./packages/backend/node_modules
COPY --from=builder /misskey/packages/backend/built ./packages/backend/built
COPY --from=builder /misskey/packages/client/node_modules ./packages/client/node_modules
COPY --from=builder /jemalloc-5.3.0/lib/libjemalloc.so.2 /usr/local/lib/
COPY . ./

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so.2

ENV NODE_ENV=production
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["yarn", "run", "migrateandstart"]
