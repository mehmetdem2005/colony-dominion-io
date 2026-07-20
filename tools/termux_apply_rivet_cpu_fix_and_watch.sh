#!/data/data/com.termux/files/usr/bin/bash

set +e
set -u
set -o pipefail

REPO="mehmetdem2005/colony-dominion-io"
FIX_WF="one-shot-fix-rivet-cpu.yml"
DEPLOY_WF="deploy-rivet-control-staging.yml"

echo "===== RIVET CPU KÖK DÜZELTMESİ ====="

if ! gh auth status >/dev/null 2>&1; then
  echo "HATA: GitHub CLI oturumu açık değil."
  exit 1
fi

BEFORE_FIX_ID="$(
  gh run list \
    --repo "$REPO" \
    --workflow "$FIX_WF" \
    --event workflow_dispatch \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty' \
    2>/dev/null
)"

BEFORE_DEPLOY_ID="$(
  gh run list \
    --repo "$REPO" \
    --workflow "$DEPLOY_WF" \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty' \
    2>/dev/null
)"

CURRENT_WORKFLOW="$(
  gh api \
    -H "Accept: application/vnd.github.raw+json" \
    "repos/$REPO/contents/.github/workflows/$DEPLOY_WF?ref=main" \
    2>/dev/null
)"

if printf '%s' "$CURRENT_WORKFLOW" | grep -Fq -- '--cpu 1 \' \
  && printf '%s' "$CURRENT_WORKFLOW" | grep -Fq -- '--instance-request-concurrency 80 \\'; then
  echo "CPU düzeltmesi zaten uygulanmış. Yeni deployment başlatılıyor."
  gh workflow run "$DEPLOY_WF" \
    --repo "$REPO" \
    --ref main \
    -f confirmation=DEPLOY-RIVET-STAGING
  FIX_STATUS=$?
else
  echo "Eski CPU=0.25 yapılandırması bulundu. Tek kullanımlık düzeltme başlatılıyor."
  gh workflow run "$FIX_WF" \
    --repo "$REPO" \
    --ref main
  FIX_STATUS=$?
fi

if [ "$FIX_STATUS" -ne 0 ]; then
  echo "HATA: Düzeltme/deployment workflow'u başlatılamadı."
  exit "$FIX_STATUS"
fi

FIX_RUN_ID=""
for _ in $(seq 1 60); do
  sleep 2
  CURRENT_FIX_ID="$(
    gh run list \
      --repo "$REPO" \
      --workflow "$FIX_WF" \
      --event workflow_dispatch \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId // empty' \
      2>/dev/null
  )"
  if [ -n "$CURRENT_FIX_ID" ] && [ "$CURRENT_FIX_ID" != "$BEFORE_FIX_ID" ]; then
    FIX_RUN_ID="$CURRENT_FIX_ID"
    break
  fi

done

if [ -n "$FIX_RUN_ID" ]; then
  echo "FIX_RUN_ID=$FIX_RUN_ID"
  gh run watch "$FIX_RUN_ID" --repo "$REPO" --exit-status
  FIX_RESULT=$?
  if [ "$FIX_RESULT" -ne 0 ]; then
    echo "HATA: CPU düzeltme workflow'u başarısız oldu."
    gh run view "$FIX_RUN_ID" --repo "$REPO" --log-failed | tail -n 250
    exit "$FIX_RESULT"
  fi
fi

DEPLOY_RUN_ID=""
for _ in $(seq 1 120); do
  sleep 3
  CURRENT_DEPLOY_ID="$(
    gh run list \
      --repo "$REPO" \
      --workflow "$DEPLOY_WF" \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId // empty' \
      2>/dev/null
  )"
  if [ -n "$CURRENT_DEPLOY_ID" ] && [ "$CURRENT_DEPLOY_ID" != "$BEFORE_DEPLOY_ID" ]; then
    DEPLOY_RUN_ID="$CURRENT_DEPLOY_ID"
    break
  fi

done

if [ -z "$DEPLOY_RUN_ID" ]; then
  echo "HATA: Düzeltilmiş deployment run'ı bulunamadı."
  exit 1
fi

echo "DEPLOY_RUN_ID=$DEPLOY_RUN_ID"
gh run watch "$DEPLOY_RUN_ID" --repo "$REPO" --exit-status
DEPLOY_RESULT=$?

if [ "$DEPLOY_RESULT" -eq 0 ]; then
  echo "RIVET_CPU_FIX_RESULT=SUCCESS"
  echo "RIVET_CONTROL_STAGING_READY=true"
else
  echo "RIVET_CPU_FIX_RESULT=FAILED"
  gh run view "$DEPLOY_RUN_ID" --repo "$REPO" --log-failed | tail -n 300
fi

exit "$DEPLOY_RESULT"
