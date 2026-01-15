# IFMAP_DRAM_TRACE, IFMAP_SRAM_TRACE 생성 과정

## 핵심: 3단계 데이터 흐름

```
Topology (M, N, K)
    ↓
Operand Matrix 생성 (IFMAP, FILTER, OFMAP 주소 행렬)
    ↓
Compute System (Systolic Array 시뮬레이션)
    ├─ IFMAP/FILTER/OFMAP 읽고 쓰는 순서 결정
    ├─ 각 사이클(cycle)에 어떤 주소를 접근하는지 결정
    └─ Prefetch/Demand 행렬 생성
    ↓
Memory System (Double Buffered SRAM 시뮬레이션)
    ├─ IFMAP_TRACE_MATRIX 생성 (SRAM 레벨)
    ├─ Prefetch/Demand를 DRAM에 요청
    └─ IFMAP_DRAM_TRACE 생성 (DRAM 레벨)
    ↓
Trace 파일로 저장
    ├─ IFMAP_SRAM_TRACE.csv
    └─ IFMAP_DRAM_TRACE.csv
```

---

## 1단계: Operand Matrix 생성

### 입력: Topology
```
Layer: QKT
M = 1024 (배치/행)
K = 64   (입력 채널)
N = 1024 (출력 채널)
```

### 처리: operand_matrix.py - create_ifmap_matrix()

```python
# operand_matrix.py 라인 163-200
def create_ifmap_matrix(self):
    """
    IFMAP 주소 행렬 생성
    """
    # 1. 행렬 인덱스 생성
    row_indices = np.arange(self.batch_size * self.ofmap_px_per_filt)  # 0~(M*K-1)
    col_indices = np.arange(self.conv_window_size)                      # 0~(K-1)
    
    # 2. 2D 메시 생성
    i, j = np.meshgrid(row_indices, col_indices, indexing='ij')
    
    # 3. 각 요소의 실제 메모리 주소 계산
    self.ifmap_addr_matrix = self.calc_ifmap_elem_addr(i, j)
    
    # 이 행렬은 (M×K, K) 크기의 2D 배열
    # 각 요소는 해당 IFMAP 데이터의 메모리 주소
```

### 계산 과정: calc_ifmap_elem_addr()

```python
# operand_matrix.py 라인 209-225
def calc_ifmap_elem_addr(self, i, j):
    """
    IFMAP 요소 주소 계산
    i: OFMAP 픽셀 인덱스 (0 ~ ofmap_px_per_filt-1)
    j: 필터 창 인덱스 (0 ~ conv_window_size-1)
    """
    offset = self.ifmap_offset  # 기본값: 0
    ifmap_rows = self.ifmap_rows  # M
    ifmap_cols = self.ifmap_cols  # K
    channel = self.num_input_channels  # 입력 채널 수
    
    # OFMAP 인덱스로부터 행/열 계산
    ofmap_row, ofmap_col = np.divmod(i, self.ofmap_cols)
    
    # OFMAP 좌표를 IFMAP 좌표로 변환 (stride 고려)
    i_row, i_col = ofmap_row * r_stride, ofmap_col * c_stride
    
    # 기본 윈도우 주소
    window_addr = (i_row * ifmap_cols + i_col) * channel
    
    # 필터 창 내의 상대 좌표
    c_row, k = np.divmod(j, filter_col * channel)
    c_col, c_ch = np.divmod(k, channel)
    
    # 최종 IFMAP 주소
    internal_address = (c_row * ifmap_cols + c_col) * channel + c_ch
    ifmap_px_addr = internal_address + window_addr + offset
    
    return ifmap_px_addr
```

### 생성된 IFMAP 주소 행렬 예시

```
IFMAP_addr_matrix (크기: M × K)
= 행: M개의 서로 다른 OFMAP 픽셀
= 열: K개의 필터 창 요소

예: M=4, K=3 인 경우
[
  [0,    1,    2     ],  # 첫 번째 OFMAP 픽셀의 3개 IFMAP 요소 주소
  [10,   11,   12    ],  # 두 번째 OFMAP 픽셀의 3개 IFMAP 요소 주소
  [100,  101,  102   ],  # 세 번째 OFMAP 픽셀의 3개 IFMAP 요소 주소
  [1000, 1001, 1002  ]   # 네 번째 OFMAP 픽셀의 3개 IFMAP 요소 주소
]
```

---

## 2단계: Compute System (Systolic Array) 시뮬레이션

### 입력: Operand Matrices (IFMAP, FILTER, OFMAP 주소)

### 처리: systolic_compute_ws.py (또는 os, is)

```python
# single_layer_sim.py 라인 198-206
# Dataflow에 따라 다른 compute system 선택
if self.dataflow == 'ws':
    self.compute_system = systolic_compute_ws()  # Weight Stationary
elif self.dataflow == 'os':
    self.compute_system = systolic_compute_os()  # Output Stationary
else:
    self.compute_system = systolic_compute_is()  # Input Stationary

# Compute system에 operand 행렬 전달
self.compute_system.set_params(
    config_obj=self.config,
    ifmap_op_mat=ifmap_op_mat,      # IFMAP 주소 행렬
    filter_op_mat=filter_op_mat,    # FILTER 주소 행렬
    ofmap_op_mat=ofmap_op_mat       # OFMAP 주소 행렬
)

# Systolic array 시뮬레이션 실행
ifmap_prefetch_mat, ifmap_demand_mat = self.compute_system.get_ifmap_prefetch_demand()
```

