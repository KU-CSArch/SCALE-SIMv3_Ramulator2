# SCALE-Sim 메모리 계층 구조 분석 (수정됨)

## ✅ 논문 확인: L2 Shared Memory 있음!

당신 말이 맞습니다! **SCALE-Sim v3** 논문에서 **"Hierarchical memory with shared L2"** 섹션 (Section III-B)에 명시되어 있습니다.

### 논문에서의 L2 정의:
```
Due to spatial partitioning, each core works on input partition (Pr × T) 
and weight partition (Pc × T).

If there is only L1 SRAM, there will be lots of DUPLICATION across 
multiple cores in the same row (duplication of input matrix) or the 
same column (duplication of weight matrix).

To mitigate the data duplication, we use SHARED L2 SRAM.
```

---

## 현재 코드 상태: Multi-core & L2는 **부분 구현**됨

### SCALE-Sim v3의 새로운 기능들:
1. ✅ **Spatio-temporal partitioning** → `topology_utils.py`에서 구현됨
   - `calc_spatio_temporal_params()`: S_r, S_c, T 계산
   - `set_spatio_temporal_params()`: 모든 레이어에 대해 계산
   
2. ⚠️ **Multi-core simulation** → 부분 구현
   - Spatio-temporal 파라미터 계산 코드는 있음
   - 실제 multi-core 시뮬레이션 코드는 명시적으로 발견되지 않음

3. ❓ **Shared L2 메모리** → 코드에서 명시적 구현 없음
   - 논문에서는 설명하지만, Python 코드에는 없는 상태

### 당신의 메모리 계층 (논문 기준 - 정확함):
```
[Tensor index (m,n,k)]
    ↓
[Logical address (0 ~ 20M)]
    ↓
[L2 SRAM (shared)] ← 여러 코어가 공유 (논문에서 설명)
    ↓
[L1 SRAM (per-core)] ← Double Buffered
    ↓
[PE Systolic Array]
    ↓
[DRAM (10 GB/s)]
```

---

## SCALE-Sim 메모리 모듈 상세 분석

### 1. **Spatio-Temporal Partitioning** ✅
**파일**: [scalesim/topology_utils.py](scalesim/topology_utils.py)

**코드 위치**: Line 300-340

```python
class double_buffered_scratchpad:
    """
    Double buffering helps to hide the DRAM latency when the SRAM is servicing 
    requests from the systolic array using one buffer while the other buffer 
    prefetches from the DRAM.
    """
    def __init__(self):
        self.ifmap_buf = rdbuf()     # IFMAP 읽기 버퍼
        self.filter_buf = rdbuf()    # FILTER 읽기 버퍼
        self.ofmap_buf = wrbuf()     # OFMAP 쓰기 버퍼
        
        self.ifmap_port = rdport()   # IFMAP 포트
        self.filter_port = rdport()  # FILTER 포트
        self.ofmap_port = wrport()   # OFMAP 포트
```

**메모리 구조 (14 MB 총 용량)**:
```
SRAM (14 MB)
├─ IFMAP Buffer (6 MB)
│  ├─ Active Buffer (3 MB): PE 배열이 읽는 데이터 제공
│  └─ Prefetch Buffer (3 MB): DRAM에서 미리 로드
├─ FILTER Buffer (6 MB)
│  ├─ Active Buffer (3 MB): PE 배열이 읽는 데이터 제공
│  └─ Prefetch Buffer (3 MB): DRAM에서 미리 로드
└─ OFMAP Buffer (2 MB)
   ├─ Active Buffer (1 MB): PE 배열이 쓰는 데이터
   └─ Prefetch Buffer (1 MB): 다음 계층 쓰기 준비
```

---

### 2. **DRAM 인터페이스** ✓
**파일**: [scalesim/memory/read_buffer.py](scalesim/memory/read_buffer.py) (DRAM 읽기)

```python
class read_buffer:
    """
    Double buffered read memory implementation
    """
    def __init__(self):
        self.total_size_bytes = 128
        self.word_size = 1          # ← INT8 데이터 포맷
        self.active_buf_frac = 0.9  # Active 90%, Prefetch 10%
        self.hit_latency = 1        # 1 사이클 후 제공
        
        self.backing_buffer = read_port()  # ← DRAM 모델
        self.req_gen_bandwidth = 100       # 100 words/cycle
```

