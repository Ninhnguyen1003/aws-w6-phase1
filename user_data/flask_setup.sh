#!/bin/bash
# EC2 user_data – install minimal Flask app on Amazon Linux 2023
set -euxo pipefail

exec > /var/log/user-data.log 2>&1

dnf install -y python3 python3-pip
pip3 install flask gunicorn

mkdir -p /opt/flask-app
cat > /opt/flask-app/app.py <<'PYEOF'
from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def index():
    return "<h1>W6 Flask App</h1><p>AWS Week 6 – ap-southeast-1</p>"


@app.route("/health")
def health():
    return jsonify(status="ok", service="w6-flask")
PYEOF

cat > /etc/systemd/system/flask.service <<'SVCEOF'
[Unit]
Description=W6 Flask application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/flask-app
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:80 --workers 1 app:app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable flask
systemctl start flask
