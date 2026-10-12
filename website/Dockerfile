# Builds the static site with Next, then serves out/ with nginx.
# Coolify: build pack Dockerfile, base directory /website, port 80.

# Stage 1: build the static export.
FROM node:22.20.0-alpine AS build
WORKDIR /app
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    NEXT_TELEMETRY_DISABLED=1
RUN corepack enable
COPY package.json yarn.lock .yarnrc.yml ./
RUN yarn install --immutable
COPY . .
RUN yarn build

# Stage 2: serve it.
FROM nginx:1.27.5-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/out /usr/share/nginx/html
EXPOSE 80
