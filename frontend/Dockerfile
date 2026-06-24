# Build the Vite SPA, then serve it with nginx (which also proxies /api -> backend).
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
# Renders /config.js from env (OIDC_AUTHORITY, OIDC_CLIENT_ID) at container start.
COPY --chmod=0755 docker-entrypoint.d/40-render-config.sh /docker-entrypoint.d/40-render-config.sh
EXPOSE 80
