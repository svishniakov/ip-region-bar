#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONTH="${DBIP_MONTH:-$(date +%Y-%m)}"
URL="https://download.db-ip.com/free/dbip-city-lite-${MONTH}.mmdb.gz"
DEST_DB="${ROOT_DIR}/IPRegionBar/Resources/dbip-city-lite.mmdb"
DEST_META="${ROOT_DIR}/IPRegionBar/Resources/dbip-city-lite.meta.json"
TMP_GZ="$(mktemp -t dbip-city-lite.XXXXXX).mmdb.gz"
TMP_MMDB="${TMP_GZ%.gz}"

cleanup() {
  rm -f "${TMP_GZ}" "${TMP_MMDB}"
}
trap cleanup EXIT

echo "Downloading DB-IP Lite for ${MONTH}..."
curl -fL "${URL}" -o "${TMP_GZ}"
gunzip -f "${TMP_GZ}"

mkdir -p "$(dirname "${DEST_DB}")"
mv "${TMP_MMDB}" "${DEST_DB}"

cat > "${DEST_META}" <<JSON
{"month":"${MONTH}","source":"DB-IP.com"}
JSON

echo "Updated: ${DEST_DB}"
echo "Metadata: ${DEST_META}"
