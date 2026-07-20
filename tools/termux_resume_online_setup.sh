#!/data/data/com.termux/files/usr/bin/bash
set +e

REPO="mehmetdem2005/colony-dominion-io"
PREFERRED_DIR="$HOME/colony-live/colony-dominion-io-phase-05-3-1-live-deployment"
STAMP="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="$HOME/colony-deployment-evidence/$STAMP"
BACKUP_DIR="$HOME/colony-backups/termux-resume-$STAMP"
FINAL_STATUS=1
RIVET_RUN_ID=""
SUPABASE_RUN_ID=""
VALIDATE_RUN_ID=""
ONLINE_RUN_ID=""

mkdir -p "$EVIDENCE_DIR" "$BACKUP_DIR"

finish() {
  echo
  echo "============================================================"
  if [ "$FINAL_STATUS" -eq 0 ]; then
    echo "COLONY_STAGING_RESULT=SUCCESS"
  else
    echo "COLONY_STAGING_RESULT=FAILED"
  fi
  echo "EVIDENCE_DIR=$EVIDENCE_DIR"
  echo "BACKUP_DIR=$BACKUP_DIR"
  [ -n "$ONLINE_RUN_ID" ] && echo "ONLINE_VALIDATION_RUN_ID=$ONLINE_RUN_ID"
  [ -n "$VALIDATE_RUN_ID" ] && echo "RIVET_VALIDATION_RUN_ID=$VALIDATE_RUN_ID"
  [ -n "$SUPABASE_RUN_ID" ] && echo "SUPABASE_RUN_ID=$SUPABASE_RUN_ID"
  [ -n "$RIVET_RUN_ID" ] && echo "RIVET_RUN_ID=$RIVET_RUN_ID"
  echo "============================================================"
  echo
  echo "Termux kapanmayacak. Çıkmak için Enter tuşuna bas."
  read -r _
}
trap finish EXIT INT TERM

section() {
  echo
  echo "===== $* ====="
}

fail() {
  echo
  echo "HATA: $*" >&2
  return 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

find_repo_dir() {
  if [ -d "$PREFERRED_DIR/.git" ]; then
    printf '%s\n' "$PREFERRED_DIR"
    return 0
  fi

  local git_dir candidate remote
  while IFS= read -r git_dir; do
    candidate="${git_dir%/.git}"
    remote="$(git -C "$candidate" remote get-url origin 2>/dev/null)"
    case "$remote" in
      *github.com/mehmetdem2005/colony-dominion-io*|*github.com:mehmetdem2005/colony-dominion-io*)
        printf '%s\n' "$candidate"
        return 0
        ;;
    esac
  done < <(find "$HOME/colony-live" -maxdepth 4 -type d -name .git 2>/dev/null)

  return 1
}

secret_exists() {
  local name="$1"
  gh secret list --repo "$REPO" --env staging 2>/dev/null | awk '{print $1}' | grep -qx "$name" \
    || gh secret list --repo "$REPO" 2>/dev/null | awk '{print $1}' | grep -qx "$name"
}

variable_exists() {
  local name="$1"
  gh variable list --repo "$REPO" --env staging 2>/dev/null | awk '{print $1}' | grep -qx "$name" \
    || gh variable list --repo "$REPO" 2>/dev/null | awk '{print $1}' | grep -qx "$name"
}

prompt_secret() {
  local name="$1"
  local prompt="$2"
  local value
  echo
  echo "$prompt"
  echo "Değer ekranda görünmeyecek ve sohbet içinde paylaşılmayacak."
  printf '%s: ' "$name"
  IFS= read -r -s value
  echo
  value="${value//$'\r'/}"
  if [ -z "$value" ]; then
    fail "$name boş bırakıldı"
    return 1
  fi
  printf '%s' "$value" | gh secret set "$name" --repo "$REPO" --env staging || return 1
  printf '%s' "$value" | gh secret set "$name" --repo "$REPO" || return 1
  unset value
  echo "$name kaydedildi."
}

