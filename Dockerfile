# syntax=docker/dockerfile:labs
FROM --platform="$BUILDPLATFORM" alpine:3.19.1 as build
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
ARG PT_VERSION=v6.1.0 \
    TARGETARCH

RUN apk upgrade --no-cache -a && \
    apk add --no-cache ca-certificates bash nodejs yarn npm git && \
    yarn global add clean-modules && \
    git clone --recursive https://github.com/Chocobozzz/PeerTube --branch "$PT_VERSION" /app && \
    sed -i "s|gosu|su-exec|g" /app/support/docker/production/entrypoint.sh && \
    if [ "$TARGETARCH" = "amd64" ]; then \
      cd /app/client && \
        npm_config_target_platform=linux npm_config_target_arch=x64 yarn install --no-lockfile && \
        clean-modules --yes && \
      cd /app && \
        npm_config_target_platform=linux npm_config_target_arch=x64 yarn install --no-lockfile && \
        clean-modules --yes && \
        npm_config_target_platform=linux npm_config_target_arch=x64 npm run build && \
        clean-modules --yes && \
        rm -r /app/client/.angular /app/client/node_modules /app/node_modules && \
        npm_config_target_platform=linux npm_config_target_arch=x64 yarn install --no-lockfile --production && \
        clean-modules --yes; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
      cd /app/client && \
        npm_config_target_platform=linux npm_config_target_arch=arm64 yarn install --no-lockfile && \
        clean-modules --yes && \
      cd /app && \
        npm_config_target_platform=linux npm_config_target_arch=arm64 yarn install --no-lockfile && \
        clean-modules --yes && \
        npm_config_target_platform=linux npm_config_target_arch=arm64 npm run build && \
        clean-modules --yes && \
        rm -r /app/client/.angular /app/client/node_modules /app/node_modules && \
        npm_config_target_platform=linux npm_config_target_arch=arm64 yarn install --no-lockfile --production && \
        clean-modules --yes; \
    fi && \
    yarn cache clean --all

FROM alpine:3.19.1
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
COPY --from=build /app /app
WORKDIR /app

# Install dependencies
RUN apk add --no-cache ca-certificates tzdata tini ffmpeg su-exec shadow nodejs && \
# Add peertube user
    groupadd -r peertube && \
    useradd -r -g peertube -m peertube && \
# script, folder, permissions and cleanup
    mv /app/support/docker/production/entrypoint.sh /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/entrypoint.sh && \
    mkdir /data /config && \
    chown -R peertube:peertube /app /data /config && \
    apk del --no-cache shadow

ENV NODE_ENV=production
ENV NODE_CONFIG_DIR=/app/config:/app/support/docker/production/config:/config
ENV PEERTUBE_LOCAL_CONFIG=/config

ENTRYPOINT ["tini", "--", "entrypoint.sh"]
CMD ["node", "dist/server"]
