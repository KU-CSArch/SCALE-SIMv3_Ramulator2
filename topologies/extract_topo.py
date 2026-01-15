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



config = AutoConfig.from_pretrained(MODEL_NAME)

hidden = config.hidden_size
ffn = config.intermediate_size
layers = config.num_hidden_layers
seq_len = config.max_position_embeddings

print("\n=== Loaded Model ===")
print("Model:", MODEL_NAME)
print(f"hidden={hidden}, ffn={ffn}, layers={layers}, seq_len={seq_len}")



# Generate GEMM-MNK topology

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

print(f"MNK topology saved → {TOPO_OUTFILE}")


# ==========================================================
# 2. Generate layout CSVs (WS / OS / IS)
# ==========================================================
# Dynamic tile size

def find_best_divisor(dim, target_range):
    
    for candidate in reversed(target_range):
        if dim % candidate == 0:
            return candidate
    return 1

def compute_tile_sizes(hidden, ffn, seq_len):
   
    tile_candidates = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]
    
    # reuse 
    K_tile = find_best_divisor(hidden, tile_candidates)
    
    # output parallelism
    N_candidates = [c for c in tile_candidates if c < K_tile]
    N_tile = find_best_divisor(hidden, N_candidates) if N_candidates else 1
    
    # M 1
    M_tile = 1
    
    # OS 
    M_tile_os = find_best_divisor(seq_len, [c for c in tile_candidates if c >= 64])
    if M_tile_os == 1:
        M_tile_os = find_best_divisor(hidden, [c for c in tile_candidates if c >= 64])
    
    return {
        'WS': (M_tile, K_tile, N_tile),
        'OS': (M_tile_os, K_tile, 1),
        'IS': (1, 1, K_tile)
    }

tiles = compute_tile_sizes(hidden, ffn, seq_len)
WS_M, WS_K, WS_N = tiles['WS']
OS_M, OS_K, OS_N = tiles['OS']
IS_M, IS_K, IS_N = tiles['IS']

print(f"[Computed Tiles]")
print(f"  WS: M={WS_M}, K={WS_K}, N={WS_N}")
print(f"  OS: M={OS_M}, K={OS_K}, N={OS_N}")
print(f"  IS: M={IS_M}, K={IS_K}, N={IS_N}")

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
        
        #layout
        for i in range(1, layers + 1):
            # Q,K,V,O
            for proj in ["Q", "K", "V", "O"]:
                wr.writerow([
                    f"{proj}_{i}",
                    f"M:{M_tile}",
                    f"K:{K_tile}",
                    f"N:{N_tile}",
                    "K:K"
                ])
            
            # FF1
            wr.writerow([
                f"FF1_{i}",
                f"M:{M_tile}",
                f"K:{K_tile}",
                f"N:{N_tile}",
                "K:K"
            ])
            
            # FF2
            wr.writerow([
                f"FF2_{i}",
                f"M:{M_tile}",
                f"K:{K_tile}",
                f"N:{N_tile}",
                "K:K"
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
