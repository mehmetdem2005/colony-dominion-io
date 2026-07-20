#!/data/data/com.termux/files/usr/bin/bash
set +e

REPO="mehmetdem2005/colony-dominion-io"
WORKFLOW="deploy-rivet-control-staging.yml"
API_URL="https://cloud-api.rivet.dev/tokens/api/inspect"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="$HOME/colony-deployment-evidence/rivet-authoritative-probe-$STAMP"
BODY_FILE="$REPORT_DIR/inspect-body.json"
CURL_ERR="$REPORT_DIR/curl-error.txt"
REPORT_FILE="$REPORT_DIR/report.txt"
RUN_ID=""
FINAL_STATUS=1

mkdir -p "$REPORT_DIR"

finish() {
  unset TOKEN RAW_INPUT
  echo
  echo "============================================================"
  [ "$FINAL_STATUS" -eq 0 ] && echo "RIVET_DIAG_RESULT=SUCCESS" || echo "RIVET_DIAG_RESULT=FAILED"
  [ -n "$RUN_ID" ] && echo "RIVET_RUN_ID=$RUN_ID"
  echo "REPORT_DIR=$REPORT_DIR"
  echo "============================================================"
  echo "Termux kapanmayacak. Çıkmak için Enter tuşuna bas."
  read -r _
}
trap finish EXIT INT TERM

fail() {
  echo "HATA: $*" | tee -a "$REPORT_FILE" >&2
  return 1
}

latest_dispatch_id() {
  gh run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW" \
    --branch main \
    --event workflow_dispatch \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty' \
    2>/dev/null
}

echo "===== RIVET NOKTA ATIŞI TANILAMA =====" | tee "$REPORT_FILE"

echo "Gerekli araçlar kontrol ediliyor..."
pkg install -y curl python gh jq >/dev/null 2>&1
if [ "$?" -ne 0 ]; then
  fail "Termux araçları kurulamadı"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  fail "GitHub oturumu açık değil. gh auth login çalıştır."
  exit 1
fi

echo
echo "Rivet panelinden aldığın tokeni veya tam 'npx ... --token ...' komutunu yapıştır."
echo "Girdi ekranda görünmeyecek. Ön ek şartı uygulanmayacak."
printf "Token veya komut: "
IFS= read -r -s RAW_INPUT
echo

TOKEN="$(printf '%s' "$RAW_INPUT" | python -c '
import re, shlex, sys
raw = sys.stdin.read().strip().replace("\r", "")
token = ""
try:
    parts = shlex.split(raw)
except ValueError:
    parts = []
if "--token" in parts:
    i = parts.index("--token")
    if i + 1 < len(parts):
        token = parts[i + 1].strip()
if not token:
    m = re.match(r"^(?:export\s+)?RIVET_CLOUD_TOKEN\s*=\s*(.+)$", raw)
    if m:
        token = m.group(1).strip()
if not token and raw and not any(ch.isspace() for ch in raw):
    token = raw
if len(token) >= 16 and not any(ch.isspace() for ch in token):
    sys.stdout.write(token)
')"
unset RAW_INPUT

if [ -z "$TOKEN" ]; then
  fail "Token alınamadı veya yapıştırılan metin çok satırlı"
  exit 1
fi

TOKEN_LENGTH="${#TOKEN}"
TOKEN_FAMILY="opaque"
case "$TOKEN" in
  cloud_api_*) TOKEN_FAMILY="cloud_api" ;;
  cloud.*) TOKEN_FAMILY="cloud_prefixed" ;;
esac
TOKEN_FP="$(printf '%s' "$TOKEN" | sha256sum | awk '{print substr($1,1,12)}')"

echo "TOKEN_PRESENT=true" | tee -a "$REPORT_FILE"
echo "TOKEN_LENGTH=$TOKEN_LENGTH" | tee -a "$REPORT_FILE"
echo "TOKEN_FAMILY=$TOKEN_FAMILY" | tee -a "$REPORT_FILE"
echo "TOKEN_FINGERPRINT_SHA256_12=$TOKEN_FP" | tee -a "$REPORT_FILE"

echo
echo "===== DNS KONTROLÜ =====" | tee -a "$REPORT_FILE"
python - <<'PY' | tee -a "$REPORT_FILE"
import socket
host = "cloud-api.rivet.dev"
try:
    addrs = sorted({item[4][0] for item in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)})
    print("DNS_OK=true")
    print("DNS_ADDRESSES=" + ",".join(addrs))
except Exception as exc:
    print("DNS_OK=false")
    print("DNS_ERROR=" + type(exc).__name__ + ":" + str(exc))
PY

echo
echo "===== RIVET CLOUD API YETKİ TESTİ =====" | tee -a "$REPORT_FILE"
HTTP_META="$(curl \
  --silent \
  --show-error \
  --connect-timeout 10 \
  --max-time 30 \
  --request GET \
  --header "Authorization: Bearer $TOKEN" \
  --header "Accept: application/json" \
  --output "$BODY_FILE" \
  --write-out '%{http_code}|%{remote_ip}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_total}|%{ssl_verify_result}' \
  "$API_URL" \
  2>"$CURL_ERR")"
CURL_STATUS=$?

IFS='|' read -r HTTP_CODE REMOTE_IP T_DNS T_CONNECT T_TLS T_TOTAL SSL_VERIFY <<< "$HTTP_META"

