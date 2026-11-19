#!/usr/bin/env bash
# Publish Whisper weights + ML Kit OCR asset pack to ECS for first-use download.
# Usage: ./deploy/models/sync_models_to_ecs.sh
set -euo pipefail

HOST="${DEPLOY_HOST:-root@8.163.45.100}"
REMOTE_ROOT=/opt/acquireenglish/models
PUBLIC_BASE="${PUBLIC_MODELS_BASE:-https://acquireenglish.curlhairai.com/models}"
PUBLIC_WWW_BASE="${PUBLIC_MODELS_WWW_BASE:-https://www.curlhairai.com/models}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${TMPDIR:-/tmp}/ae-models-sync"
NGINX_SNIPPET="$ROOT/deploy/nginx/acquireenglish-models.conf"
NGINX_WWW_SNIPPET="$ROOT/deploy/nginx/curlhairai-www-models.conf"

WHISPER_FILES=(
  ggml-tiny.en.bin
  ggml-base.en.bin
  ggml-small.en.bin
  ggml-tiny.bin
  ggml-base.bin
)
REV=5359861c739e955e79d9a303bcbc70fb988958b1

rm -rf "$WORK"
mkdir -p "$WORK/whisper" "$WORK/ocr"

echo "==> Fetch Whisper weights (hf-mirror)"
for f in "${WHISPER_FILES[@]}"; do
  out="$WORK/whisper/$f"
  if [[ -f "$out" && -s "$out" ]]; then
    echo "skip $f"
    continue
  fi
  url="https://hf-mirror.com/ggerganov/whisper.cpp/resolve/${REV}/$f"
  echo "get $url"
  curl -fL --retry 3 --connect-timeout 20 --max-time 1800 -o "$out.part" "$url" \
    || curl -fL --retry 2 --connect-timeout 20 --max-time 1800 \
         -o "$out.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/${REV}/$f"
  mv "$out.part" "$out"
  ls -lh "$out"
done

echo "==> Pack ML Kit OCR assets from local Gradle cache"
export AE_MODELS_WORK="$WORK"
python3 - <<'PY'
import os, shutil, zipfile, tempfile, subprocess
from pathlib import Path

cache = Path.home() / ".gradle/caches/modules-2/files-2.1/com.google.mlkit"
work = Path(os.environ["AE_MODELS_WORK"])
assets_root = work / "ocr_assets"
if assets_root.exists():
    shutil.rmtree(assets_root)
assets_root.mkdir(parents=True)


def find_aar(name: str) -> Path:
    matches = sorted(cache.glob(f"{name}/*/*/{name}-*.aar"))
    if not matches:
        raise SystemExit(f"missing AAR {name} under {cache}")
    return matches[-1]


for mod in ("text-recognition", "text-recognition-chinese"):
    aar = find_aar(mod)
    print("aar", aar)
    with tempfile.TemporaryDirectory() as td:
        subprocess.check_call(["unzip", "-qo", str(aar), "assets/*", "-d", td])
        src = Path(td) / "assets"
        if not src.exists():
            continue
        for p in src.rglob("*"):
            if p.is_file():
                rel = p.relative_to(src)
                dest = assets_root / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(p, dest)

zip_path = work / "ocr" / "mlkit-google-ocr-models.zip"
if zip_path.exists():
    zip_path.unlink()
with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for p in sorted(assets_root.rglob("*")):
        if p.is_file():
            zf.write(p, arcname=str(p.relative_to(assets_root)))
print("ocr zip", zip_path, zip_path.stat().st_size)
PY

echo "==> Sync to $HOST:$REMOTE_ROOT"
ssh "$HOST" "mkdir -p '$REMOTE_ROOT/whisper' '$REMOTE_ROOT/ocr'"
rsync -az --progress "$WORK/whisper/" "$HOST:$REMOTE_ROOT/whisper/"
rsync -az --progress "$WORK/ocr/" "$HOST:$REMOTE_ROOT/ocr/"
scp "$NGINX_SNIPPET" "$HOST:/etc/nginx/snippets/acquireenglish-models.conf"
scp "$NGINX_WWW_SNIPPET" "$HOST:/etc/nginx/snippets/curlhairai-www-models.conf"
ssh "$HOST" 'bash -s' <<'REMOTE'
set -euo pipefail
SITE=/etc/nginx/sites-enabled/acquireenglish
if ! grep -q acquireenglish-models.conf "$SITE"; then
  sed -i '/include snippets\/acquireenglish-openlist.conf;/a\    include snippets/acquireenglish-models.conf;' "$SITE"
fi
WWW=/etc/nginx/sites-enabled/curlhairai-www
if [[ -f "$WWW" ]] && ! grep -q curlhairai-www-models.conf "$WWW"; then
  sed -i '/root \/opt\/curlhair\/www;/i\    include snippets/curlhairai-www-models.conf;' "$WWW"
fi
nginx -t
systemctl reload nginx
REMOTE

echo "==> Verify (HEAD only)"
for base in "$PUBLIC_BASE" "$PUBLIC_WWW_BASE"; do
  for f in ggml-base.en.bin ggml-tiny.en.bin; do
    code=$(curl -fsSI -o /dev/null -w "%{http_code}" "$base/whisper/$f" || true)
    echo "$base/whisper/$f -> $code"
  done
  code=$(curl -fsSI -o /dev/null -w "%{http_code}" "$base/ocr/mlkit-google-ocr-models.zip" || true)
  echo "$base/ocr zip -> $code"
done
echo "DONE $PUBLIC_BASE + $PUBLIC_WWW_BASE"
