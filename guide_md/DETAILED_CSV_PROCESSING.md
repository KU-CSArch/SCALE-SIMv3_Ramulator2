# SCALE-Sim CSV 파일 처리 상세 분석

## 1. 토폴로지 파일 처리 (Topology GEMM)

### 파일 위치
- **입력**: `/topologies/GEMM_mnk/gpt2.csv`
- **처리**: [scalesim/topology_utils.py](scalesim/topology_utils.py) - `load_arrays_gemm()` 메서드
- **저장**: `self.topo_arrays` 리스트

### 원본 CSV 데이터
```
Layer,M,N,K,
QKT,1024,1024,64,
QKTV,1024,64,1024,
Linear1,1024,4800,1600,
Linear2,1024,1600,1600,
PW-FF-L1,1024,3072,1600,
PW-FF-L2,1024,1600,3072,
```

### 코드 실행 흐름 (load_arrays_gemm)

```python
def load_arrays_gemm(self, topofile=''):
    # 1. 파일명 추출
    self.topo_file_name = topofile.split('/')[-1]  # "gpt2.csv"
    self.current_topo_name = "gpt2"
    
    # 2. 파일 열기
    f = open(topofile, 'r')
    first = True
    
    # 3. 각 행(row) 처리
    for row in f:
        row = row.strip()  # 공백 제거
        
        if first:
            first = False
            continue  # 헤더 행 스킵: "Layer,M,N,K,"
        elif row == '':
            continue  # 빈 행 스킵
        else:
            # 4. 쉼표로 구분된 필드 추출
            elems = row.split(',')[:-1]  # 마지막 공백 제거
            # 예: ["QKT", "1024", "1024", "64"]
            
            # 5. 각 필드 파싱
            layer_name = elems[0].strip()    # "QKT"
            m = elems[1].strip()              # "1024"
            n = elems[2].strip()              # "1024"
            k = elems[3].strip()              # "64"
            
            # 6. 희소성 비율 처리 (기본값: 1:1)
            if len(elems) < 5:
                elems.append("1:1")
            sparsity_ratio = elems[4].strip().split(':')
            # 예: ["1", "1"]
            
            # 7. 내부 포맷으로 변환
            # CSV: [Layer, M, N, K]
            # 내부: [layer_name, ifmap_h, ifmap_w, filt_h, filt_w, num_ch, num_filt, stride_h, stride_w, sparse_n, sparse_m]
            entries = [layer_name, m, k, 1, k, 1, n, 1, 1, sparsity_ratio[0], sparsity_ratio[1]]
            #          [QKT,       1024,64,1, 64, 1, 1024, 1, 1, "1",             "1"]
            
            # 8. 리스트에 추가
            self.append_topo_arrays(layer_name=layer_name, elems=entries)
    
    # 9. 파일 닫기 및 플래그 설정
    self.num_layers = len(self.topo_arrays)
    self.topo_load_flag = True
```

### 메모리에 저장된 형식

```python
self.topo_arrays = [
    # [layer_name, m, k, 1, k, 1, n, 1, 1, sparse_n, sparse_m]
    ["QKT",      1024, 64,   1, 64,   1, 1024, 1, 1, "1", "1"],
    ["QKTV",     1024, 1024, 1, 1024, 1, 64,   1, 1, "1", "1"],
    ["Linear1",  1024, 1600, 1, 1600, 1, 4800, 1, 1, "1", "1"],
    ["Linear2",  1024, 1600, 1, 1600, 1, 1600, 1, 1, "1", "1"],
    ["PW-FF-L1", 1024, 1600, 1, 1600, 1, 3072, 1, 1, "1", "1"],
    ["PW-FF-L2", 1024, 3072, 1, 3072, 1, 1600, 1, 1, "1", "1"],
]

self.num_layers = 6
self.topo_load_flag = True
```

### 필드 의미 설명 (GEMM 변환 후)

