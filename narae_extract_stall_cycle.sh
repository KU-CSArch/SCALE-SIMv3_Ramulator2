#!/usr/bin/env bash
set -euo pipefail

ROOT="/scalesim/SCALE-Sim"
TOPO_BASENAME="vit_l"
OUTDIR="$ROOT"
CSV="$OUTDIR/stall_vs_refi_rebuild.csv"

echo "tREFI,layer0,layer1,layer2,layer3,layer4" > "$CSV"

# 파일 패턴 반복
for file in "$OUTDIR"/${TOPO_BASENAME}_stall_out_TREFI*; do
    [[ -f "$file" ]] || continue

    # 파일명에서 tREFI 값 추출
    fname=$(basename "$file")
    # 예: vit_l_stall_out_TREFI1170 → 1170 추출
    refi=$(echo "$fname" | grep -oP "TREFI\K[0-9]+")

    # Stall cycles 추출
    readarray -t stalls < <(grep -i "Stall cycles" "$file" | awk '{print $NF}')

    # layer 개수 부족하면 0으로 채우기
    while [[ ${#stalls[@]} -lt 5 ]]; do
        stalls+=("0")
    done

    # CSV 한 줄 생성
    echo "${refi},${stalls[0]},${stalls[1]},${stalls[2]},${stalls[3]},${stalls[4]}" \
        | tee -a "$CSV"
done

echo "✅ CSV 재구성 완료 → $CSV"
