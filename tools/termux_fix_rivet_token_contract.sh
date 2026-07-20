#!/data/data/com.termux/files/usr/bin/bash
set +e

REPO="mehmetdem2005/colony-dominion-io"
WORKFLOW="deploy-rivet-control-staging.yml"
PREFERRED_DIR="$HOME/colony-live/colony-dominion-io-phase-05-3-1-live-deployment"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT_DIR="$HOME/colony-deployment-evidence/rivet-contract-fix-$STAMP"
RUN_ID=""
FINAL_STATUS=1

mkdir -p "$RESULT_DIR"

finish() {
  echo
  echo "============================================================"
  if [ "$FINAL_STATUS" -eq 0 ]; then
    echo "RIVET_CONTRACT_FIX_RESULT=SUCCESS"
  else
    echo "RIVET_CONTRACT_FIX_RESULT=FAILED"
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

find_repo() {
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

echo "===== RIVET TOKEN SÖZLEŞMESİ KÖK DÜZELTMESİ ====="

echo
echo "===== GITHUB OTURUMU ====="
if ! gh auth status; then
  fail "GitHub oturumu açık değil"
  exit 1
fi

PROJECT_DIR="$(find_repo)"
if [ -z "$PROJECT_DIR" ]; then
  mkdir -p "$(dirname "$PREFERRED_DIR")"
  git clone "https://github.com/$REPO.git" "$PREFERRED_DIR" || exit 1
  PROJECT_DIR="$PREFERRED_DIR"
fi

cd "$PROJECT_DIR" || exit 1

echo
echo "===== YEREL DURUM KORUNUYOR ====="
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git stash push -u -m "rivet-contract-fix-$STAMP" || exit 1
  echo "Yerel değişiklikler stash içine alındı."
else
  echo "Çalışma ağacı temiz."
fi

git fetch origin main --prune || exit 1
git switch main >/dev/null 2>&1 || git switch -c main --track origin/main || exit 1
git reset --hard origin/main || exit 1

echo
echo "===== WORKFLOW TOKEN DOĞRULAMASI DÜZELTİLİYOR ====="
python - <<'PY'
from pathlib import Path
import re

path = Path('.github/workflows/deploy-rivet-control-staging.yml')
text = path.read_text(encoding='utf-8')

start = '          raw_token = os.environ.get("RAW_RIVET_CLOUD_TOKEN", "")\n'
end = '          raw_regions = os.environ.get("REGIONS_JSON", "").strip()\n'

if start not in text or end not in text:
    if 'token_family' in text and 'Rivet CLI-compatible token normalization' in text:
        print('Workflow token contract is already patched.')
        raise SystemExit(0)
    raise SystemExit('Expected workflow token normalization block was not found')

before, remainder = text.split(start, 1)
_old_block, after = remainder.split(end, 1)

replacement = '''          # Rivet CLI-compatible token normalization. The CLI accepts an opaque,
          # non-empty token and delegates validity to /tokens/api/inspect.
          raw_token = os.environ.get("RAW_RIVET_CLOUD_TOKEN", "")

          def unquote(value: str) -> str:
              value = value.strip()
              if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                  return value[1:-1].strip()
              return value

          token = ""
          stripped = raw_token.strip()

          # Accept JSON copied from Connect, assignment lines, or a direct token.
          if stripped.startswith(("{", "[")):
              try:
                  parsed = json.loads(stripped)
              except json.JSONDecodeError:
                  parsed = None

              def find_token(value):
                  if isinstance(value, dict):
                      for key in ("RIVET_CLOUD_TOKEN", "rivet_cloud_token", "token"):
                          candidate = value.get(key)
                          if isinstance(candidate, str) and candidate.strip():
                              return candidate
                      for child in value.values():
                          candidate = find_token(child)
                          if candidate:
                              return candidate
                  elif isinstance(value, list):
                      for child in value:
                          candidate = find_token(child)
                          if candidate:
                              return candidate
                  return ""

              if parsed is not None:
                  token = find_token(parsed)

          if not token:
              assignment = re.search(
                  r"(?m)^\\s*(?:export\\s+)?RIVET_CLOUD_TOKEN\\s*=\\s*(.+?)\\s*$",
                  raw_token,
              )
              if assignment:
                  token = assignment.group(1)

          if not token:
              # Prefer known current and legacy dashboard forms when Connect text
              # contains surrounding prose.
              known = list(dict.fromkeys(
                  re.findall(
                      r"cloud_api_[A-Za-z0-9._~+/=-]+|cloud\\.[A-Za-z0-9_-]+(?:\\.[A-Za-z0-9_-]+){2}",
                      raw_token,
                  )
              ))
              if len(known) == 1:
                  token = known[0]

          if not token and stripped and not any(ch.isspace() for ch in stripped):
              token = stripped

          token = unquote(token)
          if not token:
              raise SystemExit("RIVET_CLOUD_TOKEN is empty after normalization")
          if any(ch.isspace() for ch in token):
              raise SystemExit("RIVET_CLOUD_TOKEN contains whitespace after normalization")
          if len(token) < 16:
              raise SystemExit("RIVET_CLOUD_TOKEN is unexpectedly short")

          if token.startswith("cloud_api_"):
              token_family = "cloud_api"
          elif token.startswith("cloud.") and token.count(".") == 3:
              token_family = "cloud_jwt"
          else:
              token_family = "opaque"

          diagnostic = {
              "raw_length": len(raw_token),
              "normalized_length": len(token),
              "token_family": token_family,
              "looks_like_assignment": "RIVET_CLOUD_TOKEN" in raw_token and "=" in raw_token,
              "looks_like_json": stripped.startswith(("{", "[")),
              "contains_whitespace": any(ch.isspace() for ch in raw_token),
              "validation_authority": "rivet_cloud_tokens_api_inspect",
          }
          Path("build/rivet-staging/token-diagnostic.json").write_text(
              json.dumps(diagnostic, indent=2, sort_keys=True) + "\\n",
              encoding="utf-8",
          )

          print(f"::add-mask::{token}")
          with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
              output.write(f"RIVET_CLOUD_TOKEN={token}\\n")
          print(f"Rivet token normalized; family={token_family}; API inspection is authoritative")

'''

text = before + replacement + end + after
path.write_text(text, encoding='utf-8')
print('Workflow token contract patched.')
PY

if [ "$?" -ne 0 ]; then
  fail "Workflow token sözleşmesi düzeltilemedi"
  exit 1
fi

python - <<'PY'
from pathlib import Path
text = Path('.github/workflows/deploy-rivet-control-staging.yml').read_text(encoding='utf-8')
required = (
    'Rivet CLI-compatible token normalization',
    'token_family = "cloud_jwt"',
    'validation_authority": "rivet_cloud_tokens_api_inspect"',
    '--token "$RIVET_CLOUD_TOKEN"',
    'MAX_PLAYERS: "10"',
)
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f'Missing workflow markers: {missing}')
print('Workflow contract markers verified.')
PY

if [ "$?" -ne 0 ]; then
  fail "Workflow doğrulaması başarısız"
  exit 1
fi

git diff --check || exit 1

if ! git diff --quiet; then
  git add .github/workflows/deploy-rivet-control-staging.yml
  git commit -m "Accept Rivet CLI-compatible cloud token formats" || exit 1
else
  echo "Workflow zaten düzeltilmiş."
fi

echo
echo "===== RIVET TOKENİ GÜVENLİ ALINIYOR ====="
echo "Rivet panelindeki tokeni yapıştır. cloud_api_ veya cloud. biçimi kabul edilir."
echo "Token ekranda görünmeyecek."
printf 'RIVET_CLOUD_TOKEN: '
IFS= read -r -s RAW_TOKEN
echo
RAW_TOKEN="${RAW_TOKEN//$'\r'/}"

TOKEN="$(printf '%s' "$RAW_TOKEN" | python -c '
import re, sys
raw = sys.stdin.read().strip()
match = re.match(r"^(?:export\s+)?RIVET_CLOUD_TOKEN\s*=\s*(.+)$", raw)
if match:
    raw = match.group(1).strip()
if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"\047":
    raw = raw[1:-1].strip()
if raw and not any(ch.isspace() for ch in raw) and len(raw) >= 16:
    sys.stdout.write(raw)
')"
unset RAW_TOKEN

if [ -z "$TOKEN" ]; then
  fail "Token boş, çok satırlı veya yapısal olarak kullanılamaz"
  exit 1
fi

case "$TOKEN" in
  cloud_api_*) TOKEN_FAMILY="cloud_api" ;;
  cloud.*) TOKEN_FAMILY="cloud_jwt_or_opaque" ;;
  *) TOKEN_FAMILY="opaque" ;;
