# SCALE-Sim L2 Shared Memory: 논문 vs 코드 분석

## 🔍 발견사항 요약

| 항목 | 논문 (v3) | 코드 저장소 | 결론 |
|------|----------|-----------|------|
| **L2 Shared Memory** | ✅ 설명됨 (Section III-B) | ❌ 없음 | **논문은 v3 기능을 소개하지만, 코드에는 아직 미구현** |
| **Spatio-temporal Partitioning** | ✅ 설명됨 | ✅ 있음 (`topology_utils.py`) | 부분 구현 |
| **Multi-core Simulation** | ✅ 설명됨 | ❌ 없음 | 미구현 |
| **L1 SRAM (Single-core)** | ✅ 설명됨 | ✅ 있음 | 완전 구현 |

---

## 📊 코드 검색 결과

### 검색 명령어:
```bash
# Multi-core 관련 클래스
find scalesim -name "*.py" -exec grep -l "class.*Multi\|class.*multi\|class.*core" {} \;
→ 결과: 없음

# L2 관련 함수
grep -r "def.*l2\|def.*L2\|l2_sram\|shared.*sram" scalesim/
→ 결과: 없음

# 파일 구조 확인
ls scalesim/
  ├─ compute/          (연산 시뮬레이션)
  ├─ memory/           (메모리 시뮬레이션)
  │  ├─ double_buffered_scratchpad_mem.py  (L1만 모델링)
  │  ├─ read_buffer.py  (DRAM)
  │  └─ write_buffer.py (DRAM)
  ├─ single_layer_sim.py  (싱글코어 시뮬레이션)
  └─ topology_utils.py    (spatio-temporal 파라미터만)
  
→ Multi-core 전용 시뮬레이션 클래스 없음
```

---

## 🎯 상황 분석

### SCALE-Sim v3 논문의 실제 상황:

**논문 발표**: 2025년 (최근 - ISPASS 2025)

**5가지 주요 기능**:
1. ✅ **Multi-core simulation** - 논문에만 있음
2. ✅ **L2 shared memory** - 논문에만 있음  
3. ✅ **Sparse accelerators** - 미확인
4. ✅ **Ramulator integration** - 미확인
5. ✅ **Data layout modeling** - 미확인

### 가능한 시나리오:

#### 시나리오 A: 최신 GitHub 저장소에는 있음 (가능성 높음)
```
GitHub repo (main branch) → 최신 코드 있음
          ↓
Your local copy → 아직 old version?
```

#### 시나리오 B: 다른 브랜치에 구현 중
```
main/master
├─ v2 features (현재 상태)
└─ v3-dev branch? (L2 구현 진행 중)
```

#### 시나리오 C: 논문은 v3이지만 코드는 v2.x
```
논문: SCALE-Sim v3 (2025년 최신)
코드: SCALE-Sim v2.x (구버전)
```

---

## 📝 논문에서 말하는 L2 구조

### Section III-B: Hierarchical memory with shared L2

```python
# 개념적 구조
class multi_core_system:
    def __init__(self):
        self.l2_shared_sram = {}  # 모든 코어가 공유
        self.cores = []
        for i in range(num_cores):
            self.cores.append({
                'l1_sram': double_buffered_scratchpad(),
                'systolic_array': pe_array()
            })
    
    def simulate_layer(self, gemm_params):
        # 1. GEMM을 (Pr × Pc × T) 파티션으로 분할
        #    (S_r, S_c, T 파라미터 사용)
        
        # 2. L2에 input partition (Pr×T) & weight partition (T×Pc) 로드
        input_part = self.load_from_dram_to_l2(...)
        weight_part = self.load_from_dram_to_l2(...)
        
        # 3. 각 코어가 필요한 부분만 L1에 로드
        for core in self.cores:
            # 핵심: L2에서 공유 데이터를 받음
            core.l1_sram.prefetch_from_l2(...)
            
        # 4. 각 코어 병렬 계산
        for core in self.cores:
            core.compute()
```

---

## 🔧 현재 코드의 한계

### 현재 구조 (v2):
```python
# single_layer_sim.py
class single_layer_sim:
    def __init__(self):
        self.compute_system = systolic_compute_ws()  # 1개 array만
        self.memory_system = double_buffered_scratchpad()  # L1만
        
    def run(self):
        # 1개 systolic array만 시뮬레이션
        for cycle in range(total_cycles):
            data = self.memory_system.read(address)
            self.compute_system.compute(data)
```

