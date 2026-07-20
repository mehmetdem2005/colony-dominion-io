#!/data/data/com.termux/files/usr/bin/bash
set +e

REPO="mehmetdem2005/colony-dominion-io"
WORKFLOW="deploy-rivet-control-staging.yml"
RUN_ID=""

finish() {
  echo
  echo "Termux kapanmayacak. Çıkmak için Enter tuşuna bas."
  read -r _
}
trap finish EXIT INT TERM

echo "===== KOLAY RIVET YENİDEN DENEME ====="

if ! gh auth status >/dev/null 2>&1; then
  echo "HATA: GitHub oturumu açık değil. Önce gh auth login çalıştır."
  exit 1
fi

echo
+echo "Rivet panelinden kopyaladığın tokeni veya tam deploy komutunu yapıştır."
+echo "Başlangıç biçimi kontrol edilmeyecek; geçerliliği Rivet API belirleyecek."
+echo "Girdi ekranda görünmeyecek."
+printf "Token veya komut: "
+IFS= read -r -s RAW_INPUT
+echo
+
+TOKEN="$(printf '%s' "$RAW_INPUT" | python -c '
+import re
+import shlex
+import sys
+
+raw = sys.stdin.read().strip().replace("\r", "")
+token = ""
+
+try:
+    parts = shlex.split(raw)
+except ValueError:
+    parts = []
+
+if "--token" in parts:
+    index = parts.index("--token")
+    if index + 1 < len(parts):
+        token = parts[index + 1].strip()
+
+if not token:
+    match = re.match(r"^(?:export\s+)?RIVET_CLOUD_TOKEN\s*=\s*(.+)$", raw)
+    if match:
+        token = match.group(1).strip()
+
+if not token and raw and not any(ch.isspace() for ch in raw):
+    token = raw
+
+if len(token) >= 16 and not any(ch.isspace() for ch in token):
+    sys.stdout.write(token)
+')"
+unset RAW_INPUT
+
+if [ -z "$TOKEN" ]; then
+  echo "HATA: Token alınamadı. Rivet panelindeki tokeni veya tam --token komutunu tekrar kopyala."
+  exit 1
+fi
+
+echo "Token alındı. GitHub secrets güncelleniyor..."
+
+printf '%s' "$TOKEN" | gh secret set RIVET_CLOUD_TOKEN --repo "$REPO" --env staging
+ENV_STATUS=$?
+printf '%s' "$TOKEN" | gh secret set RIVET_CLOUD_TOKEN --repo "$REPO"
+REPO_STATUS=$?
+unset TOKEN
+
+if [ "$ENV_STATUS" -ne 0 ] || [ "$REPO_STATUS" -ne 0 ]; then
+  echo "HATA: GitHub secret güncellenemedi."
+  exit 1
+fi
+
+BEFORE_ID="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null)"
+
+echo "Rivet deployment başlatılıyor..."
+gh workflow run "$WORKFLOW" --repo "$REPO" --ref main -f confirmation=DEPLOY-RIVET-STAGING || exit 1
+
+for _ in $(seq 1 60); do
+  sleep 2
+  CURRENT_ID="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null)"
+  if [ -n "$CURRENT_ID" ] && [ "$CURRENT_ID" != "$BEFORE_ID" ]; then
+    RUN_ID="$CURRENT_ID"
+    break
+  fi
+done
+
+if [ -z "$RUN_ID" ]; then
+  echo "HATA: Yeni GitHub Actions çalışması bulunamadı."
+  exit 1
+fi
+
+echo "RIVET_RUN_ID=$RUN_ID"
+echo "Canlı ilerleme:"
+gh run watch "$RUN_ID" --repo "$REPO" --exit-status
+STATUS=$?
+
+if [ "$STATUS" -eq 0 ]; then
+  echo
+  echo "RIVET_CONTROL_STAGING_READY=true"
+  echo "MAX_PLAYERS=10"
+  exit 0
+fi
+
+echo
+echo "RIVET_CONTROL_STAGING_READY=false"
+gh run view "$RUN_ID" --repo "$REPO" --log-failed | tail -n 220
+exit 1