prompt_rivet_token() {
  local raw token
  echo
  echo "Rivet Dashboard > proje > Connect > Rivet Cloud bölümündeki"
  echo "RIVET_CLOUD_TOKEN değerini tek satır olarak yapıştır."
  echo "Tam 'RIVET_CLOUD_TOKEN=cloud_api_...' satırını da yapıştırabilirsin."
  printf 'RIVET_CLOUD_TOKEN: '
  IFS= read -r -s raw
  echo
  raw="${raw//$'\r'/}"
  token="$(printf '%s' "$raw" | python -c '
import re, sys
raw = sys.stdin.read()
items = list(dict.fromkeys(re.findall(r"cloud_api_[A-Za-z0-9._~+/=-]+", raw)))
if len(items) == 1:
    sys.stdout.write(items[0])
')"
  unset raw
  if [ -z "$token" ]; then
    fail "Yapıştırılan satırda tek bir cloud_api_ tokeni bulunamadı"
    return 1
  fi
  printf '%s' "$token" | gh secret set RIVET_CLOUD_TOKEN --repo "$REPO" --env staging || return 1
  printf '%s' "$token" | gh secret set RIVET_CLOUD_TOKEN --repo "$REPO" || return 1
  unset token
  echo "RIVET_CLOUD_TOKEN güvenli şekilde yenilendi."
}

latest_dispatch_id() {
  local workflow="$1"
  gh run list \
    --repo "$REPO" \
    --workflow "$workflow" \
    --branch main \
    --event workflow_dispatch \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty' 2>/dev/null
}

dispatch_and_wait() {
  local workflow="$1"
  local label="$2"
  shift 2
  local before candidate run_id status attempts

  before="$(latest_dispatch_id "$workflow")"
  section "$label BAŞLATILIYOR"

  gh workflow run "$workflow" --repo "$REPO" --ref main "$@"
  status=$?
  if [ "$status" -ne 0 ]; then
    fail "$label workflow başlatılamadı"
    return 1
  fi

  run_id=""
  for attempts in $(seq 1 45); do
    sleep 2
    candidate="$(latest_dispatch_id "$workflow")"
    if [ -n "$candidate" ] && [ "$candidate" != "$before" ]; then
      run_id="$candidate"
      break
    fi
  done

  if [ -z "$run_id" ]; then
    fail "$label için yeni Run ID bulunamadı"
    return 1
  fi

  echo "$run_id"
  gh run watch "$run_id" --repo "$REPO" --exit-status
  status=$?

  gh run view "$run_id" --repo "$REPO" > "$EVIDENCE_DIR/${workflow%.yml}-summary.txt" 2>&1 || true
  if [ "$status" -ne 0 ]; then
    gh run view "$run_id" --repo "$REPO" --log-failed \
      > "$EVIDENCE_DIR/${workflow%.yml}-failed.log" 2>&1 || true
    echo
    echo "----- $label SON HATA SATIRLARI -----"
    tail -n 220 "$EVIDENCE_DIR/${workflow%.yml}-failed.log" 2>/dev/null || true
    echo "----- HATA SONU -----"
    printf '%s\n' "$run_id"
    return 1
  fi

  printf '%s\n' "$run_id"
  return 0
}

download_artifact() {
  local run_id="$1"
  local artifact="$2"
  local target="$3"
  mkdir -p "$target"
  gh run download "$run_id" --repo "$REPO" --name "$artifact" --dir "$target"
}

section "TERMUX PAKET KONTROLÜ"
pkg install -y git gh jq curl python tar >/dev/null
if [ "$?" -ne 0 ]; then
  fail "Gerekli Termux paketleri kurulamadı"
  exit 1
fi

echo "git=$(git --version)"
echo "gh=$(gh --version | head -n 1)"
echo "jq=$(jq --version)"
echo "curl=$(curl --version | head -n 1)"

section "GITHUB OTURUM KONTROLÜ"
if ! gh auth status; then
  fail "GitHub oturumu kapalı. Önce gh auth login çalıştır"
  exit 1
fi

section "PROJE KLASÖRÜ BULUNUYOR"
PROJECT_DIR="$(find_repo_dir)"
if [ -z "$PROJECT_DIR" ]; then
  mkdir -p "$(dirname "$PREFERRED_DIR")"
  git clone "https://github.com/$REPO.git" "$PREFERRED_DIR"
  if [ "$?" -ne 0 ]; then
    fail "Repo klonlanamadı"
    exit 1
  fi
  PROJECT_DIR="$PREFERRED_DIR"
fi

echo "PROJECT_DIR=$PROJECT_DIR"
cd "$PROJECT_DIR" || exit 1