| 인덱스 | 필드명 | 값 | 의미 |
|--------|--------|-----|------|
| 0 | layer_name | "QKT" | 레이어 이름 |
| 1 | ifmap_h (M) | 1024 | M 차원 크기 (배치/행) |
| 2 | ifmap_w (K) | 64 | K 차원 크기 (입력 채널) |
| 3 | filt_h | 1 | 필터 높이 (사용 안함) |
| 4 | filt_w (K) | 64 | K 값 (사용 안함) |
| 5 | num_ch | 1 | 채널 수 (사용 안함) |
| 6 | num_filt (N) | 1024 | N 차원 크기 (출력 채널) |
| 7 | stride_h | 1 | 스트라이드 높이 (GEMM에서 항상 1) |
| 8 | stride_w | 1 | 스트라이드 너비 (GEMM에서 항상 1) |
| 9 | sparse_n | "1" | 희소성 비율 N |
| 10 | sparse_m | "1" | 희소성 비율 M |

---

## 2. 레이아웃 파일 처리 (Layout GEMM)

### 파일 위치
- **입력**: `/layouts/GEMM_mnk/gpt2.csv`
- **처리**: [scalesim/layout_utils.py](scalesim/layout_utils.py) - `load_layout_gemm()` 메서드
- **저장**: `self.layout_arrays` 리스트

### 원본 CSV 데이터
```
Layer,Array_M,Array_N,IFMAP_SRAM,FILTER_SRAM,OFMAP_SRAM,Dataflow
Linear1,256,256,6144,6144,2048,OS
QKT,256,256,6144,6144,2048,OS
QKTV,256,256,6144,6144,2048,OS
Linear2,256,256,6144,6144,2048,OS
PW-FF-L1,256,256,6144,6144,2048,OS
PW-FF-L2,256,256,6144,6144,2048,OS
```

### 코드 실행 흐름 (load_layout_gemm)

```python
def load_layout_gemm(self, layoutfile):
    # 1. 파일명 추출
    self.layout_file_name = layoutfile.split('/')[-1]  # "gpt2.csv"
    self.current_layout_name = "gpt2"
    
    # 2. 파일 열기
    f = open(layoutfile, 'r')
    first = True
    
    # 3. 각 행(row) 처리
    for row in f:
        row = row.strip()
        
        if first or row == '':
            first = False
            continue  # 헤더 행 스킵
        else:
            # 4. 쉼표로 구분된 필드 추출
            elems = row.split(',')[:-1]
            # 예: ["Linear1", "256", "256", "6144", "6144", "2048", "OS"]
            
            # 5. 각 필드 파싱
            layer_name = elems[0].strip()  # "Linear1"
            
            # 6. GEMM 형식 파싱 (현재 포맷에서 M:X 형식이 아니므로 직접 정수 파싱)
            m_val = int(elems[1].strip())      # 256 (PE 배열의 M 크기)
            k_val = int(elems[2].strip())      # 256 (PE 배열의 N 크기)
            n_val = int(elems[3].strip())      # 6144 (IFMAP SRAM)
            
            # 7. 레이아웃 배열 생성
            entry = [layer_name, m_val, k_val, n_val]
            #        ["Linear1", 256,   256,   6144]
            
            # 8. 리스트에 추가
            self.layout_arrays.append(entry)
    
    # 9. 파일 닫기 및 플래그 설정
    f.close()
    self.num_layers = len(self.layout_arrays)
    self.layout_load_flag = True
```

### 메모리에 저장된 형식

```python
self.layout_arrays = [
    ["Linear1",  256, 256, 6144],
    ["QKT",      256, 256, 6144],
    ["QKTV",     256, 256, 6144],
    ["Linear2",  256, 256, 6144],
    ["PW-FF-L1", 256, 256, 6144],
    ["PW-FF-L2", 256, 256, 6144],
]

self.num_layers = 6
self.layout_load_flag = True
```

---

## 3. 설정 파일 처리 (Config)

### 파일 위치
- **입력**: `configs/google.cfg`
- **처리**: [scalesim/scale_config.py](scalesim/scale_config.py) - `read_conf_file()` 메서드

