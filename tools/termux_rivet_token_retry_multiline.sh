#!/data/data/com.termux/files/usr/bin/bash
set +e

REPO="mehmetdem2005/colony-dominion-io"
WORKFLOW="deploy-rivet-control-staging.yml"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT_DIR="$HOME/colony-deployment-evidence/rivet-multiline-retry-$STAMP"
INPUT_FILE="$RESULT_DIR/rivet-token-input.txt"
RUN_ID=""
FINAL_STATUS=1

mkdir -p "$RESULT_DIR"

restore_tty() {
  stty echo 2>/dev/null || true
}

finish() {
  restore_tty
  rm -f "$INPUT_FILE"
  echo
  echo "============================================================"
  if [ "$FINAL_STATUS" -eq 0 ]; then
    echo "RIVET_RETRY_RESULT=SUCCESS"
  else
    echo "RIVET_RETRY_RESULT=FAILED"
  fi
  [ -n "$RUN_ID" ] && echo "RIVET_RUN_ID=$RUN_ID"
  echo "RESULT_DIR=$RESULT_DIR"
  echo "============================================================"
  echo "Termux kapanmayacak. Çıkmak için Enter tuşuna bas."
  read -r _
}
trap finish EXIT INT TERM

fail() {
  echo "HATA: $*" >&2
  return 1
}

latest_run_id() {
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

echo "===== RIVET ÇOK SATIRLI TOKEN KURTARMA ====="
echo

if ! gh auth status >/dev/null 2>&1; then
  fail "GitHub oturumu açık değil. Önce gh auth login çalıştır."
  exit 1
fi

cat <<'TEXT'
Rivet panelinden kopyaladığın metnin tamamını yapıştırabilirsin.
Tek token, RIVET_CLOUD_TOKEN=... satırı veya çok satırlı Connect metni kabul edilir.

1. Metni yapıştır.
2. Yeni bir satıra yalnızca BITTI yaz.
3. Enter'a bas.

Girdi ekranda görünmeyecek.
TEXT

echo
: > "$INPUT_FILE"
stty -echo 2>/dev/null || true
while IFS= read -r LINE; do
  LINE="${LINE//$'\r'/}"
  if [ "$LINE" = "BITTI" ]; then
    break
  fi
  printf '%s\n' "$LINE" >> "$INPUT_FILE"
done
restore_tty
echo
echo "Girdi alındı; token türü güvenli biçimde inceleniyor."

TOKEN="$({
  python - "$INPUT_FILE" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
items = list(dict.fromkeys(re.findall(r"cloud_api_[A-Za-z0-9._~+/=-]+", text)))
if len(items) == 1:
    sys.stdout.write(items[0])
PY
} 2>/dev/null)"

if [ -z "$TOKEN" ]; then
  PREFIX_INFO="$(python - "$INPUT_FILE" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
found = []
for prefix in ("sk_", "pk_", "cloud_api_"):
    if re.search(re.escape(prefix), text):
        found.append(prefix)
print(",".join(found))
PY
)"
  rm -f "$INPUT_FILE"

  echo
  if [[ "$PREFIX_INFO" == *"sk_"* ]] || [[ "$PREFIX_INFO" == *"pk_"* ]]; then
    fail "Yapıştırılan değer actor endpoint anahtarına benziyor ($PREFIX_INFO). Deployment için cloud_api_ ile başlayan RIVET_CLOUD_TOKEN gerekir."
  else
    fail "Metin içinde tek bir cloud_api_ deployment tokeni bulunamadı."
  fi
  echo "Rivet Dashboard > proje > Connect > Rivet Cloud bölümündeki RIVET_CLOUD_TOKEN değerini kullan."
  exit 1
fi

rm -f "$INPUT_FILE"

if [ "${#TOKEN}" -lt 24 ]; then
  unset TOKEN
  fail "Bulunan cloud_api_ tokeni beklenenden kısa."
  exit 1
fi

echo "Token türü doğrulandı: cloud_api_ deployment tokeni."
echo "Token karakter sayısı: ${#TOKEN}"

