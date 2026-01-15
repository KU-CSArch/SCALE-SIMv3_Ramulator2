# 메모리 계층 구조: DRAM vs Scratchpad SRAM

## 질문: 메모리는 어디의 메모리?

### 정답: **둘 다이지만, 다른 시점에 다른 메모리!**

```
Operand Matrix의 "메모리 주소"
    ↓
    이것은 "논리적 주소 공간(Logical Address Space)"
    
    실제 물리적 위치:
    ├─ 먼저 SRAM Scratchpad에서 찾음 (빠름, 자주 성공)
    └─ 없으면 DRAM에서 가져옴 (느림, 가끔)
```

---

## 메모리 계층 구조 다이어그램

```
┌─────────────────────────────────────────────────────────┐
│           Systolic Array (PE 256×256)                  │
│  (Operand Matrix를 사용해서 주소를 결정)                 │
└─────────────────┬───────────────────────────────────────┘
                  │ 메모리 요청: "주소 0의 데이터 주세요"
                  ▼
┌─────────────────────────────────────────────────────────┐
│      Scratchpad SRAM (Double Buffered)                 │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Buffer 0: PE 배열에 데이터 서빙                 │  │
│  │  (지금 사용 중)                                   │  │
│  │                                                   │  │
│  │  IFMAP 영역:                                     │  │
│  │  주소 0~11: A[0,0]~A[3,2]의 값들                │  │
│  │                                                   │  │
│  │  FILTER 영역:                                    │  │
│  │  주소 10M~10M+5: B[0,0]~B[2,1]의 값들          │  │
│  │                                                   │  │
│  │  OFMAP 영역:                                     │  │
│  │  주소 20M~20M+7: C[0,0]~C[3,1]의 값들          │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Buffer 1: DRAM에서 다음 데이터 prefetch 중     │  │
│  │  (준비 중)                                        │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
│  TRACE: IFMAP_SRAM_TRACE.csv                           │
│  [cycle, addr1, addr2, addr3, ...]                     │
│  ← PE 배열이 SRAM에 접근한 주소들                      │
└─────────────────┬───────────────────────────────────────┘
                  │ SRAM에 없으면 Read Buffer가 DRAM에 요청
                  ▼
┌─────────────────────────────────────────────────────────┐
│           DRAM (Main Memory - 메인 메모리)              │
│                                                          │
│  IFMAP 전체 데이터:                                     │
│  주소 0~[큰 숫자]: 모든 입력 데이터                     │
│                                                          │
│  FILTER 전체 데이터:                                    │
│  주소 10M~[큰 숫자]: 모든 가중치 데이터                │
│                                                          │
│  OFMAP 저장소:                                          │
│  주소 20M~[큰 숫자]: 결과 저장                          │
│                                                          │
│  TRACE: IFMAP_DRAM_TRACE.csv                           │
│  [cycle, addr1, addr2, ...]                            │
│  ← SRAM의 Read Buffer가 DRAM에 접근한 주소들           │
└─────────────────────────────────────────────────────────┘
```

---

## 구체적 실행 흐름

### Step 1-3: 첫 번째 MAC 연산 (SRAM에 데이터 있음)

```
TIME: Cycle 0

Step 1: PE 배열이 Operand Matrix를 보고 요청
  "IFMAP 주소 0의 데이터 주세요!"
  
  ↓ SRAM Scratchpad에서 찾음 ✓
  
  Scratchpad SRAM의 IFMAP 영역:
  주소 0: 1 (A[0,0])
  
  PE에 전달: 1
  
  TRACE 기록:
  IFMAP_SRAM_TRACE에 기록: [Cycle0, 0] (주소 0 접근)
  (DRAM trace에는 기록 안됨 - SRAM에서 이미 있었음)

Step 2: PE 배열이 다시 요청
  "FILTER 주소 10000000의 데이터 주세요!"
  
  ↓ SRAM Scratchpad에서 찾음 ✓
  
  Scratchpad SRAM의 FILTER 영역:
  주소 10000000: 1 (B[0,0])
  
  PE에 전달: 1
  
  TRACE 기록:
  FILTER_SRAM_TRACE에 기록: [Cycle0, 10000000]

Step 3: PE가 연산
  1 × 1 = 1
  누적: 0 + 1 = 1
```

### Step 4-6: 두 번째 MAC 연산 (여전히 SRAM에 있음)