esac

echo "Token yerel yapısal kontrolden geçti: family=$TOKEN_FAMILY length=${#TOKEN}"

echo
echo "===== GITHUB SECRETS GÜNCELLENİYOR ====="
printf '%s' "$TOKEN" | gh secret set RIVET_CLOUD_TOKEN --repo "$REPO" --env staging
ENV_STATUS=$?
printf '%s' "$TOKEN" | gh secret set RIVET_CLOUD_TOKEN --repo "$REPO"
REPO_STATUS=$?
unset TOKEN

if [ "$ENV_STATUS" -ne 0 ] || [ "$REPO_STATUS" -ne 0 ]; then
  fail "GitHub secret güncellenemedi: staging=$ENV_STATUS repository=$REPO_STATUS"
  exit 1
fi

if ! git diff --quiet HEAD; then
  fail "Commit sonrasında beklenmeyen yerel değişiklik var"
  exit 1
fi

echo
echo "===== WORKFLOW DÜZELTMESİ PUSH EDİLİYOR ====="
git push origin main || exit 1

BEFORE_ID="$(latest_dispatch_id)"

echo
echo "===== SADECE RIVET STAGING YENİDEN BAŞLATILIYOR ====="
gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref main \
  -f confirmation=DEPLOY-RIVET-STAGING || exit 1

for ATTEMPT in $(seq 1 60); do
  sleep 2
  CANDIDATE="$(latest_dispatch_id)"
  if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "$BEFORE_ID" ]; then
    RUN_ID="$CANDIDATE"
    break
  fi
done

if [ -z "$RUN_ID" ]; then
  fail "Yeni Rivet workflow Run ID bulunamadı"
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
echo "===== DEPLOYMENT ARTIFACT DOĞRULAMASI ====="
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
  fail "Workflow başarılı fakat deployment-report.json bulunamadı"
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
  fail "Deployment raporu 10 oyunculu staging sözleşmesini karşılamıyor"
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
