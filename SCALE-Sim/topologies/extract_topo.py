import csv
import os
from transformers import AutoConfig

# ==========================================================
# USER INPUT
# ==========================================================
MODEL_NAME = "Qwen/Qwen2.5-0.5B"   # HuggingFace 모델명
TOPO_DIR = "topologies"
LAYOUT_DIR = "layouts"
os.makedirs(TOPO_DIR, exist_ok=True)
os.makedirs(LAYOUT_DIR, exist_ok=True)

SAFE_NAME = MODEL_NAME.replace("/", "_")
TOPO_OUTFILE = f"{TOPO_DIR}/{SAFE_NAME}.csv"
LAYOUT_OUTFILE = f"{LAYOUT_DIR}/{SAFE_NAME}.csv"
# ==========================================================


# ==========================================================
# Load HuggingFace model config
# ==========================================================
config = AutoConfig.from_pretrained(MODEL_NAME)

hidden = config.hidden_size
ffn = config.intermediate_size
layers = config.num_hidden_layers
seq_len = config.max_position_embeddings

print("\n=== Loaded Model ===")
print("Model:", MODEL_NAME)
print(f"hidden={hidden}, ffn={ffn}, layers={layers}, seq_len={seq_len}")


# ==========================================================
# 1. Generate GEMM-MNK topology
# ==========================================================
mnk_header = ["Layer name", "M", "N", "K", "Sparsity"]
mnk_rows = []

for i in range(1, layers + 1):

    # Q,K,V,O
    for proj in ["Q", "K", "V", "O"]:
        mnk_rows.append([
            f"{proj}_{i}",
            seq_len,         # M
            hidden,          # N
            hidden,          # K
            "1:1"
        ])

    # FF1 (hidden -> ffn)
    mnk_rows.append([
        f"FF1_{i}",
        seq_len,
        ffn,               # N
        hidden,            # K
        "1:1"
    ])

    # FF2 (ffn -> hidden)
    mnk_rows.append([
        f"FF2_{i}",
        seq_len,
        hidden,            # N
        ffn,               # K
        "1:1"
    ])

# Write MNK topology CSV
with open(TOPO_OUTFILE, "w", newline='') as f:
    writer = csv.writer(f)
    writer.writerow(mnk_header)
    writer.writerows(mnk_rows)

print(f"[OK] MNK topology saved → {TOPO_OUTFILE}")


# ==========================================================
# 2. Generate layout CSVs (WS / OS / IS)
# ==========================================================
# Generic robust tile sizes for Qwen-scale matrices:
# hidden=896, ffn=4864  → divisible by 32/64/128

# Weight-Stationary (WS)
WS_M = 1
WS_K = 128
WS_N = 32

# Output-Stationary (OS)
OS_M = 128
OS_K = 128
OS_N = 1

# Input-Stationary (IS)
IS_M = 1
IS_K = 1
IS_N = 128

layout_header = [
    "Layer name",
    "ifmap_spatial_map",
    "filter_spatial_map",
    "ofmap_spatial_map",
    "temporal_map"
]

def write_layout(path, M_tile, K_tile, N_tile):
    with open(path, "w", newline='') as f:
        wr = csv.writer(f)
        wr.writerow(layout_header)
        wr.writerow([
            "*",
            f"M:{M_tile}",
            f"K:{K_tile}",
            f"N:{N_tile}",
            "K:K,"          # default temporal map
        ])

# WS layout
ws_file = f"{LAYOUT_OUTFILE}_layout_ws.csv"
write_layout(ws_file, WS_M, WS_K, WS_N)
print(f"[OK] WS layout saved → {ws_file}")

# OS layout
os_file = f"{LAYOUT_OUTFILE}_layout_os.csv"
write_layout(os_file, OS_M, OS_K, OS_N)
print(f"[OK] OS layout saved → {os_file}")

# IS layout
is_file = f"{LAYOUT_OUTFILE}_layout_is.csv"
write_layout(is_file, IS_M, IS_K, IS_N)
print(f"[OK] IS layout saved → {is_file}")

print("\n=== All topology + layout generated successfully ===")