### 원본 설정 데이터
```ini
[general]
run_name = GoogleTPU_v1_ws

[architecture_presets]
ArrayHeight:    256
ArrayWidth:     256
IfmapSramSzkB:    6144
FilterSramSzkB:   6144
OfmapSramSzkB:    2048
IfmapOffset:    0
FilterOffset:   10000000
OfmapOffset:    20000000
Dataflow : ws
Bandwidth : 10
ReadRequestBuffer: 512
WriteRequestBuffer: 512

[layout]
IfmapCustomLayout: False
IfmapSRAMBankBandwidth: 10
IfmapSRAMBankNum: 10
IfmapSRAMBankPort: 2
FilterCustomLayout: False
FilterSRAMBankBandwidth: 10
FilterSRAMBankNum: 10
FilterSRAMBankPort: 2

[sparsity]
SparsitySupport : false
SparseRep : ellpack_block
OptimizedMapping : false
BlockSize : 8
RandomNumberGeneratorSeed : 40

[run_presets]
InterfaceBandwidth: USER
UseRamulatorTrace: False
```

### 메모리에 저장된 형식

```python
# scale_config.py 객체의 멤버 변수들
self.run_name = "GoogleTPU_v1_ws"
self.array_h = 256
self.array_w = 256
self.ifmap_sram_size = 6144        # KB
self.filter_sram_size = 6144       # KB
self.ofmap_sram_size = 2048        # KB
self.ifmap_offset = 0
self.filter_offset = 10000000
self.ofmap_offset = 20000000
self.dataflow = "ws"               # Weight Stationary
self.bandwidth = 10                # GB/s
self.read_buffer = 512
self.write_buffer = 512

# Layout 섹션
self.ifmap_custom_layout = False
self.ifmap_sram_bank_bw = 10
self.ifmap_sram_bank_num = 10
self.ifmap_sram_bank_port = 2
self.filter_custom_layout = False
self.filter_sram_bank_bw = 10
self.filter_sram_bank_num = 10
self.filter_sram_bank_port = 2

# Sparsity 섹션
self.sparsity_support = False
self.sparse_rep = "ellpack_block"
self.optimized_mapping = False
self.block_size = 8
self.random_seed = 40

# Run Presets 섹션
self.interface_bandwidth = "USER"
self.use_ramulator_trace = False
```

---

## 4. 통합 처리 순서

### 전체 실행 경로

```
1. scale.py (커맨드 라인 진입점)
   ├─ argparse로 인자 파싱
   │  ├─ topology: "./topologies/GEMM_mnk/gpt2.csv"
   │  ├─ layout: "./layouts/GEMM_mnk/gpt2.csv"
   │  └─ config: "./configs/google.cfg"
   │
   └─ scalesim() 객체 생성
      │
      └─ scalesim.py (scale_sim.py)
         │
         ├─ __init__()
         │  ├─ scale_config() 초기화
         │  ├─ topologies() 초기화
         │  ├─ layouts() 초기화
         │  └─ simulator() 초기화
         │
         ├─ set_params()
         │  ├─ config.read_conf_file("configs/google.cfg")
         │  │  └─ 설정 파일 파싱 → self.config 객체 채움
         │  │
         │  ├─ topo.load_arrays("topologies/GEMM_mnk/gpt2.csv", mnk_inputs=True)
         │  │  └─ load_arrays_gemm()
         │  │     └─ CSV 파싱 → self.topo_arrays 리스트 채움
         │  │
         │  └─ layout.load_arrays("layouts/GEMM_mnk/gpt2.csv", mnk_inputs=True)
         │     └─ load_layout_gemm()
         │        └─ CSV 파싱 → self.layout_arrays 리스트 채움
         │
         └─ run_scale()
            └─ simulator.set_params()
               ├─ config_obj 전달 (설정 정보)
               ├─ topo_obj 전달 (레이어 M, N, K)
               ├─ layout_obj 전달 (배열 크기, SRAM 정보)
               │
               └─ 시뮬레이션 실행
                  ├─ 각 레이어마다:
                  │  ├─ 연산량 = M × N × K
                  │  ├─ 타일 크기 = Array_M × Array_N
                  │  ├─ 메모리 접근 패턴 분석
                  │  ├─ 성능 메트릭 계산
                  │  └─ 결과 기록
                  │
                  └─ 결과 CSV 파일 생성
```

---

