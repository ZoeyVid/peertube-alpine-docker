# syntax=docker/dockerfile:labs
FROM --platform="$BUILDPLATFORM" alpine:3.20.1 AS build
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
ARG PT_VERSION=v6.1.0 \
    TARGETARCH

RUN apk upgrade --no-cache -a && \
    apk add --no-cache ca-certificates bash git nodejs yarn npm python3 file && \
    yarn global add clean-modules && \
    git clone --recursive https://github.com/Chocobozzz/PeerTube --branch "$PT_VERSION" /app && \
    sed -i "s|gosu|su-exec|g" /app/support/docker/production/entrypoint.sh && \
    chmod +x /app/support/docker/production/entrypoint.sh && \
    if [ "$TARGETARCH" = "amd64" ]; then \
      cd /app/client && \
        npm_config_target_platform=linux npm_config_target_arch=x64 yarn install --pure-lockfile && \
      cd /app && \
        npm_config_target_platform=linux npm_config_target_arch=x64 yarn install --pure-lockfile && \
        npm_config_target_platform=linux npm_config_target_arch=x64 npm run build && \
        rm -r /app/client/.angular /app/client/node_modules /app/node_modules && \
        npm_config_target_platform=linux npm_config_target_arch=x64 yarn install --pure-lockfile --production && \
        for file in $(find /app/node_modules -name "*.node" -type f -exec file {} \; | grep -v "x86-64\|x86_64" | grep "aarch64\|arm64" | sed "s|\([^:]\):.*|\1|g"); do rm -v "$file"; done; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
      cd /app/client && \
        npm_config_target_platform=linux npm_config_target_arch=arm64 yarn install --pure-lockfile && \
      cd /app && \
        npm_config_target_platform=linux npm_config_target_arch=arm64 yarn install --pure-lockfile && \
        npm_config_target_platform=linux npm_config_target_arch=arm64 npm run build && \
        rm -r /app/client/.angular /app/client/node_modules /app/node_modules && \
        npm_config_target_platform=linux npm_config_target_arch=arm64 yarn install --pure-lockfile --production && \
        for file in $(find /app/node_modules -name "*.node" -type f -exec file {} \; | grep -v "aarch64\|arm64" | grep "x86-64\|x86_64" | sed "s|\([^:]\):.*|\1|g"); do rm -v "$file"; done; \
    fi && \
    yarn cache clean --all && \
    clean-modules --yes
FROM alpine:3.20.1 AS strip
COPY --from=build /app /app
RUN apk upgrade --no-cache -a && \
    apk add --no-cache ca-certificates binutils file && \
    find /app/node_modules -name "*.node" -type f -exec strip -s {} \; && \
    find /app/node_modules -name "*.node" -type f -exec file {} \;

FROM alpine:3.20.1
COPY --chown=1000:1000 --from=strip /app /app
WORKDIR /app
RUN apk add --no-cache ca-certificates tzdata tini su-exec nodejs yarn ffmpeg shadow && \
    groupadd -r peertube && \
    useradd -r -g peertube -m peertube && \
    mv -v /app/support/docker/production/entrypoint.sh /usr/local/bin/entrypoint.sh && \
    mkdir /data /config && \
    chown peertube:peertube /app /data /config && \
    apk del --no-cache shadow

ENV NODE_ENV=production
ENV NODE_CONFIG_DIR=/app/config:/app/support/docker/production/config:/config
ENV PEERTUBE_LOCAL_CONFIG=/config

ENTRYPOINT ["tini", "--", "entrypoint.sh"]
CMD ["node", "dist/server"]
EXPOSE 9000/tcp
EXPOSE 1935/tcp