### Compute System의 역할

```
1. DATAFLOW별로 PE 배열에 매핑
   - Weight Stationary (WS): 가중치는 고정, 입력/출력이 이동
   - Output Stationary (OS): 출력은 고정, 입력/가중치가 이동
   - Input Stationary (IS): 입력은 고정, 가중치/출력이 이동

2. 각 PE에서 수행하는 연산 결정
   - 어떤 사이클(cycle)에
   - 어떤 IFMAP, FILTER, OFMAP을 읽고/쓸지 결정

3. Prefetch 행렬 생성
   [사이클, IFMAP주소1, IFMAP주소2, ...]
   
4. Demand 행렬 생성
   [사이클, 실제 필요한 IFMAP주소1, ...]
```

### 예시: WS Dataflow

```
M=1024, N=1024, K=64 연산
PE 배열: 256×256

Tiling:
- M 타일: 1024/256 = 4
- N 타일: 1024/256 = 4
- K 타일: 64

각 타일 연산: 256 × 256 × 64 = 4,194,304 연산

사이클별 접근 패턴:
Cycle 0: PE[0,0] ~ PE[255,255]가 IFMAP[0~255] 읽음
Cycle 1: PE[0,0] ~ PE[255,255]가 IFMAP[256~511] 읽음
...

→ Prefetch/Demand 행렬 생성
```

---

## 3단계: Memory System 시뮬레이션

### 입력: Prefetch/Demand 행렬

### 처리: double_buffered_scratchpad_mem.py

#### 3-1. SRAM 레벨 Trace 생성

```python
# double_buffered_scratchpad_mem.py 라인 ?
# Systolic array로부터 요청된 주소를 SRAM에 기록

# IFMAP_TRACE_MATRIX 생성
# 크기: (사이클 수, 접근 요소 수)
# 각 행: [사이클, SRAM 주소1, SRAM 주소2, ...]

self.ifmap_trace_matrix = np.zeros((num_cycles, num_access), dtype=int)

# 각 사이클마다
for cycle in range(num_cycles):
    # Systolic array가 이 사이클에 요청한 IFMAP 주소들
    requested_addresses = demand_matrix[cycle]
    
    # SRAM에 저장
    self.ifmap_trace_matrix[cycle] = [cycle] + requested_addresses
```

#### 3-2. DRAM 레벨 Trace 생성

```python
# double_buffered_scratchpad_mem.py 라인 ?
# SRAM이 DRAM에서 prefetch할 주소를 기록

# IFMAP_BUF (Read Buffer)의 trace
self.ifmap_buf.trace_matrix에 저장

# SRAM이 필요로 하는 데이터가 SRAM에 없으면
# DRAM에서 prefetch (double buffering)

# DRAM Trace 형태:
# [사이클, DRAM 주소1, DRAM 주소2, ...]
```

### Memory System의 구조

```
┌─────────────────────────────────────────┐
│    Systolic Array (PE 256×256)          │
│    (Compute System 결과)                │
└────────────────┬────────────────────────┘
                 │ Prefetch/Demand 요청
                 ▼
┌─────────────────────────────────────────┐
│         SRAM (Double Buffered)          │
│  ┌─────────────────────────────────────┐│
│  │  Buffer 0 (serving PE array)       ││
│  └─────────────────────────────────────┘│
│  ┌─────────────────────────────────────┐│
│  │  Buffer 1 (prefetching from DRAM)  ││
│  └─────────────────────────────────────┘│
│                                          │
│  TRACE: IFMAP_SRAM_TRACE.csv            │
│  [cycle, addr1, addr2, addr3, ...]     │
└────────────────┬────────────────────────┘
                 │ DRAM 요청 (Read Buffer)
                 ▼
┌─────────────────────────────────────────┐
│           DRAM (Main Memory)            │
│                                          │
│  TRACE: IFMAP_DRAM_TRACE.csv            │
│  [cycle, addr1, addr2, addr3, ...]     │
└─────────────────────────────────────────┘
```

---

## 4단계: Trace 파일 저장

### 저장 코드

```python
# single_layer_sim.py 라인 311-320
def save_traces(self, top_path):
    """
    SRAM과 DRAM trace를 CSV 파일로 저장
    """
    dir_name = top_path + '/layer' + str(self.layer_id)
    
    # SRAM Traces
    ifmap_sram_filename = dir_name + '/IFMAP_SRAM_TRACE.csv'
    filter_sram_filename = dir_name + '/FILTER_SRAM_TRACE.csv'
    ofmap_sram_filename = dir_name + '/OFMAP_SRAM_TRACE.csv'
    
    # DRAM Traces
    ifmap_dram_filename = dir_name + '/IFMAP_DRAM_TRACE.csv'
    filter_dram_filename = dir_name + '/FILTER_DRAM_TRACE.csv'
    ofmap_dram_filename = dir_name + '/OFMAP_DRAM_TRACE.csv'
    
    # Memory system에서 trace 추출 후 저장
    self.memory_system.print_ifmap_sram_trace(ifmap_sram_filename)
    self.memory_system.print_ifmap_dram_trace(ifmap_dram_filename)
    # ... 나머지도 동일
```