section "YEREL ÇALIŞMALAR KORUNUYOR"
git status --short > "$BACKUP_DIR/status-before.txt"
git diff > "$BACKUP_DIR/unstaged.patch"
git diff --cached > "$BACKUP_DIR/staged.patch"
git ls-files --others --exclude-standard > "$BACKUP_DIR/untracked-files.txt"

if ! git diff --quiet \
  || ! git diff --cached --quiet \
  || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git stash push -u -m "termux-deep-resume-$STAMP"
  if [ "$?" -ne 0 ]; then
    fail "Yerel değişiklikler stash içine alınamadı"
    exit 1
  fi
  echo "Yerel değişiklikler stash ve patch yedeğiyle korundu."
else
  echo "Çalışma ağacı temiz."
fi

section "MAIN İLE TAM SENKRONİZASYON"
git fetch origin main --prune
if [ "$?" -ne 0 ]; then
  fail "origin/main indirilemedi"
  exit 1
fi

if git show-ref --verify --quiet refs/heads/main; then
  git switch main >/dev/null 2>&1
else
  git switch -c main --track origin/main >/dev/null 2>&1
fi

LOCAL_HEAD="$(git rev-parse HEAD 2>/dev/null)"
REMOTE_HEAD="$(git rev-parse origin/main 2>/dev/null)"
if [ -n "$LOCAL_HEAD" ] && [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
  git branch "backup/termux-$STAMP-${LOCAL_HEAD:0:8}" "$LOCAL_HEAD" 2>/dev/null || true
fi

git reset --hard origin/main
if [ "$?" -ne 0 ]; then
  fail "main dalı origin/main ile eşitlenemedi"
  exit 1
fi

git clean -fd build >/dev/null 2>&1 || true
HEAD_SHA="$(git rev-parse HEAD)"
echo "HEAD_SHA=$HEAD_SHA"
git log -1 --oneline

section "10 OYUNCU VE MİMARİ TUTARLILIK TARAMASI"
CHECK_FAILURE=0
check_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"
  if grep -Fq "$pattern" "$file"; then
    echo "OK: $description"
  else
    echo "FAIL: $description ($file)" >&2
    CHECK_FAILURE=1
  fi
}

check_pattern network/network_protocol.gd 'DEFAULT_MAX_PLAYERS: int = 10' 'Godot ağ protokolü 10 oyuncu'
check_pattern backend/rivet-control/src/server.ts '"MAX_PLAYERS", 10' 'Matchmaking üst sınırı 10'
check_pattern backend/rivet-control/src/allocator.ts 'readPositiveInteger("MAX_PLAYERS", 10)' 'Allocator 10 oyuncu'
check_pattern backend/game-server/Dockerfile 'MAX_PLAYERS=10' 'Dedicated server Docker 10 oyuncu'
check_pattern backend/game-server/entrypoint.sh 'MAX_PLAYERS:-10' 'Sunucu başlangıç varsayılanı 10'
check_pattern tools/run_online_soak.sh 'PLAYERS="${PLAYERS:-10}"' 'Soak testi 10 istemci'
check_pattern .github/workflows/deploy-rivet-control-staging.yml 'MAX_PLAYERS: "10"' 'Staging dağıtımı 10 oyuncu'
check_pattern .github/workflows/deploy-rivet-control-staging.yml 'actions/checkout@v6' 'GitHub checkout Node 24 tabanlı'
check_pattern .github/workflows/deploy-rivet-control-staging.yml 'actions/setup-node@v6' 'GitHub setup-node güncel'
check_pattern .github/workflows/deploy-rivet-control-staging.yml '--token "$RIVET_CLOUD_TOKEN"' 'Rivet CLI tokeni açıkça alıyor'

if [ "$CHECK_FAILURE" -ne 0 ]; then
  fail "10 oyuncu veya deployment mimarisi tutarsız"
  exit 1
fi

section "GITHUB SECRET VE VARIABLE ENVANTERİ"
for secret in SUPABASE_ACCESS_TOKEN SUPABASE_SECRET_KEY RIVET_CLOUD_TOKEN; do
  if secret_exists "$secret"; then
    echo "OK secret: $secret"
  else
    case "$secret" in
      RIVET_CLOUD_TOKEN)
        prompt_rivet_token || exit 1
        ;;
      SUPABASE_ACCESS_TOKEN)
        prompt_secret "$secret" "Supabase Management API access tokenini gir." || exit 1
        ;;
      SUPABASE_SECRET_KEY)
        prompt_secret "$secret" "Supabase server-side secret keyini gir." || exit 1
        ;;
    esac
  fi
