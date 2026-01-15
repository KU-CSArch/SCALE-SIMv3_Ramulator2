# Operand Matrix 생성 상세 분석

## 개요

Operand Matrix는 SCALE-Sim의 핵심입니다. Topology의 M, N, K를 기반으로:
- **IFMAP 주소 행렬**: 입력 데이터의 메모리 위치
- **FILTER 주소 행렬**: 가중치 데이터의 메모리 위치  
- **OFMAP 주소 행렬**: 출력 데이터의 메모리 위치

이 행렬들이 **Systolic Array가 어떤 데이터를 언제 접근할지**를 결정합니다.

---

## 1. Operand Matrix 초기화 (set_params)

### 입력 데이터

```python
# topology에서 추출
self.ifmap_rows = M         # 1024 (예: QKT의 M)
self.ifmap_cols = K         # 64
self.num_filters = N        # 1024
self.num_input_channels = 1 # GEMM 변환이므로 1

# 계산된 값
self.ofmap_rows = M/stride_h = 1024/1 = 1024          # OFMAP 행 = 입력 행
self.ofmap_cols = N = 1024                             # OFMAP 열 = 필터 개수
self.ofmap_px_per_filt = M = 1024                      # 각 필터당 출력 픽셀 수

# Conv 형식에서의 필터 크기 (1×1 Conv)
self.filter_rows = 1                                   # 필터 높이 = 1
self.filter_cols = K = 64                              # 필터 입력 채널 수 = K
self.conv_window_size = 1 * 64 = 64                    # 총 필터 요소 = 1×64
```

### 메모리 오프셋

```python
# 3개 메모리 영역을 분리
self.ifmap_offset = 0          # IFMAP 메모리 시작 주소
self.filter_offset = 10000000  # FILTER 메모리 시작 주소
self.ofmap_offset = 20000000   # OFMAP 메모리 시작 주소

# 이렇게 하면 어느 메모리 영역인지 쉽게 구분 가능
# IFMAP 주소: 0 ~ 9999999
# FILTER 주소: 10000000 ~ 19999999
# OFMAP 주소: 20000000 ~ 29999999
```

### 주소 행렬 크기 초기화

간단히 말하면: **빈 행렬 3개를 미리 만들어 두기**

```python
# IFMAP 주소를 저장할 빈 행렬
# 1024개 행 (픽셀) × 64개 열 (K값)
self.ifmap_addr_matrix = np.ones((1024, 64), dtype='>i4')

# FILTER 주소를 저장할 빈 행렬
# 64개 행 (K값) × 1024개 열 (필터)
self.filter_addr_matrix = np.ones((64, 1024), dtype='>i4')

# OFMAP 주소를 저장할 빈 행렬
# 1024개 행 (픽셀) × 1024개 열 (필터)
self.ofmap_addr_matrix = np.ones((1024, 1024), dtype='>i4')
```

**의미:**
- `np.ones()`: 0으로 채운 행렬 생성
- `(1024, 64)`: 크기 지정 (행, 열)
- 나중에 이 빈 자리에 주소 값들을 채워넣음

---

## 2. IFMAP 주소 행렬 생성
### 목표 - 간단히

**각 출력값 1개를 만드는데 필요한 입력 위치 64개를 기록**

**중요: IFMAP_addr_matrix는 "주소 맵"이지 최종 출력이 아님!**

예를 들어:
- 출력 픽셀 0번: IFMAP의 **행 0** = 주소 0, 1, 2, ..., 63 읽기
- 출력 픽셀 1번: IFMAP의 **행 1** = 주소 64, 65, 66, ..., 127 읽기
- 출력 픽셀 2번: IFMAP의 **행 2** = 주소 128, 129, 130, ..., 191 읽기
- ...
- 출력 픽셀 1023번: IFMAP의 **행 1023** = 주소 65408, ..., 65471 읽기

즉, 각 출력 픽셀 = IFMAP의 한 행 전체를 읽음

**하지만 계산은:**
```
픽셀 i의 최종 출력 = IFMAP[i] × 1024개의 서로 다른 필터
                  = 1024개의 서로 다른 값

따라서:
- 1024개 픽셀 × 1024개 필터 = 1024×1024 OUTPUT ✓
```

IFMAP_addr_matrix (1024×64) = 어디서 읽을지 저장
OFMAP 최종 출력 (1024×1024) = 계산 결과 저장

