#!/usr/bin/env bash
set -euo pipefail

ROOT="/scalesim/SCALE-Sim"
DDR4_CPP="$ROOT/submodules/ramulator/src/DDR4.cpp"
RAMULATOR_DIR="$ROOT/submodules/ramulator"

TOPOLOGY="topologies/GEMM_mnk/vit_l.csv"
LAYOUT="layouts/GEMM_mnk/vit_l_KM_KN.csv"
TOPO_BASENAME="$(basename "$TOPOLOGY" .csv)"

# tREFI sweep
TREFI_START=1170
TREFI_STEP=1170
TREFI_END=25740
REFI_LIST=($(seq $TREFI_START $TREFI_STEP $TREFI_END))

OUTDIR="$ROOT"
CSV="$OUTDIR/stall_vs_refi.csv"

# we know vit-L has 4 layers
N_LAYERS=5

echo "tREFI,layer0,layer1,layer2,layer3,layer4" > "$CSV"

run_all() {
  
  local tag="$1"
  # baseline run
  echo "===== orig_out ====="
  python "$ROOT/scalesim/scale.py" \
    -c "$ROOT/configs/google.cfg" \
    -l "$LAYOUT" \
    -t "$TOPOLOGY" \
    -i gemm \
    > "$OUTDIR/${TOPO_BASENAME}_orig_out_${tag}" || true

  echo "Running dram_sim.py"
  python "$ROOT/scripts/dram_sim.py" -run_name GoogleTPU_v1_os

  echo "Running dram_latency.py"
  python "$ROOT/scripts/dram_latency.py"

  echo "Running scalesim/scale.py (ramulator)"
  python "$ROOT/scalesim/scale.py" \
    -c "$ROOT/configs/google_ramulator.cfg" \
    -l "$LAYOUT" \
    -t "$TOPOLOGY" \
    -i gemm \
    > "$OUTDIR/${TOPO_BASENAME}_stall_out_${tag}" || true
}


# sweep loop
for REFI in "${REFI_LIST[@]}"; do
  echo "===== tREFI = ${REFI} ====="

  cp -f "$DDR4_CPP" "${DDR4_CPP}.bak"

  sed -i -z -E \
    "s/\{[[:space:]]*6240,[[:space:]]*7280,[[:space:]]*8320,[[:space:]]*[0-9]+,[[:space:]]*12480[[:space:]]*\}/\
{6240, 7280, 8320, ${REFI}, 12480}/" \
    "$DDR4_CPP"

  if ! grep -q "${REFI}" "$DDR4_CPP"; then
    echo "[WARN] sed replacement failed for tREFI=${REFI}, skipping."
    mv -f "${DDR4_CPP}.bak" "$DDR4_CPP"
    continue
  fi

  #confirm change
  grep -i "REFI_TABLE" -A2 "$DDR4_CPP"

  echo "Rebuilding Ramulator..."
  pushd "$RAMULATOR_DIR" >/dev/null
  make -j4
  popd >/dev/null

  TAG="TREFI${REFI}"

  run_all "$TAG"

  OUTFILE="$OUTDIR/${TOPO_BASENAME}_stall_out_${TAG}"
  readarray -t STALLS < <(grep -i "Stall cycles" "$OUTFILE" | awk '{print $NF}')


  if [[ ${#STALLS[@]} -lt $N_LAYERS ]]; then
    for ((i=${#STALLS[@]}; i<$N_LAYERS; i++)); do
        STALLS+=("0")
    done
  fi


  LINE="${REFI},${STALLS[0]},${STALLS[1]},${STALLS[2]},${STALLS[3]},${STALLS[4]}"
  echo "$LINE" | tee -a "$CSV"

  mv -f "${DDR4_CPP}.bak" "$DDR4_CPP"
done

echo "✅ Done. CSV saved: $CSV"