done

if variable_exists SUPABASE_PROJECT_REF; then
  echo "OK variable: SUPABASE_PROJECT_REF"
else
  echo
  printf 'SUPABASE_PROJECT_REF: '
  read -r PROJECT_REF
  PROJECT_REF="${PROJECT_REF//$'\r'/}"
  if [ -z "$PROJECT_REF" ]; then
    fail "SUPABASE_PROJECT_REF boş"
    exit 1
  fi
  gh variable set SUPABASE_PROJECT_REF --repo "$REPO" --env staging --body "$PROJECT_REF" || exit 1
  gh variable set SUPABASE_PROJECT_REF --repo "$REPO" --body "$PROJECT_REF" || true
fi

section "CI VE BUILD DOĞRULAMALARI"
ONLINE_OUTPUT="$(dispatch_and_wait online-release.yml "ONLINE RELEASE VALIDATION")"
ONLINE_STATUS=$?
ONLINE_RUN_ID="$(printf '%s\n' "$ONLINE_OUTPUT" | tail -n 1)"
printf '%s\n' "$ONLINE_OUTPUT"
if [ "$ONLINE_STATUS" -ne 0 ]; then
  fail "Online release validation başarısız"
  exit 1
fi

VALIDATE_OUTPUT="$(dispatch_and_wait validate-rivet-control.yml "RIVET CONTROL VALIDATION")"
VALIDATE_STATUS=$?
VALIDATE_RUN_ID="$(printf '%s\n' "$VALIDATE_OUTPUT" | tail -n 1)"
printf '%s\n' "$VALIDATE_OUTPUT"
if [ "$VALIDATE_STATUS" -ne 0 ]; then
  fail "Rivet control validation başarısız"
  exit 1
fi

section "SUPABASE STAGING UYGULAMA VE DOĞRULAMA"
SUPABASE_OUTPUT="$(dispatch_and_wait deploy-supabase-staging.yml "SUPABASE STAGING")"
SUPABASE_STATUS=$?
SUPABASE_RUN_ID="$(printf '%s\n' "$SUPABASE_OUTPUT" | tail -n 1)"
printf '%s\n' "$SUPABASE_OUTPUT"
if [ "$SUPABASE_STATUS" -ne 0 ]; then
  fail "Supabase staging başarısız"
  exit 1
fi

download_artifact "$SUPABASE_RUN_ID" colony-supabase-staging "$EVIDENCE_DIR/supabase"
SUPABASE_REPORT="$(find "$EVIDENCE_DIR/supabase" -type f -name last_deployment.json | head -n 1)"
if [ -z "$SUPABASE_REPORT" ]; then
  fail "Supabase deployment raporu bulunamadı"
  exit 1
fi

jq -e '
  .status == "complete" and
  .deployment_environment == "staging" and
  (.supabase.verification.verified_table_count >= 12) and
  .supabase.verification.authoritative_result_function == true and
  .supabase.verification.leaderboard_function == true and
  .supabase.verification.ranked_summary_function == true and
  ((.supabase.migrations_applied | length) >= 5)
' "$SUPABASE_REPORT" >/dev/null
if [ "$?" -ne 0 ]; then
  fail "Supabase raporu beklenen üretim sözleşmesini karşılamıyor"
  jq . "$SUPABASE_REPORT" || true
  exit 1
fi

echo "SUPABASE_STAGING_READY=true"

run_rivet_once() {
  local output status
  output="$(dispatch_and_wait deploy-rivet-control-staging.yml "RIVET CONTROL STAGING" -f confirmation=DEPLOY-RIVET-STAGING)"
  status=$?
  RIVET_RUN_ID="$(printf '%s\n' "$output" | tail -n 1)"
  printf '%s\n' "$output"
  return "$status"
}

section "RIVET STAGING DAĞITIMI"
run_rivet_once
RIVET_STATUS=$?