이걸 행렬로 정리:
```
IFMAP_addr_matrix = [
  [0,   1,   2,   ..., 63],      # 출력 픽셀 0 (IFMAP 행 0)
  [64,  65,  66,  ..., 127],     # 출력 픽셀 1 (IFMAP 행 1)
  [128, 129, 130, ..., 191],     # 출력 픽셀 2 (IFMAP 행 2)
  ...
  [65408, ..., 65471],            # 출력 픽셀 1023 (IFMAP 행 1023)
]
```

패턴: **IFMAP_addr[i, j] = i*64 + j** (각 출력이 한 행씩)

---

**다음 3가지는 코드 상세 설명이므로 필요 없으면 넘어가도 됩니다.**

### ⏭️ 간단 버전으로 건너뛰기

IFMAP_addr_matrix를 만들었으면, 같은 방식으로:

**FILTER_addr_matrix (64×1024):**
- 각 행: 가중치 위치
- 각 열: 필터 종류
- 값: 메모리 주소

**OFMAP_addr_matrix (1024×1024):**
- 각 행: 출력 픽셀
- 각 열: 필터
- 값: 메모리 주소 (쓸 위치)

이 3개 행렬로 계산:
```
for 픽셀 i in 0~1023:
  for 필터 j in 0~1023:
    result = IFMAP[i의 64개] × FILTER[j의 64개 가중치]
    OFMAP[i,j에 저장]
```

**최종 크기: 1024×1024 OUTPUT** ✓

---

### 상세 함수 설명 (선택사항)

```python
def calc_ifmap_elem_addr(self, i, j):
    """
    i: OFMAP 픽셀 인덱스 (0 ~ ofmap_px_per_filt-1)
    j: 필터 창 인덱스 (0 ~ conv_window_size-1)
    
    반환: 해당 IFMAP 요소의 메모리 주소
    """
    offset = self.ifmap_offset  # 0
    ifmap_rows = self.ifmap_rows  # M = 1024
    ifmap_cols = self.ifmap_cols  # K = 64
    channel = self.num_input_channels  # 1
    
    # Step 1: OFMAP 인덱스를 행/열로 변환
    ofmap_row, ofmap_col = np.divmod(i, self.ofmap_cols)
    # i=0이면   ofmap_row=0, ofmap_col=0
    # i=64이면  ofmap_row=1, ofmap_col=0
    # i=128이면 ofmap_row=2, ofmap_col=0
    # ...
    
    # Step 2: OFMAP 좌표를 IFMAP 좌표로 변환 (stride 고려)
    i_row = ofmap_row * self.row_stride  # stride=1이므로 ofmap_row와 동일
    i_col = ofmap_col * self.col_stride  # stride=1이므로 ofmap_col과 동일
    
    # Step 3: 이 OFMAP 픽셀이 요구하는 기본 IFMAP 윈도우
    window_addr = (i_row * ifmap_cols + i_col) * channel
    # 2D 좌표를 1D 선형 주소로 변환
    # (row, col) → row * 행폭 + col
    
    # Step 4: 필터 창 내 위치 계산
    c_row, k = np.divmod(j, self.filter_cols * channel)
    # j는 필터 창 내의 요소 인덱스
    # Conv의 경우: 필터 높이 × 필터 너비 × 채널
    # GEMM의 경우: 1 × K × 1
    
    c_col, c_ch = np.divmod(k, channel)
    # c_row: 필터 행 인덱스
    # c_col: 필터 열 인덱스
    # c_ch: 채널 인덱스
    
    # Step 5: 바운드 체크 (필터가 IFMAP를 벗어나지 않는지 확인)
    valid_indices = np.logical_and(
        c_row + i_row < ifmap_rows,
        c_col + i_col < ifmap_cols
    )
    
    # Step 6: 최종 IFMAP 주소 계산
    internal_address = (c_row * ifmap_cols + c_col) * channel + c_ch
    ifmap_px_addr = internal_address + window_addr + offset
    
    return ifmap_px_addr
```

### 예시: GEMM QKT 레이어 (M=1024, K=64)

