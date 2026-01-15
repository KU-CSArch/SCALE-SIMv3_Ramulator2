# SCALE-Sim v3 L2 Shared Memory 상세 분석

## 📄 논문 출처
**SCALE-Sim V3: A Modular Cycle-Accurate Systolic Accelerator Simulator for End-To-End System Analysis**
- Section III-B: "Hierarchical memory with shared L2"

---

## 🏗️ 메모리 계층 구조 (논문)

### Multi-core 시스템에서 L2 SRAM의 역할:

```
Multi-core Systolic Array:
┌─────────────────────────────────────────┐
│  Core (0,0)   Core (0,1)   Core (0,2)   │  ← 각 코어가 다른
│   [L1 buf]     [L1 buf]     [L1 buf]     │    GEMM 작업 수행
│                                          │
│  Core (1,0)   Core (1,1)   Core (1,2)   │
│   [L1 buf]     [L1 buf]     [L1 buf]     │
│                                          │
│  Core (2,0)   Core (2,1)   Core (2,2)   │
│   [L1 buf]     [L1 buf]     [L1 buf]     │
└─────────────────────────────────────────┘
         ↓ (각 코어가 공유 데이터 요청)
      [L2 SRAM - SHARED]  ← 데이터 중복 제거
         ↓
      [DRAM]
```

### 문제: L1 only vs L2 + L1

**L1 only (문제):**
```
Input Matrix 분할:
├─ Row 0: [1,2,3,4,5,6,7,8] → Core (0,0), Core (0,1), Core (0,2) 모두 필요
│         ↓                ↓                ↓
│         중복             중복             중복  (3배 낭비!)
│
├─ Row 1: [5,6,7,8,9,10,11,12] → 역시 각 코어에서 중복 저장
```

**L2 + L1 (해결):**
```
Input Matrix 분할:
├─ Row 0 Partition (Pr×T): [1,2,3,4,5,6,7,8]
│         ↓
│      [L2 SRAM - 1사본만] ← 여러 코어가 공유
│         ↓  ↓  ↓
│     Core0 Core1 Core2 (각각 필요한 부분만 L1에 로드)
```

---

## 💻 코드에서 L2 구현 상태

### 1. **Spatio-Temporal Partitioning** ✅ (구현됨)

**파일**: [scalesim/topology_utils.py](scalesim/topology_utils.py)

```python
def calc_spatio_temporal_params(self, df='os', layer_id=0):
    """
    Calculate spatio-temporal parameters (S_r, S_c and T) based on dataflow.
    """
    # S_r: spatial row dimension
    # S_c: spatial column dimension  
    # T: temporal dimension
    
    if df == 'os':      # Output Stationary
        s_row = num_ofmap
        s_col = num_filt
        t_time = window_sz
    elif df == 'ws':    # Weight Stationary
        s_row = window_sz
        s_col = num_filt
        t_time = num_ofmap
    elif df == 'is':    # Input Stationary
        s_row = window_sz
        s_col = num_ofmap
        t_time = num_filt
    
    return s_row, s_col, t_time
```

**의미:**
- `S_r`: 몇 개의 행 파티션이 만들어지는가
- `S_c`: 몇 개의 열 파티션이 만들어지는가
- `T`: 몇 개의 시간 배치로 나누는가

### 2. **Multi-core 시뮬레이션** ⚠️ (부분 구현)

코드에서 multi-core를 직접 제어하는 명시적 루프는 없음:
- Spatio-temporal 파라미터는 계산됨
- 하지만 각 코어별로 별도로 시뮬레이션하는 부분이 명확하지 않음

### 3. **Shared L2 메모리** ❓ (명시적 구현 안 보임)

**찾아본 파일들:**
- `scalesim/memory/double_buffered_scratchpad_mem.py`: L1만 모델링
- `scalesim/memory/read_buffer.py`: backing buffer는 DRAM만
- `scalesim/memory/write_buffer.py`: L2 관련 코드 없음

**결론:**
SCALE-Sim v3 논문에서는 L2 shared memory를 설명하지만,
현재 코드 저장소에는 **명시적 L2 구현이 아직 없는 상태**

---

## 📊 L2 SRAM이 필요한 이유

### 예시: ViT-base 레이어에서 multi-core GEMM

