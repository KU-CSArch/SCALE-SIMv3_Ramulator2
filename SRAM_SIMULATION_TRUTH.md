# SRAM 유무 판단과 시뮬레이션의 진실

## 핵심 진실: "데이터를 실제로 저장하지 않음!"

### 시뮬레이션이 하는 것 vs 하지 않는 것

```
❌ 하지 않는 것:
  - 실제 메모리에 데이터 저장
  - 실제 메모리 할당
  - 실제 메모리 접근

✅ 하는 것:
  - "주소 0에 접근한다"는 이벤트 기록
  - "주소 0이 SRAM에 있는가?"를 시뮬레이션
  - "이 주소가 필요한 사이클"과 "SRAM에 로드되는 사이클" 계산
  - 접근 패턴만 추적
```

---

## 1단계: Operand Matrix - "어떤 주소를 접근할 것인가?"

```python
# operand_matrix.py
IFMAP_addr_matrix = [
    [0,     1,     2,     ..., 63    ],      # i=0
    [1,     2,     3,     ..., 64    ],      # i=1
    [2,     3,     4,     ..., 65    ],      # i=2
    ...
]

이것은: "PE가 이 주소들에 접근한다"는 **계획**
실제 데이터는 메모리에 없음!
주소 번호만 기록된 것
```

---

## 2단계: Compute System - "어떤 순서로 접근할 것인가?"

```
Dataflow에 따라 접근 순서 결정
(WS: Weight Stationary)

Cycle 0: PE(0,0)가 IFMAP[0,0], FILTER[0,0] 접근할 계획
Cycle 1: PE(0,0)이 IFMAP[0,1], FILTER[0,0] 접근할 계획
Cycle 2: PE(0,0)이 IFMAP[0,2], FILTER[0,0] 접근할 계획
...

이것도: "이 사이클에 이 주소를 접근한다"는 **예정표**
```

---

## 3단계: Memory System - "SRAM에 있나 없나?"를 판단

### 핵심: Prefetch와 Demand의 타이밍 비교

```python
# double_buffered_scratchpad_mem.py의 로직

# Compute System에서 받은 정보:
prefetch_matrix = [
    [사이클 0, 주소들...],    # 이 사이클에 prefetch 시작
    [사이클 50, 주소들...],   # 이 사이클에 prefetch 시작
    [사이클 100, 주소들...],  # 이 사이클에 prefetch 시작
]

demand_matrix = [
    [사이클 0, 주소들...],    # 이 사이클에 실제로 필요
    [사이클 1, 주소들...],    # 이 사이클에 실제로 필요
    [사이클 10, 주소들...],   # 이 사이클에 실제로 필요
]

# 시뮬레이션: SRAM 유무 판단
def is_in_sram(address, demand_cycle):
    """
    address가 demand_cycle에 SRAM에 있는가?
    """
    # SRAM 크기: 6144 KB
    # Double Buffering: Buffer 0, Buffer 1
    
    # Buffer 0에 로드되는 주소들:
    buffer0_addresses = {
        주소들...: 로드 사이클
    }
    
    # Buffer 1에 로드되는 주소들:
    buffer1_addresses = {
        주소들...: 로드 사이클
    }
    
    # 판단 로직:
    if address in buffer0_addresses:
        load_cycle = buffer0_addresses[address]
        if load_cycle <= demand_cycle - SRAM_LATENCY:
            return True  # ✓ SRAM에 있음
    
    if address in buffer1_addresses:
        load_cycle = buffer1_addresses[address]
        if load_cycle <= demand_cycle - SRAM_LATENCY:
            return True  # ✓ SRAM에 있음
    
    return False  # ✗ SRAM에 없음 → DRAM에서 가져와야 함
```

### 구체적 예시

```
SRAM 크기: 6144 KB = 6144 * 1024 bytes = 6291456 bytes
주소 당 데이터: 4 bytes (int32)
SRAM이 저장할 수 있는 주소 개수: 6291456 / 4 = 1,572,864 개

실제 필요한 주소 개수:
IFMAP: 1024 * 64 = 65,536 개
FILTER: 64 * 1024 = 65,536 개
OFMAP: 1024 * 1024 = 1,048,576 개

하지만 한 번에 모두 SRAM에 로드할 수 없음:
  한 번에 최대: 65,536 + 65,536 = 131,072 개 (IFMAP + FILTER 한 배치)
  
→ Buffer 0과 Buffer 1로 번갈아가며 로드

Timeline:

Cycle 0-50:
  Buffer 0 로드 중: IFMAP[0:1000], FILTER[0:64]
  ├─ 읽음 완료: Cycle 10
  └─ PE가 Cycle 10-50 사용 (40 사이클)
  
Cycle 20:
  Buffer 1 로드 시작: IFMAP[1000:2000], FILTER[64:128]
  ├─ DRAM 요청: Cycle 20
  ├─ DRAM 응답: Cycle 30 (10 사이클 레이턴시)
  └─ 준비 완료: Cycle 30

Cycle 50:
  PE가 Buffer 1로 전환 (데이터 준비됨!)
  ├─ Cycle 50-100: Buffer 1 사용
  └─ DRAM 지연 없음 (완벽한 prefetch!)

판단 예시:
- address=1000, demand_cycle=60
  → Buffer 1에 로드됨, load_cycle=30
  → 30 <= 60 - 3? → Yes! ✓ SRAM에 있음
  
- address=50000, demand_cycle=40
  → Buffer 1에 아직 로드 안 됨, load_cycle=미정
  → 40 - 3 = 37 < 로드 예정 사이클?
  → ✗ SRAM에 없음 → DRAM_TRACE에 기록
```

