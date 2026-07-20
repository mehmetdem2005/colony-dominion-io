#!/data/data/com.termux/files/usr/bin/bash
set +e

REPO="mehmetdem2005/colony-dominion-io"
SOURCE_PATH="tools/termux_resume_online_setup.sh"
RUNTIME_DIR="$HOME/.colony-bootstrap"
RUNTIME_FILE="$RUNTIME_DIR/termux_resume_online_setup.runtime.sh"

mkdir -p "$RUNTIME_DIR"
rm -f "$RUNTIME_FILE"

finish_launcher() {
  local status="$1"
  echo
  echo "LAUNCHER_RESULT=$status"
  if [ "$status" != "HANDOFF" ]; then
    echo "Termux kapanmayacak. Çıkmak için Enter tuşuna bas."
    read -r _
  fi
}

command -v gh >/dev/null 2>&1 || {
  echo "HATA: gh komutu bulunamadı. Önce pkg install -y gh çalıştır." >&2
  finish_launcher FAILED
  exit 1
}

command -v python >/dev/null 2>&1 || {
  echo "HATA: python komutu bulunamadı. Önce pkg install -y python çalıştır." >&2
  finish_launcher FAILED
  exit 1
}

if ! gh auth status >/dev/null 2>&1; then
  echo "HATA: GitHub oturumu açık değil. Önce gh auth login çalıştır." >&2
  finish_launcher FAILED
  exit 1
fi

echo "===== GÜNCEL COLONY KURTARMA SİSTEMİ İNDİRİLİYOR ====="
gh api \
  -H "Accept: application/vnd.github.raw+json" \
  "repos/$REPO/contents/$SOURCE_PATH?ref=main" \
  > "$RUNTIME_FILE"
DOWNLOAD_STATUS=$?

if [ "$DOWNLOAD_STATUS" -ne 0 ] || [ ! -s "$RUNTIME_FILE" ]; then
  echo "HATA: Ana kurtarma scripti indirilemedi. Kod: $DOWNLOAD_STATUS" >&2
  finish_launcher FAILED
  exit 1
fi

python - "$RUNTIME_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = 'if grep -Fq "$pattern" "$file"; then'
new = 'if grep -Fq -- "$pattern" "$file"; then'

if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("Beklenen check_pattern grep satırı bulunamadı; script yapısı değişmiş")

path.write_text(text, encoding="utf-8")
PY
PATCH_STATUS=$?

if [ "$PATCH_STATUS" -ne 0 ]; then
  echo "HATA: Termux grep uyumluluk yaması uygulanamadı." >&2
  finish_launcher FAILED
  exit 1
fi

if ! bash -n "$RUNTIME_FILE"; then
  echo "HATA: Yamanmış script Bash sözdizimi kontrolünden geçmedi." >&2
  finish_launcher FAILED
  exit 1
fi

if ! grep -Fq -- 'grep -Fq -- "$pattern" "$file"' "$RUNTIME_FILE"; then
  echo "HATA: Grep güvenlik yaması doğrulanamadı." >&2
  finish_launcher FAILED
  exit 1
fi

if ! grep -Fq 'DEFAULT_MAX_PLAYERS: int = 10' "$RUNTIME_FILE" \
  || ! grep -Fq 'MAX_PLAYERS=10' "$RUNTIME_FILE"; then
  echo "HATA: İndirilen script 10 oyuncu doğrulama sözleşmesini içermiyor." >&2
  finish_launcher FAILED
  exit 1
fi

chmod 700 "$RUNTIME_FILE"
echo "Grep uyumluluk yaması doğrulandı. Ana derin kurulum başlatılıyor."
echo
finish_launcher HANDOFF
exec bash "$RUNTIME_FILE"