```
M = 197 (sequence length)
N = 768 (hidden dim)
K = 768 (input dim)

Systolic array: 64×64 (4096 cores)
```

**S_r, S_c, T 계산 (WS dataflow):**
```python
s_row = K = 768          # K개 행으로 분할
s_col = N = 768          # N개 열로 분할
t_time = M = 197         # M번 시간 배치
```

**각 코어에 할당되는 작업:**
```
Core (0,0) processes:
  Input: M×(K/s_row) = 197×1 (1개 요소) ← 매우 작음
  Filter: (K/s_row)×(N/s_col) = 1×1 (1개 요소)

Core (0,1) processes:
  같은 Input 행 필요!  ← 다시 로드? 아니면 L2에서 공유?
```

이것이 **L2 shared memory**가 필요한 이유!

---

## 🔍 L2 메모리 구조 (이론적)

```
┌─────────────────────────────────────────────┐
│         L2 SRAM (Shared)                    │
│   └─ IFMAP 파티션 (Pr × T)                  │
│   └─ FILTER 파티션 (T × Pc)                 │
│   (모든 코어가 접근 가능)                    │
└─────────────────────────────────────────────┘
         ↙        ↓        ↘
      Core    Core    Core
     (0,0)    (0,1)    (0,2)
    ┌────┐  ┌────┐  ┌────┐
    │L1  │  │L1  │  │L1  │
    │buf │  │buf │  │buf │
    └────┘  └────┘  └────┘
```

**L2의 역할:**
1. 여러 코어 간 **데이터 공유**
2. **메모리 계층 최적화**
   - L1 메모리가 작을 때 (각 코어마다 작음)
   - L2에 더 많은 데이터 캐싱
3. **DRAM 접근 감소** (대역폭 절약)

---

## 📋 현재 코드 인벤토리

| 계층 | 파일 | 상태 | 설명 |
|------|------|------|------|
| **Partitioning** | `topology_utils.py` | ✅ | S_r, S_c, T 계산 구현 |
| **Multi-core** | 불명확 | ⚠️ | 부분 구현 (core별 독립 시뮬레이션?) |
| **L1 SRAM** | `double_buffered_scratchpad_mem.py` | ✅ | 완전 구현 (14 MB) |
| **L2 SRAM** | ❌ | ❌ | 명시적 구현 없음 |
| **DRAM** | `read/write_buffer.py` | ✅ | 완전 구현 |

---

## ❓ 의문점

### Q1: L2가 코드에 없는데, 왜 논문에 있을까?

**가능성:**
1. v3 기능이 **현재 코드에 완전 구현되지 않음**
2. L2는 **향후 추가 예정 기능**
3. 또는 **다른 브랜치에서 개발 중**

### Q2: Spatio-temporal 파라미터는 있는데 사용하지 않나?

코드 흐름을 추적해보면:
```python
# topology_utils.py에서 계산만 하고
s_row, s_col, t_time = self.calc_spatio_temporal_params(...)

# 실제 각 코어별 시뮬레이션은?
# → single_layer_sim.py에서 확인 필요
```

---

## 🎯 결론

### ✅ 논문에 있는 것:
- L2 Shared Memory 메모리 계층 구조 설명
- Spatio-temporal partitioning 방법론
- Multi-core scalability 이론

### ⚠️ 코드에 부분 구현:
- Spatio-temporal 파라미터 계산
- Single-core L1 SRAM 시뮬레이션 (double_buffered_scratchpad_mem.py)

### ❌ 코드에 없는 것:
- Explicit L2 SRAM 구현
- Multi-core 동시 시뮬레이션
- L2-L1 데이터 전달 로직

---

## 📚 다음 단계

혹시 L2 구현을 찾기 위해 다음을 확인해보세요:

```bash
# L2 관련 코드 검색
grep -r "L2\|l2_sram\|shared.*memory\|multi.*core" scalesim/

# single_layer_sim.py 확인 (실제 시뮬레이션 로직)
cat scalesim/single_layer_sim.py | grep -C 5 "spatio_temporal"

# scale_sim.py 또는 simulator.py에서 multi-core 처리
cat scalesim/scale_sim.py
```

혹은 **SCALE-Sim v3이 최근에 발표된 논문**이므로, 
GitHub 저장소의 최신 버전에는 L2 구현이 있을 수 있습니다!
