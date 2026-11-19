#!/usr/bin/env bash
set -euo pipefail

dnf install -y nginx

install -m 0644 /dev/stdin /usr/share/nginx/html/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Terraform EC2 Web Server</title>
</head>
<body>
  <h1>Terraform EC2 Web Server</h1>
  <p>This page is served by Nginx.</p>
</body>
</html>
HTML

systemctl enable --now nginx