## 5. 실제 동작 예시 (QKT 레이어)

### 입력 데이터
```
Topology CSV: QKT,1024,1024,64,
Layout CSV:   QKT,256,256,6144,6144,2048,OS
Config:       ArrayHeight=256, ArrayWidth=256, Bandwidth=10GB/s, Dataflow=WS
```

### 처리 과정

```python
# 1. 토폴로지 파싱
topo_arrays[0] = ["QKT", 1024, 64, 1, 64, 1, 1024, 1, 1, "1", "1"]
# 해석: M=1024, K=64, N=1024

# 2. 레이아웃 파싱
layout_arrays[0] = ["QKT", 256, 256, 6144]
# 해석: PE 배열 256×256, IFMAP SRAM 6144 KB

# 3. 설정 적용
config.array_h = 256
config.array_w = 256
config.bandwidth = 10  # GB/s
config.dataflow = "ws"  # Weight Stationary

# 4. 시뮬레이션 계산
M, N, K = 1024, 1024, 64
연산량 = M × N × K = 1024 × 1024 × 64 = 67,108,864 연산

PE_M, PE_N = 256, 256
타일_M = M / PE_M = 1024 / 256 = 4 타일
타일_N = N / PE_N = 1024 / 256 = 4 타일
타일_K = K = 64

타일당 연산 = 256 × 256 × 64 = 4,194,304 연산
총 타일 개수 = 4 × 4 × 1 = 16 타일

메모리 접근:
- IFMAP: K × PE_M = 64 × 256 = 16,384 elements
- FILTER: N × K = 1024 × 64 = 65,536 elements (WS: Weight Stationary)
- OFMAP: PE_M × N = 256 × 1024 = 262,144 elements

메모리 대역폭으로 인한 지연:
IFMAP 로드 시간 = (16,384 elements × 4 bytes) / (10 GB/s) ≈ 6.5 us

# 5. 결과 생성
{
  "layer": "QKT",
  "M": 1024,
  "N": 1024,
  "K": 64,
  "ops": 67108864,
  "cycles": ...,
  "memory_bandwidth": 10,
  "dataflow": "WS",
  ...
}
```

---

## 6. 데이터 흐름 요약

```
CSV 파일
    │
    ├─→ topology_utils.load_arrays_gemm()
    │   └─→ 각 행을 파싱하여 리스트로 변환
    │       CSV: [Layer, M, N, K]
    │       변환: [Layer, M, K, 1, K, 1, N, 1, 1, sparse_n, sparse_m]
    │
    ├─→ layout_utils.load_layout_gemm()
    │   └─→ 각 행을 파싱하여 리스트로 변환
    │       CSV: [Layer, Array_M, Array_N, IFMAP_SRAM, ...]
    │       변환: [Layer, Array_M, Array_N, IFMAP_SRAM]
    │
    └─→ scale_config.read_conf_file()
        └─→ 각 섹션을 파싱하여 객체 멤버 변수로 변환
            INI: [section] key = value
            변환: object.key = value

메모리 데이터 구조
    │
    ├─→ simulator.set_params()로 전달
    │   ├─ config_obj: 하드웨어 설정
    │   ├─ topo_obj: 레이어 연산 정보
    │   └─ layout_obj: 배열 구조 정보
    │
    └─→ 시뮬레이션 실행
        ├─ 각 레이어마다 성능 메트릭 계산
        └─ 결과 CSV 파일로 저장
```

---

## 참고

### GEMM (General Matrix Multiplication) 포맷 설명
- **M**: 행렬의 행 개수 (Batch size)
- **N**: 행렬의 열 개수 (출력 채널, Output channels)
- **K**: 행렬의 공통 차원 (입력 채널, Input channels)
- **연산**: C = A(M×K) × B(K×N), 총 연산량 = M × N × K

### Dataflow 종류
- **OS** (Output Stationary): 출력이 PE에서 고정, 입력과 가중치는 흘러다님
- **WS** (Weight Stationary): 가중치가 PE에서 고정, 입력과 출력이 흘러다님
- **IS** (Input Stationary): 입력이 PE에서 고정, 가중치와 출력이 흘러다님