```
TIME: Cycle 1

Step 4: PE 배열
  "IFMAP 주소 1의 데이터 주세요!"
  
  ↓ SRAM에서 찾음 ✓
  
  Scratchpad SRAM:
  주소 1: 2 (A[0,1])
  
  PE에 전달: 2
  TRACE: IFMAP_SRAM_TRACE에 [Cycle1, 1] 기록

Step 5: PE 배열
  "FILTER 주소 10000002의 데이터 주세요!"
  
  ↓ SRAM에서 찾음 ✓
  
  Scratchpad SRAM:
  주소 10000002: 3 (B[1,0])
  
  PE에 전달: 3
  TRACE: FILTER_SRAM_TRACE에 [Cycle1, 10000002] 기록

Step 6: PE가 연산
  2 × 3 = 6
  누적: 1 + 6 = 7
```

### 만약 데이터가 SRAM에 없었다면?

```
예를 들어, 다른 시나리오:

TIME: Cycle 100

PE 배열:
  "IFMAP 주소 100의 데이터 주세요!"
  (새로운 데이터 필요)
  
  ↓ Scratchpad SRAM에서 찾음...
  ✗ 찾을 수 없음! (Buffer가 다른 데이터로 채워져 있음)
  
  ↓ Read Buffer가 DRAM에 요청
  "DRAM 주소 100, 101, 102, ... 의 데이터 가져와!"
  
  ↓ DRAM 접근 (느림! ~10-100 사이클)
  
  메인 메모리에서:
  주소 100: A[?]의 값
  주소 101: A[?]의 값
  ...
  
  ↓ DRAM Trace 기록
  IFMAP_DRAM_TRACE에 [Cycle100, 100, 101, 102, ...] 기록
  
  ↓ Data 도착 (Cycle ~110)
  
  ↓ Buffer 1에 채워짐 (prefetch)
  
  ↓ PE 배열이 다시 요청할 때 (Cycle ~120)
  
  ↓ Buffer 1에서 데이터 제공 ✓
  
  ↓ Scratchpad SRAM Trace 기록
  IFMAP_SRAM_TRACE에 [Cycle120, 100, 101, 102, ...] 기록
```

---

## SRAM vs DRAM 접근 비교

### IFMAP_SRAM_TRACE

```
매우 자주 나타남 (거의 매 사이클)
┌─────────────────────────────────┐
│ Cycle, Address1, Address2, ...  │
├─────────────────────────────────┤
│ 0, 0, 1, 2, ...                 │  ← Cycle 0: 주소 0~63 접근 (많음)
│ 1, 1, 2, 3, ...                 │  ← Cycle 1: 주소 1~64 접근
│ 2, 2, 3, 4, ...                 │  ← Cycle 2: 주소 2~65 접근
│ ...                              │
│ 1000, 64, 65, 66, ...           │  ← Cycle 1000: 주소 64~127 접근
└─────────────────────────────────┘

특징:
- 많은 주소들이 나열됨 (한 사이클에 여러 PE가 동시 접근)
- 규칙적 패턴 (Compute 패턴 반영)
- 총 라인 수: ~연산 사이클 수 (많음)

이유:
PE 배열이 매 사이클 SRAM에서 데이터를 읽음
SRAM은 빠르니까 (1-3 사이클) 매번 성공
```

### IFMAP_DRAM_TRACE

```
드물게 나타남 (Double Buffering 덕분에)
┌─────────────────────────────────┐
│ Cycle, Address1, Address2, ...  │
├─────────────────────────────────┤
│ 100, 1000, 1001, 1002, ..., 1127│  ← Cycle 100: Buffer 1에 prefetch 시작
│ 110, ...                         │
│ ...                              │
│ 500, 2000, 2001, 2002, ..., 2127│  ← Cycle 500: 다음 배치 prefetch
│ ...                              │
└─────────────────────────────────┘

특징:
- 적은 주소들이 나열됨 (prefetch 요청만)
- 불규칙적 패턴 (메모리 대역폭 제약 반영)
- 총 라인 수: ~prefetch 요청 횟수 (적음)

이유:
Double Buffering으로 DRAM 레이턴시를 숨김
PE가 Buffer 0 사용 중 → Buffer 1에 prefetch
미리 데이터를 준비하므로 DRAM 접근 횟수 최소화
```

---

## 메모리 접근의 시간 흐름

### 이상적인 Double Buffering