```
설정:
- IFMAP: 1024 × 64 (M × K)
- FILTER: 1 × 64 (1×1 conv처럼 모델링)
- OFMAP: 1024 × 1024 (M × N)
- OFMAP_PX_PER_FILT: 1024 * 1 = 1024 (각 필터당 1024 출력)

계산 예시:
i=0 (첫 번째 OFMAP 픽셀):
  ofmap_row = 0, ofmap_col = 0
  i_row = 0, i_col = 0
  window_addr = (0 * 64 + 0) * 1 = 0
  
  필터 창 내 모든 j (0~63):
    j=0:  c_row=0, c_col=0, c_ch=0
          internal_addr = (0*64 + 0)*1 + 0 = 0
          최종 주소 = 0 + 0 + 0 = 0
    
    j=1:  c_row=0, c_col=1, c_ch=0
          internal_addr = (0*64 + 1)*1 + 0 = 1
          최종 주소 = 1 + 0 + 0 = 1
    
    j=63: c_row=0, c_col=63, c_ch=0
          internal_addr = (0*64 + 63)*1 + 0 = 63
          최종 주소 = 63 + 0 + 0 = 63

  → IFMAP_addr_matrix[0] = [0, 1, 2, ..., 63]


i=1 (두 번째 OFMAP 픽셀):
  ofmap_row = 0, ofmap_col = 1  (K=64이므로 64번째 픽셀부터 다음 행)
  i_row = 0, i_col = 1
  window_addr = (0 * 64 + 1) * 1 = 1
  
  필터 창 내 모든 j (0~63):
    j=0:  internal_addr = 0
          최종 주소 = 0 + 1 + 0 = 1
    
    j=1:  internal_addr = 1
          최종 주소 = 1 + 1 + 0 = 2
    
    j=63: internal_addr = 63
          최종 주소 = 63 + 1 + 0 = 64

  → IFMAP_addr_matrix[1] = [1, 2, 3, ..., 64]


일반적인 패턴:
IFMAP_addr_matrix = [
  [0,    1,    2,   ..., 63],      # i=0
  [1,    2,    3,   ..., 64],      # i=1
  [2,    3,    4,   ..., 65],      # i=2
  ...
  [1023, 1024, 1025, ..., 1086],  # i=1023
]
```

---

## 3. FILTER 주소 행렬 생성

### 목표 - 간단히

**1024개 필터 각각이 64개 가중치를 메모리 어디서 읽을지 저장**

```
FILTER_addr_matrix (64 × 1024):
- 64개 행: 각 필터의 0번~63번 가중치
- 1024개 열: 필터 종류 (0번~1023번)

FILTER_addr[k, j] = 필터 j번의 k번째 가중치 주소
```

예:
```
필터 0번:  FILTER_addr[0:64, 0]   = [10000000, 10000001, ..., 10000063]
필터 1번:  FILTER_addr[0:64, 1]   = [10001024, 10001025, ..., 10001087]
...
필터 1023번: FILTER_addr[0:64, 1023] = [10064512, 10064513, ..., 10064575]
```

**출력 계산 (픽셀 i, 필터 j):**
```
output[i,j] = IFMAP_addr[i, 0:64] × FILTER_addr[0:64, j]
            = IFMAP 행 i × 필터 j의 가중치
            = 1개 값
```

### 핵심 함수: calc_filter_elem_addr()

```python
def create_filter_matrix(self):
    """
    필터 주소 행렬 생성
    크기: (conv_window_size, num_filters)
          = (K, N) = (64, 1024)
    """
    # 모든 필터 요소에 대한 인덱스 생성
    row_indices = np.expand_dims(np.arange(self.conv_window_size), axis=1)
    # shape: (64, 1)
    # [0, 1, 2, ..., 63]를 열벡터로 변환
    
    col_indices = np.arange(self.num_filters)
    # shape: (1024,)
    # [0, 1, 2, ..., 1023]
    
    self.filter_addr_matrix = self.calc_filter_elem_addr(row_indices, col_indices)
```

### 계산 로직

```python
def calc_filter_elem_addr(self, i, j):
    """
    i: 필터 창 내 위치 (0 ~ conv_window_size-1)
    j: 필터 인덱스 (0 ~ num_filters-1)
    
    반환: 해당 필터 요소의 메모리 주소
    """
    offset = self.filter_offset  # 10000000
    num_filt = self.num_filters  # 1024
    
    # 선형 주소 계산
    internal_address = i * num_filt + j
    filter_px_addr = internal_address + offset
    
    return filter_px_addr
```

### 예시: GEMM QKT

```
필터 행렬 크기: (64, 1024)

FILTER_addr_matrix = [
  [10000000, 10000001, 10000002, ..., 10001023],     # 필터 위치 0
  [10001024, 10001025, 10001026, ..., 10002047],     # 필터 위치 1
  [10002048, 10002049, 10002050, ..., 10003071],     # 필터 위치 2
  ...
  [10064512, 10064513, 10064514, ..., 10065535],     # 필터 위치 63
]

패턴:
FILTER[i, j] = 10000000 + i * 1024 + j

FILTER[0, 0] = 10000000
FILTER[0, 1] = 10000001
FILTER[0, 1023] = 10001023

FILTER[1, 0] = 10001024
FILTER[1, 1] = 10001025

FILTER[63, 1023] = 10065535
```

