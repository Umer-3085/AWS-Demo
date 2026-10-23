#!/bin/bash
dnf install -y httpd
systemctl enable --now httpd

cat > /usr/local/bin/sync-cv.sh <<'EOF'
#!/bin/bash
BUCKET="cv-23l-3085"
CACHE=/opt/cv-site
WEB=/var/www/html
LOG=/var/log/cv-sync.log

TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

mkdir -p "$CACHE"
if aws s3 sync "s3://$BUCKET/site/" "$CACHE/" --delete \
   && cp -r "$CACHE"/. "$WEB"/ \
   && sed -i "s/{{HOSTED_ON}}/EC2 $ID/g" "$WEB/index.html"; then
  echo "$(date -Is) sync OK" >> "$LOG"
else
  echo "$(date -Is) sync FAILED" >> "$LOG"
fi
EOF
chmod +x /usr/local/bin/sync-cv.sh

cat > /etc/systemd/system/cv-sync.service <<'EOF'
[Unit]
Description=Sync CV from S3
[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-cv.sh
EOF

cat > /etc/systemd/system/cv-sync.timer <<'EOF'
[Unit]
Description=Run CV sync every 2 minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now cv-sync.timer
/usr/local/bin/sync-cv.sh