```
SRAM Buffer 0: 현재 PE가 읽는 데이터
SRAM Buffer 1: 다음에 필요할 데이터 (prefetch 중)

Timeline:
─────────────────────────────────────────────────────

Cycle 0-99: 
  PE가 Buffer 0에서 읽음 (데이터 연속 공급)
  ├─ SRAM_TRACE: [0, addr0], [1, addr1], ..., [99, addr99]
  └─ DRAM_TRACE: (없음, prefetch 중)

사이에 Buffer 0 남은 데이터로 충분한 사이클 가능

Cycle 100-199:
  PE가 Buffer 1에서 읽음 (이제 Buffer 1이 준비됨)
  ├─ SRAM_TRACE: [100, addr100], ..., [199, addr199]
  └─ DRAM_TRACE: (없음, prefetch 중)

동시에:
  Buffer 0이 다음 데이터로 prefetch 중
  ├─ Cycle 90: DRAM에 요청 시작
  ├─ Cycle 95-105: DRAM에서 읽음 (느림)
  └─ Cycle 110: Buffer 0 준비 완료

결과:
┌─ DRAM Latency (10-20 사이클)를 완벽히 숨김!
│
├─ PE는 항상 SRAM에서 빠르게 읽음 ✓
│
└─ Double Buffering 성공!
```

### 문제 상황: Double Buffering 실패

```
만약 SRAM 크기가 너무 작아서...

Cycle 0-49:
  Buffer 0의 데이터 다 사용
  ├─ SRAM_TRACE: [0, addr0], ..., [49, addr49]
  └─ Buffer 1의 prefetch가 아직 완료 안됨
  
Cycle 50:
  PE: "데이터 줘!"
  Read Buffer: "Buffer 1이 아직 안 준비됐는데..."
  
  강제로 DRAM에 긴급 요청
  ├─ DRAM 지연: 100 사이클
  └─ PE 스톨! (아무것도 못함)
  
Cycle 50-150:
  STALL_CYCLES 발생!
  ├─ PE가 기다림
  ├─ DRAM_TRACE: [50, emergency_addr, ...]
  └─ 성능 저하!
```

---

## 종합 정리

### Operand Matrix의 "메모리 주소"

```
논리적 주소 공간:
┌──────────────────────────────────────────┐
│ IFMAP: 주소 0 ~ 9,999,999               │ ← Operand Matrix가 사용
│ FILTER: 주소 10,000,000 ~ 19,999,999   │
│ OFMAP: 주소 20,000,000 ~ 29,999,999    │
└──────────────────────────────────────────┘
                ↓
        물리적으로 실제 접근:
                ↓
        ┌─────────────────────────┐
        │ 먼저 SRAM에서 찾음      │
        │ (빠름, 1-3 사이클)     │ → IFMAP_SRAM_TRACE.csv
        └─────────────────────────┘
                ↓ (찾으면 성공!)
        ┌─────────────────────────┐
        │ 없으면 DRAM 요청        │
        │ (느림, 10-100 사이클)  │ → IFMAP_DRAM_TRACE.csv
        └─────────────────────────┘
```

### 3가지 Trace 파일의 의미

```
1. IFMAP_SRAM_TRACE.csv
   "PE 배열이 SRAM Scratchpad에서 읽은 주소들"
   - 빈번 (매 사이클 여러 번)
   - 규칙적 (Compute 패턴)
   - 평가: SRAM 포트 대역폭

2. IFMAP_DRAM_TRACE.csv
   "SRAM의 Read Buffer가 DRAM에 요청한 주소들"
   - 드물음 (prefetch 때문에)
   - 불규칙적 (메모리 제약)
   - 평가: DRAM 대역폭, 메모리 지연
   
3. 두 Trace의 차이 분석
   - DRAM 접근이 많다 → 메모리 대역폭 부족 (병목)
   - 간격이 크다 → DRAM Latency 문제
   - 스톨 사이클이 많다 → Double Buffering 실패
```

---

## 최종 답변

### Q: 메모리는 어디의 메모리?

### A: 
```
Operand Matrix에서 언급하는 "메모리 주소"는:

1단계: 논리적 주소공간 (추상화)
   - "주소 0~12에서 입력 읽고"
   - "주소 10M~10M+6에서 가중치 읽고"
   
2단계: 실제 물리적 구현 (구체화)
   ├─ SRAM Scratchpad에서 찾으면: 빠르게 제공 (1-3사이클)
   │  └─ IFMAP_SRAM_TRACE에 기록
   │
   └─ SRAM에 없으면: DRAM에 요청 (10-100사이클)
      └─ IFMAP_DRAM_TRACE에 기록

따라서:
- SRAM을 먼저 확인하고 없으면 DRAM에서 가져옴
- Trace 파일이 2개인 이유가 이것!
- Double Buffering으로 DRAM 접근을 최소화
```