if [ "$RIVET_STATUS" -ne 0 ]; then
  RIVET_LOG="$EVIDENCE_DIR/deploy-rivet-control-staging-failed.log"
  if grep -Eqi '401 Unauthorized|must contain exactly one cloud_api_|RIVET_CLOUD_TOKEN is missing|Cloud API error' "$RIVET_LOG" 2>/dev/null; then
    section "RIVET TOKEN OTOMATİK KURTARMA"
    echo "Mevcut secret Rivet tarafından reddedildi veya yapısı bozuk."
    prompt_rivet_token || exit 1
    echo "Token yenilendi; Rivet deployment bir kez daha deneniyor."
    run_rivet_once
    RIVET_STATUS=$?
  fi
fi

if [ "$RIVET_STATUS" -ne 0 ]; then
  fail "Rivet staging ikinci denemeden sonra da başarısız"
  exit 1
fi

download_artifact "$RIVET_RUN_ID" rivet-control-staging "$EVIDENCE_DIR/rivet"
RIVET_REPORT="$(find "$EVIDENCE_DIR/rivet" -type f -name deployment-report.json | head -n 1)"
if [ -z "$RIVET_REPORT" ]; then
  fail "Rivet deployment raporu bulunamadı"
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
' "$RIVET_REPORT" >/dev/null
if [ "$?" -ne 0 ]; then
  fail "Rivet deployment raporu 10 oyunculu staging sözleşmesini karşılamıyor"
  jq . "$RIVET_REPORT" || true
  exit 1
fi

CONTROL_URL="$(jq -r '.rivet_control_base_url // empty' "$RIVET_REPORT")"
if [ -z "$CONTROL_URL" ]; then
  fail "Rivet control-plane URL raporda yok"
  exit 1
fi

section "CANLI ENDPOINT DERİN DOĞRULAMASI"
curl --fail --silent --show-error --retry 6 --retry-delay 2 --retry-all-errors \
  "$CONTROL_URL/v1/health" > "$EVIDENCE_DIR/live-health.json"
if [ "$?" -ne 0 ]; then
  fail "Canlı /v1/health erişilemedi"
  exit 1
fi

curl --fail --silent --show-error --retry 6 --retry-delay 2 --retry-all-errors \
  "$CONTROL_URL/v1/health/config" > "$EVIDENCE_DIR/live-health-config.json"
if [ "$?" -ne 0 ]; then
  fail "Canlı /v1/health/config erişilemedi"
  exit 1
fi

curl --fail --silent --show-error --retry 6 --retry-delay 2 --retry-all-errors \
  "$CONTROL_URL/v1/regions" > "$EVIDENCE_DIR/live-regions.json"
if [ "$?" -ne 0 ]; then
  fail "Canlı /v1/regions erişilemedi"
  exit 1
fi

jq -e '.ok == true' "$EVIDENCE_DIR/live-health.json" >/dev/null || exit 1
jq -e '
  .checks.supabase_url == true and
  .checks.supported_build_id == true and
  .checks.protocol_version == true and
  .checks.per_server_auth == true and
  .checks.supabase_server_write == true and
  .checks.regions == true and
  .checks.allocator == false and
  .limits.min_players == 2 and
  .limits.max_players == 10
' "$EVIDENCE_DIR/live-health-config.json" >/dev/null
if [ "$?" -ne 0 ]; then
  fail "Canlı control-plane ayarları beklenen durumda değil"
  jq . "$EVIDENCE_DIR/live-health-config.json" || true
  exit 1
fi

jq -e '.regions | type == "array" and length > 0' "$EVIDENCE_DIR/live-regions.json" >/dev/null
if [ "$?" -ne 0 ]; then
  fail "Canlı region kataloğu boş"
  exit 1
fi

section "SONUÇ"
echo "SOURCE_MAIN_SYNCED=true"
echo "ONLINE_RELEASE_VALIDATION=true"
echo "RIVET_CONTROL_VALIDATION=true"
echo "SUPABASE_STAGING_READY=true"
echo "RIVET_CONTROL_STAGING_READY=true"
echo "MAX_PLAYERS=10"
echo "RIVET_CONTROL_URL=$CONTROL_URL"
echo "GAME_SERVER_ALLOCATOR_READY=false"
echo "FULL_ONLINE_READY=false"
echo
echo "Not: allocator=false hata değildir. Control plane ve Supabase hazırdır;"
echo "Godot UDP dedicated gameplay server hosting ayrı sonraki üretim kapısıdır."

FINAL_STATUS=0
exit 0
