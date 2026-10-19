#!/bin/bash
# EdgeVoice 모델 받기 (Linux·Jetson) — compose 파일의 기본 모델(과 .env)을 읽어 docker 안에서 HuggingFace 로 받는다.
# Windows 는 deploy/download-models.ps1 (같은 방식, 크기·남은 크기 표시).
#
#   ./scripts/download-models.sh [dev|jetson]
#
# 모델은 각자의 라이선스를 따른다 (HuggingFace 모델 페이지 참고).
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="$ROOT/docker-compose.${1:-dev}.yml"
MODEL_DIR="$ROOT/models"
[ -f "$ROOT/.env" ] && set -a && . "$ROOT/.env" && set +a

# 서비스 블록에서 값 하나: ${VAR:-기본값} 이면 .env 값 또는 기본값
block() { awk -v s="  $1:" '$0==s{f=1;next} f&&/^  [A-Za-z][A-Za-z0-9_-]*:$/{f=0} f' "$COMPOSE"; }
resolve() {
    local v="$1"
    if [[ "$v" =~ ^\$\{([A-Za-z_]+):-([^}]*)\}$ ]]; then
        local name="${BASH_REMATCH[1]}"
        v="${!name:-${BASH_REMATCH[2]}}"
    fi
    echo "$v"
}

LLM=$(resolve "$(block llm | grep -A1 -- '- --model' | tail -1 | sed 's/^ *- *//')")
[ -z "$LLM" ] || [ "$LLM" = "- --model" ] && LLM=$(resolve "$(block llm | sed -n 's/.*MODEL_NAME=//p' | head -1)")
STT=$(resolve "$(block stt | sed -n 's/.*MODEL_SIZE=//p' | head -1)")
EMB=$(resolve "$(block embedding | sed -n 's/.*MODEL_NAME=//p' | head -1)")
case "$STT" in
    large-v3-turbo|turbo) STT=mobiuslabsgmbh/faster-whisper-large-v3-turbo ;;
    large-v3|medium|small|base) STT="Systran/faster-whisper-$STT" ;;
esac

echo "LLM: $LLM"
echo "임베딩: $EMB"
echo "음성 인식(STT): $STT"
mkdir -p "$MODEL_DIR"

docker run --rm -e HF_TOKEN="${HF_TOKEN:-}" \
    -v "$MODEL_DIR:/m" -v edgevoice-stt-hf-cache:/stt \
    python:3.11-slim sh -c "pip install -q --disable-pip-version-check 'huggingface_hub>=0.34' \
        && hf download $LLM --cache-dir /m/llm/hub \
        && hf download $EMB --local-dir /m/embedding \
        && hf download $STT --cache-dir /stt/hub"
echo "모델 받기 완료"