echo "CURL_EXIT=$CURL_STATUS" | tee -a "$REPORT_FILE"
echo "HTTP_CODE=${HTTP_CODE:-000}" | tee -a "$REPORT_FILE"
echo "REMOTE_IP=${REMOTE_IP:-unknown}" | tee -a "$REPORT_FILE"
echo "TIME_DNS=${T_DNS:-unknown}" | tee -a "$REPORT_FILE"
echo "TIME_CONNECT=${T_CONNECT:-unknown}" | tee -a "$REPORT_FILE"
echo "TIME_TLS=${T_TLS:-unknown}" | tee -a "$REPORT_FILE"
echo "TIME_TOTAL=${T_TOTAL:-unknown}" | tee -a "$REPORT_FILE"
echo "SSL_VERIFY_RESULT=${SSL_VERIFY:-unknown}" | tee -a "$REPORT_FILE"

if [ -s "$CURL_ERR" ]; then
  sed -E 's/(Bearer )[A-Za-z0-9._~+\/=:-]+/\1***/g' "$CURL_ERR" | tee -a "$REPORT_FILE"
fi

SAFE_BODY="$(python - "$BODY_FILE" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    raise SystemExit(0)
raw = p.read_text(encoding="utf-8", errors="replace")
try:
    data = json.loads(raw)
except Exception:
    print(raw[:500])
    raise SystemExit(0)
allowed = {}
for key in ("message", "project", "organization"):
    if key in data:
        allowed[key] = data[key]
print(json.dumps(allowed, ensure_ascii=False, sort_keys=True))
PY
)"
[ -n "$SAFE_BODY" ] && echo "SAFE_RESPONSE=$SAFE_BODY" | tee -a "$REPORT_FILE"

if [ "$CURL_STATUS" -ne 0 ]; then
  fail "Rivet API'ye ağ/TLS seviyesinde ulaşılamadı"
  exit 1
fi

case "$HTTP_CODE" in
  200)
    echo "AUTH_RESULT=VALID" | tee -a "$REPORT_FILE"
    ;;
  401)
    echo "AUTH_RESULT=REJECTED_401" | tee -a "$REPORT_FILE"
    fail "Token, Rivet CLI'nin kullandığı gerçek /tokens/api/inspect endpoint'i tarafından reddedildi"
    exit 1
    ;;
  403)
    echo "AUTH_RESULT=VALID_BUT_FORBIDDEN" | tee -a "$REPORT_FILE"
    fail "Token tanındı ancak Cloud API yetkisi yetersiz"
    exit 1
    ;;
  *)
    echo "AUTH_RESULT=UNEXPECTED_HTTP_$HTTP_CODE" | tee -a "$REPORT_FILE"
    fail "Rivet API beklenmeyen HTTP kodu döndürdü: $HTTP_CODE"
    exit 1
    ;;
esac

echo
echo "===== GITHUB SECRET AKTARIMI =====" | tee -a "$REPORT_FILE"
printf '%s' "$TOKEN" | gh secret set RIVET_CLOUD_TOKEN --repo "$REPO" --env staging
ENV_STATUS=$?
printf '%s' "$TOKEN" | gh secret set RIVET_CLOUD_TOKEN --repo "$REPO"
REPO_STATUS=$?
unset TOKEN

echo "STAGING_SECRET_SET_EXIT=$ENV_STATUS" | tee -a "$REPORT_FILE"
echo "REPOSITORY_SECRET_SET_EXIT=$REPO_STATUS" | tee -a "$REPORT_FILE"

if [ "$ENV_STATUS" -ne 0 ] || [ "$REPO_STATUS" -ne 0 ]; then
  fail "GitHub secret aktarımı başarısız"
  exit 1
fi

BEFORE_ID="$(latest_dispatch_id)"

echo
echo "===== RIVET DEPLOYMENT =====" | tee -a "$REPORT_FILE"
gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref main \
  -f confirmation=DEPLOY-RIVET-STAGING
if [ "$?" -ne 0 ]; then
  fail "GitHub Actions workflow başlatılamadı"
  exit 1
fi

for _ in $(seq 1 60); do
  sleep 2
  CURRENT_ID="$(latest_dispatch_id)"
  if [ -n "$CURRENT_ID" ] && [ "$CURRENT_ID" != "$BEFORE_ID" ]; then
    RUN_ID="$CURRENT_ID"
    break
  fi
done

if [ -z "$RUN_ID" ]; then
  fail "Yeni workflow Run ID bulunamadı"
  exit 1
fi

echo "RIVET_RUN_ID=$RUN_ID" | tee -a "$REPORT_FILE"
gh run watch "$RUN_ID" --repo "$REPO" --exit-status
WATCH_STATUS=$?

gh run view "$RUN_ID" --repo "$REPO" > "$REPORT_DIR/run-summary.txt" 2>&1 || true

if [ "$WATCH_STATUS" -ne 0 ]; then
  gh run view "$RUN_ID" --repo "$REPO" --log-failed \
    | tee "$REPORT_DIR/failed.log" \
    | tail -n 300
  fail "Token API testinden geçti ancak deployment daha sonraki bir adımda başarısız oldu"
  exit 1
fi

echo "RIVET_CONTROL_STAGING_READY=true" | tee -a "$REPORT_FILE"
echo "MAX_PLAYERS=10" | tee -a "$REPORT_FILE"
FINAL_STATUS=0
exit 0
