#!/bin/sh
# nginx:alpine runs /docker-entrypoint.d/*.sh before starting nginx. Regenerate
# the SPA's runtime config from container env so the deployment (not the image)
# carries the OIDC settings.
set -e
cat > /usr/share/nginx/html/config.js <<EOF
window.__APP_CONFIG__ = {
  oidcAuthority: "${OIDC_AUTHORITY:-}",
  oidcClientId: "${OIDC_CLIENT_ID:-lab-tracker}"
};
EOF
echo "rendered /config.js (oidcAuthority=${OIDC_AUTHORITY:-<unset>})"