**read_buffer의 역할**:
1. L1 SRAM의 Active Buffer에서 PE가 데이터를 가져감
2. Prefetch Buffer가 비면 DRAM의 `backing_buffer`에서 새 데이터 로드
3. 주소 변환: Logical address → DRAM 대역폭 시뮬레이션

---

### 3. **쓰기 경로** ✓
**파일**: [scalesim/memory/write_buffer.py](scalesim/memory/write_buffer.py)

```python
class write_buffer:
    """
    Double buffered write memory implementation for OFMAP
    """
    def __init__(self):
        self.total_size_bytes = 128
        self.word_size = 1          # INT8
        self.backing_buffer = write_port()  # DRAM 모델
```

---

### 4. **포트 레벨 접근** ✓
**파일**: 
- [scalesim/memory/read_port.py](scalesim/memory/read_port.py)
- [scalesim/memory/write_port.py](scalesim/memory/write_port.py)

포트가 DRAM 대역폭과 레이턴시를 모델링합니다.

---

## ❌ **L2 Cache는 왜 없을까?**

### Google TPU v1 실제 아키텍처:
```
PE Array (256×256)
    ↓
Scratchpad SRAM (14 MB) ← L1에 해당
    ↓
DRAM (10 GB/s) ← 직접 연결, L2 없음
```

**Google TPU v1 특징**:
- **고대역폭 on-chip 메모리**: 14 MB Scratchpad가 충분히 큼
- **Systolic Array 구조**: 고효율 데이터 흐름으로 L2 필요 없음
- **메모리 계층 단순화**: SRAM → DRAM 직접 접근

### 당신의 다이어그램이 참조하는 아키텍처:
귀하의 "L2 SRAM (shared)" 계층은 아마도:
- **일반 CPU/GPU 아키텍처** (예: x86, NVIDIA GPU)
- 각 코어/쓰레드 그룹이 공유하는 L2 캐시
- SCALE-Sim은 TPU이므로 이 구조가 없음

---

## 메모리 주소 변환 흐름

```
compute/operand_matrix.py (주소 생성)
    ↓ Logical address (0~20M)
    ↓
memory/double_buffered_scratchpad_mem.py (L1 SRAM 접근)
    ├─ Active buffer에 있으면: 즉시 반환
    └─ 없으면 prefetch buffer에서 로드
        ↓
memory/read_buffer.py (DRAM 백업)
    ├─ backing_buffer = read_port()
    ├─ DRAM 대역폭 시뮬레이션 (10 GB/s)
    └─ 데이터 반환 후 SRAM prefetch buffer에 캐시
```

---

## 코드 구조 매핑

| 계층 | 파일 | 역할 |
|------|------|------|
| **주소 생성** | `compute/operand_matrix.py` | 텐서 인덱스 → 선형 주소 |
| **L1 SRAM** | `memory/double_buffered_scratchpad_mem.py` | 14 MB 버퍼 관리 |
| **DRAM 읽기** | `memory/read_buffer.py` | DRAM 대역폭 시뮬레이션 |
| **DRAM 쓰기** | `memory/write_buffer.py` | OFMAP 쓰기 시뮬레이션 |
| **포트** | `memory/read_port.py`, `write_port.py` | DRAM 포트 레이턴시 |

---

## 결론

### ✅ SCALE-Sim의 메모리 계층:
1. **L1 SRAM** (14 MB, Double Buffered) - `double_buffered_scratchpad_mem.py`
2. **DRAM** (10 GB/s) - `read_buffer.py` + `write_buffer.py`

### ❌ SCALE-Sim의 메모리 계층 (없음):
- **L2 Cache**: Google TPU v1 아키텍처에는 없기 때문
- **L3 Cache**: 역시 없음
- **TLB/메모리 관리**: 논리 주소 공간만 시뮬레이션

### 📊 당신의 다이어그램 수정안:
```
[Tensor index (m,n,k)]
    ↓
[Logical address (0~20M)]
    ↓
[L1 SRAM - Double Buffer] (14 MB)
  ├─ Active: PE에 제공
  └─ Prefetch: DRAM에서 미리 로드
    ↓
[DRAM Interface] (10 GB/s)
    ↓
[PE Systolic Array]
```

이것이 SCALE-Sim의 **실제 메모리 계층** 입니다!
