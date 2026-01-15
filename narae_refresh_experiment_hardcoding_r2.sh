#!/usr/bin/env bash
set -euo pipefail

# Ramulator2 hardcoding and refresh experiment
ROOT="/scalesim/SCALE-Sim"
DDR5_CPP="$ROOT/submodules/ramulator2/src/dram/impl/DDR5-VRR.cpp"
RAMULATOR_DIR="$ROOT/submodules/ramulator2"

TOPOLOGY="topologies/GEMM_mnk/vit_l.csv"
#TOPOLOGY="/scalesim/SCALE-Sim/topologies/GEMM_mnk/gpt2.csv"
LAYOUT="layouts/GEMM_mnk/vit_l_KM_KN.csv"
#LAYOUT="/scalesim/SCALE-Sim/layouts/GEMM_mnk/gpt2.csv"
TOPO_BASENAME="$(basename "$TOPOLOGY" .csv)"

# tREFI sweep
TREFI_START=1950
TREFI_STEP=1950
TREFI_END=19500
REFI_LIST=($(seq $TREFI_START $TREFI_STEP $TREFI_END))

OUTDIR="$ROOT"
CSV="$OUTDIR/stall_vs_refi_v3.csv"

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
  python "$ROOT/scripts/dram_sim.py" -run_name GoogleTPU_v1_ws

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

  cp -f "$DDR5_CPP" "${DDR5_CPP}.bak"

  sed -i \
    "s/constexpr int tREFI_BASE = [0-9]\+/constexpr int tREFI_BASE = ${REFI}/" \
    "$DDR5_CPP"

  if ! grep -q "${REFI}" "$DDR5_CPP"; then
    echo "[WARN] sed replacement failed for tREFI=${REFI}, skipping."
    mv -f "${DDR5_CPP}.bak" "$DDR5_CPP"
    continue
  fi

  #confirm change
  grep -i "tREFI_BASE" -A2 "$DDR5_CPP"

  echo "Rebuilding Ramulator..."


  pushd "$RAMULATOR_DIR"
  mkdir -p build
  cd build
  cmake ..
  make -j4
  popd

#  pushd "$RAMULATOR_DIR" >/dev/null
 # make -j4
 # popd >/dev/null

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

  mv -f "${DDR5_CPP}.bak" "$DDR5_CPP"
done

echo "✅ Done. CSV saved: $CSV"

python notify.py --msg "Docker: Scalesim+Ramulator2 tREFI sweep done. CSV saved"

#nohup bash /scalesim/SCALE-Sim/narae_refresh_experiment_hardcoding_r2.sh > experiment.log 2>&1 &
#ps aux | grep run_experiment.sh
#tail -f experiment.log
#pkill -f run_experiment.sh

# Ctrl+b d (to detach)