### 필요한 구조 (v3):
```python
# multi_layer_sim.py (아직 없음)
class multi_core_sim:
    def __init__(self):
        self.l2_sram = shared_l2_sram()  # ← 구현 필요
        self.cores = [single_layer_sim() for _ in range(num_cores)]
        
    def run(self):
        # 스파시-시간 파티셔닝
        s_r, s_c, t_time = calc_spatio_temporal_params()
        
        # L2 공유 로직
        for core_idx in range(num_cores):
            core = self.cores[core_idx]
            # L2에서 필요한 데이터 페치
            data_from_l2 = self.l2_sram.get_partition(...)
            core.run_with_prefetched_data(data_from_l2)
```

---

## ✅ 현재 코드에서 찾은 것들

### 1️⃣ Spatio-temporal 파라미터 (topology_utils.py)
```python
# Line 300-340
def calc_spatio_temporal_params(self, df='os', layer_id=0):
    """계산된 S_r, S_c, T"""
    
    # Example (WS dataflow):
    # Input dimension K=768 → s_row = 768
    # Output dimension N=768 → s_col = 768  
    # Batch/time dimension M=197 → t_time = 197
    
    # 각 코어가 처리할 데이터 크기:
    # 코어별 GEMM: (K/s_row) × (N/s_col) × M
    #            = 1 × 1 × 197  (매우 작음!)
```

**문제**: 이 파라미터들이 **계산만 되고 사용되지 않음**!

### 2️⃣ Single-core L1 SRAM 완전 구현 (double_buffered_scratchpad_mem.py)
```python
class double_buffered_scratchpad:
    def __init__(self):
        self.ifmap_buf = rdbuf()      # L1
        self.filter_buf = rdbuf()     # L1
        self.ofmap_buf = wrbuf()      # L1
```

**문제**: L2 backing buffer가 아님, DRAM이 backing buffer

---

## 💡 L2가 필요한 실제 예시

### ViT-base forward pass의 Multi-core MVM:

```
Q = Input @ W_q   # GEMM: (197, 768) @ (768, 768)

systolic array: 64×64 (4096 cores)

Spatio-temporal partition:
├─ S_r (input rows) = 197
├─ S_c (output cols) = 768
└─ T (weight rows) = 768

각 코어 할당:
└─ Core (0,0): 1×1 output element
   Input needed: 197 values (Q의 1행)  
   Weight needed: 768 values (W_q의 1행)

Core (0,1): 1×1 output element
└─ Input needed: 197 values (Q의 1행) ← 다시?!

❌ L1 only: 같은 Input을 Core(0,0)과 Core(0,1)에서 각각 로드 (낭비!)

✅ L2로 해결:
   L2에 Input (197 values) 1사본 → 모든 코어가 공유
   각 코어는 L1에서 필요한 부분만 캐시
```

---

## 🔍 다음 확인 사항

### 1. GitHub 저장소 최신 버전 확인
```bash
cd /scalesim/SCALE-Sim
git log --oneline | head -10  # 최근 커밋 확인
git branch -a                  # 다른 브랜치 있는지 확인
```

### 2. 버전 확인
```bash
cat setup.py | grep version
cat __version__ or scale.py | grep version
```

### 3. L2 구현 경로 찾기
```bash
# 논문 저자의 GitHub를 직접 확인?
# SCALE-Sim GitHub Issues/Discussions에서 v3 상태 확인?
```

---

## 📌 결론

### ✅ 확실한 것:
1. **논문 v3에는 L2 shared memory가 정의됨** (Section III-B)
2. **현재 코드에는 L2 구현이 없음**
3. **Spatio-temporal 파라미터 계산 코드는 있지만 미사용**

### ⚠️ 상황:
- 논문 발표 (2025년 최근) > 코드 저장소 (아직 v2)
- **코드 저장소가 따라가지 못한 상태**

### 🎯 해석:
당신의 메모리 계층 다이어그램이 **정확함**! 
논문에서 설명하는 v3 시스템이 바로 그것.

하지만 **현재 이 저장소의 코드는 아직 그것을 구현하지 않았음**.

---

## 📚 참고

**논문**: SCALE-Sim V3: A Modular Cycle-Accurate Systolic Accelerator Simulator
- 발표: ISPASS 2025 (최신)
- 주요 특징: Multi-core + L2 + Sparsity + Ramulator + Accelergy
- 현재 상태: **논문 소개 단계, 코드 미구현**
