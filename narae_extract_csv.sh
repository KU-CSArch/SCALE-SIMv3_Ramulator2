#!/usr/bin/env bash
set -euo pipefail

ROOT="/scalesim/SCALE-Sim"
TOPO_BASENAME="vit_l"
OUTDIR="$ROOT"
CSV="$OUTDIR/stall_vs_refi_rebuild.csv"

# CSV 헤더
echo -n "tREFI" > "$CSV"
for layer in 0 1 2 3 4; do
    echo -n ",L${layer}_total,L${layer}_compute,L${layer}_stall" >> "$CSV"
done
echo "" >> "$CSV"

for file in "$OUTDIR"/${TOPO_BASENAME}_stall_out_TREFI*; do
    [[ -f "$file" ]] || continue

    fname=$(basename "$file")
    refi=$(echo "$fname" | grep -oP "TREFI\K[0-9]+")

    totals=()
    computes=()
    stalls=()

    # 한 줄씩 읽으면서 추출
    while IFS= read -r line; do
        if [[ "$line" =~ Total\ cycles: ]]; then
            totals+=($(echo "$line" | awk '{print $NF}'))
        elif [[ "$line" =~ Compute\ cycles: ]]; then
            computes+=($(echo "$line" | awk '{print $NF}'))
        elif [[ "$line" =~ Stall\ cycles: ]]; then
            stalls+=($(echo "$line" | awk '{print $NF}'))
        fi
    done < "$file"

    # 레이어 개수가 부족하면 0으로 채움
    while [[ ${#totals[@]} -lt 5 ]]; do totals+=("0"); done
    while [[ ${#computes[@]} -lt 5 ]]; do computes+=("0"); done
    while [[ ${#stalls[@]} -lt 5 ]]; do stalls+=("0"); done

    # CSV 한 줄 작성
    echo -n "$refi" >> "$CSV"
    for i in 0 1 2 3 4; do
        echo -n ",${totals[$i]},${computes[$i]},${stalls[$i]}" >> "$CSV"
    done
    echo "" >> "$CSV"
done

echo "✅ CSV 재구성 완료 → $CSV"