---

## 4단계: 실제 데이터 흐름

### 시뮬레이션과 실제의 차이

```
시뮬레이션 (SCALE-Sim이 하는 것):

┌─────────────────────────────────────────────────┐
│ 메모리 주소 리스트                              │
│ (실제 데이터 없음)                              │
│                                                  │
│ IFMAP_addr: [0, 1, 2, 3, ...]                  │
│ FILTER_addr: [10M, 10M+1, 10M+2, ...]         │
│ OFMAP_addr: [20M, 20M+1, 20M+2, ...]          │
│                                                  │
│ ↓ Compute System                                │
│                                                  │
│ 접근 순서 & 타이밍 (실제 데이터 없음)          │
│ Cycle 0: addr 0, 10M, 20M                      │
│ Cycle 1: addr 1, 10M, 20M+1                    │
│ ...                                             │
│                                                  │
│ ↓ Memory System                                 │
│                                                  │
│ 주소 시뮬레이션                                 │
│ "addr 0은 이 사이클에 SRAM에 있을까?"          │
│ "addr 1은 이 사이클에 SRAM에 있을까?"          │
│ ...                                             │
│                                                  │
│ ↓ Trace 파일 생성                              │
│                                                  │
│ IFMAP_SRAM_TRACE.csv: SRAM에서 읽은 주소들   │
│ IFMAP_DRAM_TRACE.csv: DRAM에서 읽은 주소들   │
└─────────────────────────────────────────────────┘

실제 메모리 (SCALE-Sim이 하지 않는 것):

┌─────────────────────────────────────────────────┐
│ 메인 메모리 (실제 물리 메모리)                  │
│                                                  │
│ 주소 0: [1.0, 2.3, 4.5, 3.2, ...]             │
│ 주소 1: [5.2, 1.1, 3.3, 2.1, ...]             │
│ 주소 2: [2.2, 4.4, 1.5, 5.5, ...]             │
│ ...                                             │
│                                                  │
│ (이 부분은 SCALE-Sim이 관심 없음!)             │
│ (성능 분석만 하고 데이터는 안 다룸)            │
└─────────────────────────────────────────────────┘
```

---

## 5단계: SRAM 유무 판단 알고리즘 상세

### 코드 로직 (의사코드)

```python
class double_buffered_scratchpad:
    def __init__(self):
        # SRAM 버퍼 (실제 데이터 없음, 주소만 기록)
        self.buffer0_addresses = set()  # Buffer 0에 로드된 주소들
        self.buffer1_addresses = set()  # Buffer 1에 로드된 주소들
        
        self.buffer0_ready_cycle = 0    # Buffer 0이 준비되는 사이클
        self.buffer1_ready_cycle = 0    # Buffer 1이 준비되는 사이클
        
        self.current_buffer = 0         # 현재 사용 중인 버퍼
        
    def service_memory_requests(self, ifmap_demand, ifmap_prefetch):
        """
        실제 시뮬레이션: 주소만 기반으로 SRAM 유무 판단
        """
        
        # Step 1: Prefetch 계획 분석
        for prefetch_cycle, prefetch_addresses in ifmap_prefetch:
            if prefetch_cycle < self.buffer0_ready_cycle:
                # Buffer 0에 로드
                self.buffer0_addresses.update(prefetch_addresses)
                self.buffer0_ready_cycle = prefetch_cycle + DRAM_LATENCY
            else:
                # Buffer 1에 로드
                self.buffer1_addresses.update(prefetch_addresses)
                self.buffer1_ready_cycle = prefetch_cycle + DRAM_LATENCY
        
        # Step 2: Demand 요청 처리
        sram_hits = 0
        sram_misses = 0
        
        for demand_cycle, demand_addresses in ifmap_demand:
            for address in demand_addresses:
                # 주소만으로 SRAM 유무 판단
                in_sram = self.check_if_in_sram(
                    address, 
                    demand_cycle,
                    self.buffer0_addresses,
                    self.buffer1_addresses,
                    self.buffer0_ready_cycle,
                    self.buffer1_ready_cycle
                )
                
                if in_sram:
                    # ✓ SRAM 히트
                    sram_hits += 1
                    self.ifmap_sram_trace.append([demand_cycle, address])
                else:
                    # ✗ SRAM 미스 → DRAM 접근
                    sram_misses += 1
                    self.ifmap_dram_trace.append([demand_cycle, address])
        
        print(f"SRAM Hits: {sram_hits}, Misses: {sram_misses}")
        print(f"Hit Rate: {sram_hits/(sram_hits+sram_misses)*100:.2f}%")
    
    def check_if_in_sram(self, address, demand_cycle, 
                         buffer0_addr, buffer1_addr,
                         buf0_ready, buf1_ready):
        """
        address가 demand_cycle에 SRAM에 있는가?
        (실제 데이터 없이 주소만으로 판단)
        """
        
        # Buffer 0 확인
        if address in buffer0_addr:
            if buf0_ready <= demand_cycle:
                return True  # ✓ 주소가 Buffer 0에 있고 준비됨
        
        # Buffer 1 확인
        if address in buffer1_addr:
            if buf1_ready <= demand_cycle:
                return True  # ✓ 주소가 Buffer 1에 있고 준비됨
        
        return False  # ✗ SRAM에 없음
```

