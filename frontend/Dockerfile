# Build the Vite SPA, then serve it with nginx (which also proxies /api -> backend).
FROM node:24-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
# Baked into the bundle (__APP_VERSION__) and shown in the footer. Set after
# `npm ci` so a version change doesn't bust the dependency-install cache layer.
ARG APP_VERSION=dev
ENV VITE_APP_VERSION=$APP_VERSION
COPY . .
RUN npm run build

FROM nginx:1.31-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
# Renders /config.js from env (OIDC_AUTHORITY, OIDC_CLIENT_ID) at container start.
COPY --chmod=0755 docker-entrypoint.d/40-render-config.sh /docker-entrypoint.d/40-render-config.sh
EXPOSE 80