echo
echo "===== GITHUB SECRETS GÜNCELLENİYOR ====="
printf '%s' "$TOKEN" | gh secret set RIVET_CLOUD_TOKEN --repo "$REPO" --env staging
ENV_STATUS=$?
printf '%s' "$TOKEN" | gh secret set RIVET_CLOUD_TOKEN --repo "$REPO"
REPO_STATUS=$?
unset TOKEN

if [ "$ENV_STATUS" -ne 0 ] || [ "$REPO_STATUS" -ne 0 ]; then
  fail "RIVET_CLOUD_TOKEN GitHub'a kaydedilemedi. staging=$ENV_STATUS repository=$REPO_STATUS"
  exit 1
fi

echo "RIVET_CLOUD_TOKEN staging ve repository seviyesinde güncellendi."

BEFORE_ID="$(latest_run_id)"

echo
echo "===== RIVET STAGING DEPLOYMENT BAŞLATILIYOR ====="
gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref main \
  -f confirmation=DEPLOY-RIVET-STAGING

if [ "$?" -ne 0 ]; then
  fail "Rivet workflow başlatılamadı."
  exit 1
fi

for ATTEMPT in $(seq 1 60); do
  sleep 2
  CANDIDATE="$(latest_run_id)"
  if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "$BEFORE_ID" ]; then
    RUN_ID="$CANDIDATE"
    break
  fi
done

if [ -z "$RUN_ID" ]; then
  fail "Yeni Rivet workflow Run ID bulunamadı."
  exit 1
fi

echo "RIVET_RUN_ID=$RUN_ID"
echo
echo "===== CANLI GITHUB ACTIONS İLERLEMESİ ====="
gh run watch "$RUN_ID" --repo "$REPO" --exit-status
WATCH_STATUS=$?

gh run view "$RUN_ID" --repo "$REPO" > "$RESULT_DIR/run-summary.txt" 2>&1 || true

if [ "$WATCH_STATUS" -ne 0 ]; then
  echo
echo "===== BAŞARISIZ ADIM LOGU ====="
  gh run view "$RUN_ID" --repo "$REPO" --log-failed \
    | tee "$RESULT_DIR/failed.log" \
    | tail -n 300
  exit 1
fi

echo
echo "===== DEPLOYMENT RAPORU DOĞRULANIYOR ====="
ARTIFACT_DIR="$RESULT_DIR/artifact"
mkdir -p "$ARTIFACT_DIR"

for ATTEMPT in $(seq 1 8); do
  gh run download "$RUN_ID" \
    --repo "$REPO" \
    --name rivet-control-staging \
    --dir "$ARTIFACT_DIR" \
    >/dev/null 2>&1
  [ "$?" -eq 0 ] && break
  sleep 3
done

REPORT="$(find "$ARTIFACT_DIR" -type f -name deployment-report.json 2>/dev/null | head -n 1)"
if [ -z "$REPORT" ]; then
  fail "Workflow başarılı ancak deployment-report.json indirilemedi."
  exit 1
fi

jq -e '
  .environment == "staging" and
  .control_plane_live == true and
  .supabase_schema_ready == true and
  .min_players == 2 and
  .max_players == 10 and
  .game_server_allocator_ready == false and
  .full_online_ready == false
' "$REPORT" >/dev/null

if [ "$?" -ne 0 ]; then
  fail "Deployment raporu beklenen 10 oyunculu staging sözleşmesini karşılamıyor."
  jq . "$REPORT" || true
  exit 1
fi

CONTROL_URL="$(jq -r '.rivet_control_base_url // empty' "$REPORT")"

echo "RIVET_CONTROL_STAGING_READY=true"
echo "MAX_PLAYERS=10"
echo "RIVET_CONTROL_URL=$CONTROL_URL"
echo "GAME_SERVER_ALLOCATOR_READY=false"
echo "FULL_ONLINE_READY=false"

FINAL_STATUS=0
exit 0