---

## 4. OFMAP 주소 행렬 생성

### 목표
각 출력 요소가 메모리의 어느 위치에 쓰일 것인가

### 핵심 함수: calc_ofmap_elem_addr()

```python
def create_ofmap_matrix(self):
    """
    OFMAP 주소 행렬 생성
    크기: (ofmap_px_per_filt, num_filters)
          = (M, N) = (1024, 1024)
    """
    row_indices = np.expand_dims(np.arange(self.ofmap_px_per_filt), axis=1)
    # shape: (1024, 1)
    
    col_indices = np.arange(self.num_filters)
    # shape: (1024,)
    
    self.ofmap_addr_matrix = self.calc_ofmap_elem_addr(row_indices, col_indices)
```

### 계산 로직

```python
def calc_ofmap_elem_addr(self, i, j):
    """
    i: OFMAP 픽셀 인덱스 (0 ~ ofmap_px_per_filt-1)
    j: 필터 인덱스 (0 ~ num_filters-1)
    
    반환: 해당 OFMAP 요소의 메모리 주소
    """
    offset = self.ofmap_offset  # 20000000
    num_filt = self.num_filters  # 1024
    
    # OFMAP은 행렬: ofmap[i, j] = i번째 픽셀, j번째 필터
    internal_address = num_filt * i + j
    ofmap_px_addr = internal_address + offset
    
    return ofmap_px_addr
```

### 예시: GEMM QKT

```
OFMAP 행렬 크기: (1024, 1024)

OFMAP_addr_matrix = [
  [20000000, 20000001, 20000002, ..., 20001023],     # 픽셀 0
  [20001024, 20001025, 20001026, ..., 20002047],     # 픽셀 1
  [20002048, 20002049, 20002050, ..., 20003071],     # 픽셀 2
  ...
  [21043200, 21043201, 21043202, ..., 21044223],     # 픽셀 1023
]

패턴:
OFMAP[i, j] = 20000000 + i * 1024 + j

OFMAP[0, 0] = 20000000
OFMAP[0, 1023] = 20001023
OFMAP[1, 0] = 20001024
OFMAP[1023, 1023] = 21044223
```

---

## 5. 3개 주소 행렬의 관계

### 행렬 크기 비교

```
IFMAP 주소 행렬:  (1024, 64)   ← 각 픽셀마다 필터의 64개 입력 요소
FILTER 주소 행렬: (64, 1024)   ← 64개 입력이 1024개 필터로 변환
OFMAP 주소 행렬:  (1024, 1024) ← 1024개 픽셀 × 1024개 필터 출력

각 행렬의 차원 의미:
IFMAP[픽셀_idx, 채널_idx] = 읽을 메모리 주소
FILTER[채널_idx, 필터_idx] = 읽을 메모리 주소
OFMAP[픽셀_idx, 필터_idx] = 쓸 메모리 주소
```

### 시스톨릭 배열에서의 사용

```
PE(i, j) = i번째 행, j번째 열의 처리 요소 (PE array가 256×256이면 i,j = 0~255)

각 사이클에:

PE(0, 0)가 수행하는 연산:
  IFMAP_addr_matrix[pixel_idx, filter_pos] = 입력 읽기
  FILTER_addr_matrix[filter_pos, filter_idx] = 가중치 읽기
  OFMAP_addr_matrix[pixel_idx, filter_idx] = 출력 쓰기
  → MAC 연산: input × weight + accumulator → output
  
PE(0, 1)가 수행하는 연산:
  다른 pixel_idx, filter_idx, filter_pos 조합
  
...

PE 배열 전체가 병렬로 수행
```

---

## 6. 메모리 레이아웃 시각화

### 메모리 주소 공간