---

## 6단계: Trace 파일이 기록하는 것

### IFMAP_SRAM_TRACE.csv - 실제 내용

```
cycle,addr0,addr1,addr2,addr3,addr4,...
0,0,1,2,3,4,...,63
1,1,2,3,4,5,...,64
2,2,3,4,5,6,...,65
...
1000,1000,1001,1002,...,1063
```

### 이것이 의미하는 것

```
이것은 "실제 데이터"가 아니라 "주소 접근 기록"

각 행의 의미:
Cycle 0: PE 배열이 이 사이클에 이 주소들을 SRAM에서 읽으려고 함
Cycle 1: PE 배열이 이 사이클에 이 주소들을 SRAM에서 읽으려고 함
...

실제 값은:
┌─ 주소 0: 어떤 값 (예: 1.5)
├─ 주소 1: 어떤 값 (예: 2.3)
├─ 주소 2: 어떤 값 (예: 3.1)
└─ ...

하지만 SCALE-Sim은:
"값 1.5, 2.3, 3.1은 몰라도 괜찮아"
"중요한 건 접근 패턴이야"
"메모리 대역폭, 캐시 미스율, 지연시간 등을 분석하면 돼"
```

---

## 7단계: 시뮬레이션 출력 예시

### 시뮬레이션 결과

```
SRAM Configuration:
  Size: 6144 KB
  Latency: 3 cycles
  Bandwidth: 128 bits/cycle

DRAM Configuration:
  Latency: 100 cycles
  Bandwidth: 64 bits/cycle

Layer: QKT (M=1024, K=64, N=1024)

Memory Access Analysis:
  Total SRAM Accesses: 1,048,576
  Total DRAM Accesses: 2,048
  SRAM Hit Rate: 99.8%
  
  SRAM Cycles: 1,048,576 × 3 = 3,145,728 cycles
  DRAM Cycles: 2,048 × 100 = 204,800 cycles
  (Double Buffering으로 숨겨짐)

Performance:
  Total Compute Cycles: 1,048,576
  Total Memory Cycles: 3,145,728
  Memory Stall Cycles: 100,234
  Overall Utilization: 45.2%
```

### 이것이 의미하는 것

```
"실제 데이터 값들을 어떤 주소에서 언제 접근하는가?"를 시뮬레이션했으므로:

✓ 메모리 대역폭 분석 가능: "SRAM 포트가 병목이다"
✓ 캐시 미스율 분석 가능: "99.8% 히트율, 좋다!"
✓ 성능 예측 가능: "전체 1000 사이클 소요될 것"
✓ 아키텍처 개선 포인트 발견: "SRAM 크기를 2배로 하면?"

❌ 하지만 실제 데이터는 없음:
"1.5 × 2.3 = 3.45가 맞는지는 모름"
(데이터 정확성 검증은 다른 시뮬레이터의 일)
```

---

## 최종 정리

### SRAM 유무 판단 방식

```
1. Operand Matrix: "이 주소들을 접근한다"
   └─ 주소 목록

2. Compute System: "이 순서와 타이밍에 접근한다"
   └─ (주소, 사이클) 쌍의 목록

3. Prefetch Schedule: "이 주소들을 언제 prefetch할까?"
   ├─ Buffer 0: 사이클 0-50에 주소 0-65535 로드
   ├─ Buffer 1: 사이클 20-70에 주소 65536-131071 로드
   └─ ...

4. Demand Request: "이 주소가 이 사이클에 필요하다"
   └─ (주소, 사이클) 쌍

5. SRAM 유무 판단:
   demand_cycle에 address가 (buffer0 or buffer1)에 있는가?
   = "이 주소가 필요한 사이클에, prefetch로 이미 로드되었는가?"
   
   판단 로직:
   ✓ 있으면: SRAM_TRACE에 기록 (주소만)
   ✗ 없으면: DRAM_TRACE에 기록 (주소만)
```

### 시뮬레이션의 진실

```
SCALE-Sim은:
┌─ 주소 접근 시뮬레이터 (자세함, 정확함)
├─ 메모리 타이밍 시뮬레이터 (자세함, 정확함)
└─ 성능 분석 도구 (유용함)

하지만:
└─ 데이터 값 시뮬레이터는 아님 (필요 없음)

따라서:
├─ Trace에는 주소만 기록됨 ✓
├─ 실제 데이터는 저장되지 않음 ✓
└─ 메모리 접근 패턴만 분석 ✓
```
