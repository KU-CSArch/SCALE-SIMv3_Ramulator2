# GEMM → Conv 형식 변환 분석

## 핵심 발견: GEMM 데이터를 Conv 형식으로 변환

### 1. 데이터 구조 비교

#### Conv 형식 (기본 형식)
```python
# Conv 형식의 인덱스별 의미
header = [
    "Layer name",           # index 0
    "IFMAP height",         # index 1
    "IFMAP width",          # index 2
    "Filter height",        # index 3
    "Filter width",         # index 4
    "Channels",             # index 5
    "Num filter",           # index 6
    "Stride height",        # index 7
    "Stride width"          # index 8
]
```

#### GEMM 입력 CSV 형식
```
Layer,M,N,K,
QKT,1024,1024,64,
```
- Layer: 레이어 이름
- M: 행렬의 행 수 (배치/output 행 수)
- N: 행렬의 열 수 (출력 채널)
- K: 공통 차원 (입력 채널)

### 2. 변환 매핑 (load_arrays_gemm 함수)

```python
# 원본 GEMM CSV에서 추출
layer_name = elems[0].strip()  # "QKT"
m = elems[1].strip()            # "1024"
n = elems[2].strip()            # "1024"
k = elems[3].strip()            # "64"
sparsity_ratio = elems[4].strip().split(':')  # ["1", "1"]

# Conv 형식으로 변환
entries = [layer_name, m, k, 1, k, 1, n, 1, 1, sparsity_ratio[0], sparsity_ratio[1]]
#          [name,     M, K, 1, K, 1, N, 1, 1, sparse_n,          sparse_m]
```

#### 구체적인 매핑

| GEMM CSV | 값 | → | Conv 인덱스 | 의미 | 값 |
|----------|-----|---|-------------|------|-----|
| Layer | QKT | → | 0 (Layer name) | 레이어 이름 | QKT |
| M | 1024 | → | 1 (IFMAP height) | 입력 높이 | 1024 |
| K | 64 | → | 2 (IFMAP width) | 입력 너비 | 64 |
| - | - | → | 3 (Filter height) | 필터 높이 | 1 |
| K | 64 | → | 4 (Filter width) | 필터 너비 | 64 |
| - | - | → | 5 (Channels) | 입력 채널 | 1 |
| N | 1024 | → | 6 (Num filter) | 출력 채널 | 1024 |
| - | - | → | 7 (Stride height) | 스트라이드 높이 | 1 |
| - | - | → | 8 (Stride width) | 스트라이드 너비 | 1 |
| sparse | 1:1 | → | 9, 10 | 희소성 비율 | 1, 1 |

### 3. 예제로 보는 변환

#### 입력: QKT 레이어
```
Layer,M,N,K,
QKT,1024,1024,64,
```

#### 처리 과정
```python
# Step 1: CSV 파싱
layer_name = "QKT"
m = "1024"      # M (행 수)
n = "1024"      # N (열 수/출력 채널)
k = "64"        # K (공통 차원/입력 채널)
sparsity_ratio = ["1", "1"]

# Step 2: Conv 형식으로 변환 (내부 포맷)
entries = ["QKT", "1024", "64", 1, "64", 1, "1024", 1, 1, "1", "1"]
#          [0,     1,      2,    3,  4,    5,  6,       7, 8,  9,   10]
```

#### 해석 (Conv 관점에서)
```
이것을 Conv 형식으로 해석하면:
- IFMAP: 1024 × 64 (M × K)
- FILTER: 1×64 (1 × K, 사실상 1×1 convolution이지만 채널 축이 K)
- CHANNELS: 1 (사용 안함)
- NUM_FILTER (출력 채널): 1024 (N)
- STRIDE: 1×1 (GEMM이므로 stride 없음)

실제로는:
- 입력 행렬: M × K = 1024 × 64
- 가중치 행렬: K × N = 64 × 1024
- 출력 행렬: M × N = 1024 × 1024
```

### 4. 왜 이렇게 변환할까?

#### 통합된 시뮬레이션 엔진
SCALE-Sim은 Conv 연산과 GEMM 연산을 같은 엔진으로 처리하기 위해:

1. **GEMM을 Conv처럼 취급**: GEMM 연산을 "1×1 Convolution"으로 모델링
   ```
   GEMM (M×N×K) = 1×1 Conv (M×K → M×N)
   ```

