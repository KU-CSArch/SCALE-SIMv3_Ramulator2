# SCALE-Sim에서 CSV 파일 처리 흐름

## 1. 전체 프로세스 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                      scale.py (진입점)                          │
│  - 커맨드 라인 인자 파싱                                        │
│  - topology, layout, config 파일 경로 지정                     │
└─────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   scale_sim.py (__init__)                        │
│  - scalesim 객체 생성                                           │
│  - scale_config, topologies, layouts 객체 초기화               │
└─────────────────────────────┬──────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                 scale_sim.py (set_params)                        │
│  1. config 파일 읽기 (scale_config.read_conf_file)             │
│  2. topology 파일 읽기 (topologies.load_arrays)                │
│  3. layout 파일 읽기 (layouts.load_arrays)                     │
└──────────────────────────────────────────────────────────────────┘
```

## 2. gpt2.csv (Topology) 처리 흐름

### 입력 파일: `/topologies/GEMM_mnk/gpt2.csv`
```csv
Layer,M,N,K,
QKT,1024,1024,64,
QKTV,1024,64,1024,
Linear1,1024,4800,1600,
Linear2,1024,1600,1600,
PW-FF-L1,1024,3072,1600,
PW-FF-L2,1024,1600,3072,
```

### 처리 단계:

```
scale_sim.py (set_params)
    │
    └─> self.topo.load_arrays(topofile, mnk_inputs=True)
            │
            └─> topology_utils.py :: load_arrays_gemm()
                    │
                    ├─ CSV 파일 열기 (for row in f)
                    ├─ 첫 번째 행 스킵 (헤더)
                    │
                    ├─ 각 행(레이어)마다:
                    │   ├─ 행을 쉼표로 분할: row.split(',')[:-1]
                    │   ├─ 각 필드 추출:
                    │   │   ├─ layer_name = "QKT", "Linear1" 등
                    │   │   ├─ m = "1024"
                    │   │   ├─ n = "1024"
                    │   │   ├─ k = "64"
                    │   │   └─ sparsity_ratio = "1:1" (기본값)
                    │   │
                    │   └─ entries 배열 생성:
                    │       [layer_name, m, k, 1, k, 1, n, 1, 1, sparsity_N, sparsity_M]
                    │       예: ["QKT", "1024", "64", 1, "64", 1, "1024", 1, 1, "1", "1"]
                    │
                    └─ self.append_topo_arrays()로 저장
                            │
                            └─> self.topo_arrays 리스트에 추가
```

### GEMM 형식 변환 로직 (중요!):

```python
# 원본 CSV: Layer, M, N, K
# 변환 후: [layer_name, m, k, 1, k, 1, n, 1, 1, sparsity_n, sparsity_m]

# 예시:
# CSV: QKT, 1024, 1024, 64
# 변환: ["QKT", 1024, 64, 1, 64, 1, 1024, 1, 1, "1", "1"]
#       [name,  M,   K,  1,  K,  1,  N,    1, 1, sparse_n, sparse_m]
```

## 3. gpt2.csv (Layout) 처리 흐름

### 입력 파일: `/layouts/GEMM_mnk/gpt2.csv`
```csv
Layer,Array_M,Array_N,IFMAP_SRAM,FILTER_SRAM,OFMAP_SRAM,Dataflow
Linear1,256,256,6144,6144,2048,OS
QKT,256,256,6144,6144,2048,OS
QKTV,256,256,6144,6144,2048,OS
Linear2,256,256,6144,6144,2048,OS
PW-FF-L1,256,256,6144,6144,2048,OS
PW-FF-L2,256,256,6144,6144,2048,OS
```

### 처리 단계:

```
scale_sim.py (set_params)
    │
    └─> self.layout.load_arrays(layoutfile, mnk_inputs=True)
            │
            └─> layout_utils.py :: load_layout_gemm()
                    │
                    ├─ CSV 파일 열기 (for row in f)
                    ├─ 첫 번째 행 스킵 (헤더)
                    │
                    ├─ 각 행(레이어)마다:
                    │   ├─ 행을 쉼표로 분할: row.split(',')[:-1]
                    │   ├─ 각 필드 추출:
                    │   │   ├─ layer_name = "Linear1"
                    │   │   ├─ Array_M = "256"
                    │   │   ├─ Array_N = "256"
                    │   │   ├─ IFMAP_SRAM = "6144"
                    │   │   ├─ FILTER_SRAM = "6144"
                    │   │   ├─ OFMAP_SRAM = "2048"
                    │   │   └─ Dataflow = "OS"
                    │   │
                    │   └─ entry 생성:
                    │       [layer_name, Array_M, Array_N, IFMAP_SRAM, FILTER_SRAM, OFMAP_SRAM, Dataflow]
                    │
                    └─> self.layout_arrays 리스트에 추가