### Trace 파일 형식

#### IFMAP_SRAM_TRACE.csv
```
cycle,addr1,addr2,addr3,...
0,0,1,2,3,...,63
1,10,11,12,13,...,73
2,20,21,22,23,...,83
...
```

각 행:
- 첫 번째 열: 사이클 번호
- 나머지 열: 해당 사이클에 SRAM에서 읽은 IFMAP 주소들

#### IFMAP_DRAM_TRACE.csv
```
cycle,addr1,addr2,addr3,...
100,0,1,2,3,...,63
200,1000,1001,1002,...
300,2000,2001,...
...
```

각 행:
- 첫 번째 열: 사이클 번호
- 나머지 열: 해당 사이클에 DRAM에서 읽은 IFMAP 주소들

---

## 완전한 흐름 정리

### 1. Topology 입력
```
QKT: M=1024, K=64, N=1024
```

### 2. Operand Matrix 생성
```
IFMAP 주소 행렬 (1024×64)
- [0,     1,     ...,  63]      # 첫 번째 OFMAP 픽셀의 64개 IFMAP 요소
- [1000,  1001,  ...,  1063]    # 두 번째 OFMAP 픽셀의 64개 IFMAP 요소
- ...
- [1000000, ...]                # 1024번째 OFMAP 픽셀의 64개 IFMAP 요소

FILTER 주소 행렬 (64×1024)
- [10000000, 10000001, ..., 10001023]    # 첫 번째 필터 요소의 1024개 가중치
- ...

OFMAP 주소 행렬 (1024×1024)
- [20000000, 20000001, ..., 20001023]    # 첫 번째 OFMAP의 1024개 요소
- ...
```

### 3. Compute System 시뮬레이션
```
Dataflow: WS (Weight Stationary)
PE Array: 256×256

결과:
- 사이클별 Prefetch 패턴: 언제 어떤 데이터를 미리 가져올지
- 사이클별 Demand 패턴: 실제 필요한 데이터

예:
Prefetch @ Cycle 0: 주소 0~63 (buffer 1에서 DRAM 읽음)
Demand @ Cycle 10: 주소 0~63 (buffer 0에서 SRAM 읽음)
```

### 4. Memory System 시뮬레이션
```
SRAM (Double Buffered):
- Buffer 0: Compute system의 demand 서빙
- Buffer 1: DRAM에서 prefetch

DRAM:
- Read Buffer가 DRAM에서 데이터 읽음
- Latency 고려하여 실제 사이클 계산

결과: 메모리 접근 trace
```

### 5. Trace 파일 생성
```
/results/layer0/IFMAP_SRAM_TRACE.csv
/results/layer0/IFMAP_DRAM_TRACE.csv
/results/layer0/FILTER_SRAM_TRACE.csv
/results/layer0/FILTER_DRAM_TRACE.csv
/results/layer0/OFMAP_SRAM_TRACE.csv
/results/layer0/OFMAP_DRAM_TRACE.csv
```

---

## 핵심 차이: SRAM vs DRAM Trace

### IFMAP_SRAM_TRACE
- **주체**: Systolic array (PE 배열)
- **시점**: 사이클 단위
- **목적**: PE 배열이 언제 어떤 데이터를 읽었는가?
- **특징**: 연속적이고 규칙적 (Compute pattern 반영)
- **양**: 많음 (매 사이클마다 접근)

### IFMAP_DRAM_TRACE
- **주체**: Read Buffer (SRAM의 prefetch 담당)
- **시점**: SRAM이 DRAM에서 데이터를 가져올 때
- **목적**: DRAM 접근 패턴 분석 (메모리 대역폭, latency)
- **특징**: 불규칙적일 수 있음 (double buffering과 latency 반영)
- **양**: 적음 (prefetch 요청 시에만 접근)

---

## 메모리 계층 구조 요약

```
Level 1: Compute
  Input: Topology (M, N, K)
  Output: Prefetch/Demand 행렬
  Role: 어떤 데이터를 언제 필요로 하는지 결정

Level 2: SRAM (빠름, 작음)
  Input: Prefetch/Demand 행렬
  Output: IFMAP_SRAM_TRACE
  Role: 자주 접근하는 데이터 캐시, double buffering으로 DRAM 레이턴시 숨김

Level 3: DRAM (느림, 크다)
  Input: SRAM의 prefetch 요청
  Output: IFMAP_DRAM_TRACE
  Role: 메인 메모리, SRAM에 데이터 공급
```

이렇게 3단계를 거쳐서 IFMAP_SRAM_TRACE와 IFMAP_DRAM_TRACE가 생성됩니다!