2. **공통 데이터 구조 사용**: 모든 데이터를 Conv 형식의 배열로 저장
   ```python
   self.topo_arrays = [
       ["QKT", 1024, 64, 1, 64, 1, 1024, 1, 1, "1", "1"],
       ["QKTV", 1024, 1024, 1, 1024, 1, 64, 1, 1, "1", "1"],
       # ... (모든 레이어가 같은 형식)
   ]
   ```

3. **동일한 시뮬레이션 로직**: Conv 시뮬레이터로 GEMM도 처리
   ```python
   # 시뮬레이터는 구분 안함, 모두 같은 방식으로 처리
   for layer in self.topo_arrays:
       name = layer[0]
       ifmap_h = layer[1]  # M
       ifmap_w = layer[2]  # K
       filt_h = layer[3]   # 1
       filt_w = layer[4]   # K
       num_ch = layer[5]   # 1 (사용 안함)
       num_filt = layer[6] # N
       stride_h = layer[7] # 1
       stride_w = layer[8] # 1
       
       # Conv 연산 시뮬레이션
       # M × N × K 연산 계산
       compute_simulation(ifmap_h, ifmap_w, filt_h, filt_w, num_ch, num_filt, stride_h, stride_w)
   ```

### 5. Conv 형식 배열 구조 상세

```python
# append_topo_arrays()가 최종적으로 저장하는 형식
self.topo_arrays = [
    # [layer_name, ifmap_h, ifmap_w, filt_h, filt_w, num_ch, num_filt, stride_h, stride_w]
    ["QKT",      1024,     64,      1,      64,     1,      1024,     1,        1],
    ["QKTV",     1024,     1024,    1,      1024,   1,      64,       1,        1],
    ["Linear1",  1024,     1600,    1,      1600,   1,      4800,     1,        1],
    # ... 
]

# 이를 통해 시뮬레이터는:
# 1. 각 레이어의 연산량 계산: ifmap_h × filt_w × num_filt
#    = M × K × N = M × N × K (GEMM 연산량)
#
# 2. 타일링 계산: (ifmap_h, ifmap_w) 기반으로 PE 배열에 맞춤
#    = (M, K) 기반 타일링
#
# 3. 메모리 접근: 일반 Conv와 동일한 로직 적용
```

### 6. 코드의 주석에서 명시

```python
# Entries: layer name, Ifmap h, ifmap w, filter h, filter w, num_ch, num_filt,
#          stride h, stride w, N in N:M, M in N:M
entries = [layer_name, m, k, 1, k, 1, n, 1, 1, sparsity_ratio[0], sparsity_ratio[1]]

# entries are later iterated from index 1. Index 0 is used to store layer name in
# convolution mode. So, to rectify assignment of M, N and K in GEMM mode, layer name
# has been added at index 0 of entries.
```

주석에 명시: **"GEMM 모드에서 M, N, K의 할당을 수정하기 위해, Conv 모드와 일관성을 유지하도록 layer name을 index 0에 추가"**

### 7. 최종 정리

```
GEMM 입력 (CSV)
    ↓
    Layer, M, N, K
    
Conv 형식으로 변환
    ↓
    Index:  0,      1,   2, 3, 4, 5, 6, 7, 8, 9,  10
    Name,   M,      K,   1, K, 1, N, 1, 1, S_N, S_M
           (name) (H)   (W)(FH)(FW)(C)(F)(SH)(SW)

메모리 저장
    ↓
    self.topo_arrays = [[QKT, 1024, 64, 1, 64, 1, 1024, 1, 1, 1, 1], ...]

시뮬레이터
    ↓
    Conv 형식 배열로 모든 레이어 처리 (GEMM/Conv 구분 없음)
    ↓
    성능 메트릭 계산 (연산량, 메모리 대역폭, 레이턴시 등)
```

### 8. 핵심 통찰

1. **GEMM을 1×1 Conv로 모델링**
   - GEMM: A(M×K) × B(K×N) → C(M×N)
   - 1×1 Conv: ifmap(M×K) → ofmap(M×N)

2. **공통 엔진 사용의 이점**
   - 코드 재사용
   - Conv와 GEMM 성능 비교 가능
   - 통합된 시뮬레이션 로직

3. **변환 방식**
   - M → IFMAP height (행 차원)
   - K → IFMAP width (열 차원/입력 채널)
   - N → Num filter (출력 채널)
   - 나머지는 1로 설정 (1×1 conv, stride=1 등)
