#!/usr/bin/env bash
set -euo pipefail

/usr/local/bin/fvtt-sync-down.sh

# Write s3config.json for asset storage
cat > /opt/foundrydata/Config/s3config.json <<EOF
{
  "region": "${AWS_DEFAULT_REGION:-eu-north-1}",
  "credentials": {
    "accessKeyId": "${FVTT_S3_ACCESS_KEY_ID}",
    "secretAccessKey": "${FVTT_S3_SECRET_ACCESS_KEY}"
  }
}
EOF

# Patch options.json: strip cloud proxy settings, ensure awsConfig is set
OPTS=/opt/foundrydata/Config/options.json
node -e "
const fs = require('fs');
const o = fs.existsSync('$OPTS') ? JSON.parse(fs.readFileSync('$OPTS')) : {};
delete o.hostname; delete o.proxySSL; delete o.proxyPort;
o.awsConfig = 's3config.json';
o.telemetry = false;
fs.writeFileSync('$OPTS', JSON.stringify(o, null, 2));
"

exec node /opt/foundryvtt/resources/app/main.js --dataPath=/opt/foundrydata