```
주소 0
├─ IFMAP 영역 (0 ~ 9999999)
│  ├─ [0]: IFMAP[0, 0] (첫 OFMAP 픽셀의 첫 입력)
│  ├─ [1]: IFMAP[0, 1] (첫 OFMAP 픽셀의 두 번째 입력)
│  ├─ ...
│  ├─ [63]: IFMAP[0, 63]
│  ├─ [64]: IFMAP[1, 0] (두 번째 OFMAP 픽셀의 첫 입력)
│  ├─ ...
│  └─ [65535]: IFMAP[1023, 63]
│
주소 10000000
├─ FILTER 영역 (10000000 ~ 19999999)
│  ├─ [10000000]: FILTER[0, 0] (첫 필터 위치, 첫 필터)
│  ├─ [10000001]: FILTER[0, 1] (첫 필터 위치, 두 번째 필터)
│  ├─ ...
│  ├─ [10001023]: FILTER[0, 1023]
│  ├─ [10001024]: FILTER[1, 0] (두 번째 필터 위치, 첫 필터)
│  ├─ ...
│  └─ [10065535]: FILTER[63, 1023]
│
주소 20000000
├─ OFMAP 영역 (20000000 ~ 29999999)
│  ├─ [20000000]: OFMAP[0, 0] (첫 픽셀, 첫 필터 출력)
│  ├─ [20000001]: OFMAP[0, 1] (첫 픽셀, 두 번째 필터 출력)
│  ├─ ...
│  ├─ [20001023]: OFMAP[0, 1023]
│  ├─ [20001024]: OFMAP[1, 0] (두 번째 픽셀, 첫 필터 출력)
│  ├─ ...
│  └─ [21044223]: OFMAP[1023, 1023]
```

---

## 7. Conv vs GEMM 주소 계산

### Conv의 경우 (Stride, Padding 있을 수 있음)

```python
# Conv: ifmap[H×W], filter[FH×FW], stride=[SH, SW]
# → ofmap[(H-FH+1)/SH × (W-FW+1)/SW]

IFMAP 계산이 복잡함:
- OFMAP의 (행, 열)이 stride에 따라 IFMAP을 스캔
- Padding 고려
- 2D 필터 윈도우 (FH × FW × C)

i_row = ofmap_row * stride_h + filter_row
i_col = ofmap_col * stride_w + filter_col
```

### GEMM의 경우 (Stride=1, Padding=0)

```python
# GEMM: A[M×K] × B[K×N] = C[M×N]
# 1×1 Conv로 모델링: ifmap[M×K], filter[1×1×K], ofmap[M×N]

IFMAP 계산이 간단함:
- OFMAP의 i번째 픽셀은 IFMAP의 i번째 행
- 필터 위치는 항상 같음 (0 ~ K-1)

ofmap_row = i // ofmap_cols
ofmap_col = i % ofmap_cols
# 하지만 stride=1이므로:
i_row = ofmap_row
i_col = ofmap_col
```

---

## 8. 최종 정리: 3개 행렬이 하는 일

### 계산 수식

```
GEMM 연산:
C[i, j] = Σ(k=0 to K-1) A[i, k] × B[k, j]

메모리에서:
A는 IFMAP
B는 FILTER
C는 OFMAP

Systolic Array에서의 접근:
for i in range(ofmap_px_per_filt):  # 1024
  for j in range(num_filters):      # 1024
    for k in range(conv_window_size): # 64
      ifmap_val = mem[IFMAP_addr[i, k]]
      filter_val = mem[FILTER_addr[k, j]]
      ofmap_val = ofmap_val + ifmap_val * filter_val
    mem[OFMAP_addr[i, j]] = ofmap_val
```

### Dataflow별 접근 순서 (Trace 결정)

```
Weight Stationary (WS):
- FILTER는 PE에서 고정
- IFMAP은 행을 따라 흐름
- OFMAP은 누적

Output Stationary (OS):
- OFMAP은 PE에서 고정
- IFMAP과 FILTER가 흐름

Input Stationary (IS):
- IFMAP은 PE에서 고정
- FILTER과 OFMAP이 흐름

→ 각 Dataflow마다 3개 행렬이 접근되는 순서가 다름
→ 따라서 Trace 파일의 내용이 다름
```

---

## 9. 코드 실행 순서 정리

```
1. single_layer_sim.py
   ├─ operand_matrix 객체 생성
   └─ op_mat_obj.set_params()
      ├─ topology에서 M, N, K, stride 등 추출
      ├─ ofmap 크기 계산
      └─ 메모리 오프셋 설정

2. operand_matrix.py - create_operand_matrices()
   ├─ create_filter_matrix()
   │  ├─ calc_filter_elem_addr() 호출
   │  └─ self.filter_addr_matrix 생성
   │
   ├─ create_ifmap_matrix()
   │  ├─ calc_ifmap_elem_addr() 호출
   │  └─ self.ifmap_addr_matrix 생성
   │
   └─ create_ofmap_matrix()
      ├─ calc_ofmap_elem_addr() 호출
      └─ self.ofmap_addr_matrix 생성

3. 생성된 행렬들을 Compute System에 전달
   └─ 각 사이클에 어떤 주소를 접근할지 결정
```

이렇게 생성된 주소 행렬들이 Systolic Array의 메모리 접근 패턴을 완전히 결정하게 됩니다!