```

## 4. 설정 파일 처리 흐름

### 입력 파일: `configs/google.cfg`
```ini
[general]
run_name = GoogleTPU_v1_ws

[architecture_presets]
ArrayHeight: 256
ArrayWidth: 256
...
```

### 처리:

```
scale_sim.py (set_params)
    │
    └─> self.config.read_conf_file(config_file)
            │
            └─> scale_config.py :: read_conf_file()
                    │
                    ├─ configparser로 .cfg 파일 파싱
                    ├─ [general], [architecture_presets], [layout], [sparsity] 섹션 읽음
                    │
                    └─> 각 파라미터를 객체 변수에 저장
                        ├─ self.run_name = "GoogleTPU_v1_ws"
                        ├─ self.array_h = 256
                        ├─ self.array_w = 256
                        ├─ self.ifmap_sram_size = 6144
                        ├─ self.filter_sram_size = 6144
                        ├─ self.ofmap_sram_size = 2048
                        └─ ... (기타 설정)
```

## 5. 시뮬레이션 실행

```
scale_sim.py (run_scale)
    │
    └─> self.runner.set_params(
            config_obj = self.config      # 파싱된 설정
            topo_obj = self.topo          # 파싱된 토폴로지
            layout_obj = self.layout      # 파싱된 레이아웃
            top_path = 결과 저장 경로
        )
        │
        └─> self.run_once()
                │
                └─> simulator.py에서 실제 시뮬레이션 실행
                        ├─ 각 레이어별로:
                        │   ├─ M, N, K 값을 이용해 연산량 계산
                        │   ├─ Array_M, Array_N을 이용해 타일링 계산
                        │   ├─ SRAM 크기 기반 메모리 접근 패턴 분석
                        │   ├─ Dataflow (OS/WS/IS) 적용
                        │   └─ 성능 메트릭 생성 (레이턴시, 메모리 대역폭, 연산량 등)
                        │
                        └─> 결과 CSV 파일 생성
```

## 6. 데이터 흐름 정리

### 토폴로지 (M, N, K)
- **M**: Batch size (1024 in most layers)
- **N**: Output channels (1024, 4800, 1600, 3072 등)
- **K**: Input channels (64, 1600, 1600, 3072 등)
- **용도**: 연산량 (M×N×K) 계산에 사용

### 레이아웃 (Array_M, Array_N, SRAM)
- **Array_M**: PE 배열의 M 차원 크기 (256)
- **Array_N**: PE 배열의 N 차원 크기 (256)
- **IFMAP_SRAM**: 입력 특성맵용 SRAM (6144 KB)
- **FILTER_SRAM**: 가중치용 SRAM (6144 KB)
- **OFMAP_SRAM**: 출력 특성맵용 SRAM (2048 KB)
- **Dataflow**: 데이터 재사용 패턴 (OS: Output Stationary, WS: Weight Stationary, IS: Input Stationary)
- **용도**: 타일링 계산, 메모리 접근 패턴 최적화

### 설정 (Config)
- **ArrayHeight/Width**: PE 배열 크기 (256×256)
- **Bandwidth**: 메모리 대역폭 (10GB/s)
- **SparsitySupport**: 희소성 지원 여부
- **용도**: 전역 설정, 모든 레이어에 적용되는 하드웨어 파라미터

## 7. 주요 데이터 구조 (메모리에 저장)

```python
# topology_utils.py
self.topo_arrays = [
    ["QKT", 1024, 64, 1, 64, 1, 1024, 1, 1, "1", "1"],
    ["QKTV", 1024, 1024, 1, 1024, 1, 64, 1, 1, "1", "1"],
    ["Linear1", 1024, 1600, 1, 1600, 1, 4800, 1, 1, "1", "1"],
    # ... 나머지 레이어들
]

# layout_utils.py
self.layout_arrays = [
    ["Linear1", 256, 256, 6144, 6144, 2048, "OS"],
    ["QKT", 256, 256, 6144, 6144, 2048, "OS"],
    # ... 나머지 레이어들
]

# scale_config.py
self.run_name = "GoogleTPU_v1_ws"
self.array_h = 256
self.array_w = 256
self.ifmap_sram_size = 6144
self.filter_sram_size = 6144
self.ofmap_sram_size = 2048
self.bandwidth = 10
# ... 기타 설정
```

## 결론

1. **CSV 파일 읽기**: 각 CSV 파일을 행(row) 단위로 파싱
2. **데이터 추출**: 쉼표로 구분된 필드를 개별 변수로 추출
3. **메모리 저장**: 파싱된 데이터를 리스트 형태로 메모리에 저장
4. **시뮬레이션**: 저장된 데이터를 이용해 각 레이어별 성능 계산
5. **결과 생성**: 시뮬레이션 결과를 출력 CSV 파일로 저장
