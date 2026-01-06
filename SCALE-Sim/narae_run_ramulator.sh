#!/bin/bash

set -euo pipefail

topology="topologies/GEMM_mnk/vit_l.csv"
#topology="topologies/translation/gpt2.csv"
#topology="topologies/ispass25_models/resnet18.csv"
#topology="topologies/llama/llama3b_clean.csv"
#topology="topologies/Qwen_Qwen2.5-0.5B.csv"
topo="${topology##*/}"
topo="${topo%.csv}"

# Entries: layer name, Ifmap h, ifmap w, filter h, filter w, num_ch, num_filt,
                #          stride h, stride w, N in N:M, M in N:M
                # entries = [layer_name, m, k, 1, k, 1, n, 1, 1, sparsity_ratio[0], sparsity_ratio[1]]
                # entries are later iterated from index 1. Index 0 is used to store layer name in
                # convolution mode. So, to rectify assignment of M, N and K in GEMM mode, layer name
                # has been added at index 0 of entries.


layout="layouts/GEMM_mnk/vit_l_KM_KN.csv"

run_name="GoogleTPU_v1_ws"

echo "Running scalesim/scale.py"
echo "-------------------------"
python3 scalesim/scale.py -c ./configs/google.cfg -t ${topology} -l ${layout} -i gemm > ${topo}_orig_out


echo "Running dram_sim.py"
echo "-------------------------"
python3 scripts/dram_sim.py  -run_name ${run_name} -topology ${topology}


echo "Running dram_latency.py"
echo "-------------------------"
python3 scripts/dram_latency.py


echo "Running scalesim/scale.py"
echo "-------------------------"
python3 scalesim/scale.py -c ./configs/google_ramulator.cfg -t ${topology} -l ${layout} -i gemm > ${topo}_stall_out

