#!/bin/sh
set -e

# ===== Required ENV =====
if [ -z "$UUID" ]; then
  echo "❌ UUID"
  exit 1
fi

PORT=${PORT:-7860}
WSPATH=${WSPATH:-/api/v1/aichatbot}

echo "Starting with:"
echo "PORT=${PORT}"
echo "WSPATH=${WSPATH}"

# ===== Create Xray Config =====
cat > /etc/xray/config.json << EOF
{
  "log": {
    "access": "none",
    "error": "none",
    "loglevel": "none"
  },
  "inbounds": [{
    "port": 9000,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${UUID}" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "${WSPATH}" }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

echo "✅ Xray config created"

# ===== Create nginx temp directories =====
mkdir -p \
  /tmp/nginx/client_body \
  /tmp/nginx/proxy \
  /tmp/nginx/fastcgi \
  /tmp/nginx/uwsgi \
  /tmp/nginx/scgi

chown -R xray:xray /tmp/nginx

# ===== Generate nginx config =====
cat > /tmp/nginx.conf << EOF
pid /tmp/nginx.pid;

events { worker_connections 1024; }

http {
    client_body_temp_path /tmp/nginx/client_body 1 2;
    proxy_temp_path       /tmp/nginx/proxy;
    fastcgi_temp_path     /tmp/nginx/fastcgi;
    uwsgi_temp_path       /tmp/nginx/uwsgi;
    scgi_temp_path        /tmp/nginx/scgi;

    server {
        listen ${PORT} default_server;
        server_name _;

        access_log /var/log/nginx/access.log;
        error_log  /var/log/nginx/error.log warn;

        location / {
            root /www;
            index index.html;
            try_files \$uri \$uri/ =404;
        }

        location ${WSPATH} {
            proxy_pass http://127.0.0.1:9000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 86400;
        }
    }
}
EOF

echo "✅ nginx.conf created"
grep "listen" /tmp/nginx.conf
grep "location" /tmp/nginx.conf

# ===== Start Xray =====
ai-core run -config /etc/xray/config.json &

# ===== Start nginx (foreground) =====
exec nginx -c /tmp/nginx.conf -g "daemon off;"
