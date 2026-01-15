# Prefetch vs DRAM Request: 시간 순서의 진실

## 핵심 오류 수정

### 사용자의 이해 (부분적으로 잘못됨):
```
"prefetch 되어있는지 유무를 판단 → 없으면 그때 DRAM request 날린다"
```

### 실제 동작 (정확한 설명):
```
1. Prefetch는 미리 계획됨 (시뮬레이션 시작 단계)
2. 계획된 시점에 DRAM에 요청 발생 (prefetch 스케줄 따라)
3. DRAM에서 응답 (레이턴시 후)
4. 데이터가 도착했으면 SRAM에 저장
5. Demand 시점에 판단: "도착했나?"
   - Yes → SRAM에서 읽음
   - No → Stall 발생 (긴급 요청 아님)
```

---

## 시간 흐름 상세 분석

### Scenario 1: 완벽한 Prefetch (성공)

```
Timeline:

Cycle 0:
  ├─ Compute System이 계획: "Cycle 0에 prefetch 시작"
  └─ Memory System: "Cycle 0에 DRAM 요청 발행" ← ⭐ 이미 여기서 요청!

Cycle 10: (DRAM 레이턴시 = 10 사이클)
  └─ DRAM 응답: 데이터 도착 → Buffer 0에 저장

Cycle 50:
  ├─ Compute System이 요구: "이 사이클에 주소 X 필요!"
  └─ Memory System이 판단:
     "주소 X가 Buffer 0에 있나? YES (Cycle 10에 도착했음)
      도착 사이클 10 <= 필요 사이클 50? YES
      → SRAM 히트! ✓"

결과:
  ├─ Cycle 0: DRAM 요청 발생 (prefetch 계획에 따라)
  ├─ Cycle 10: DRAM 응답
  ├─ Cycle 50: SRAM에서 읽음
  └─ 성공! (지연 없음)
```

### Scenario 2: Prefetch 타이밍이 부족한 경우 (실패)

```
Timeline:

Cycle 40:
  ├─ Compute System이 계획: "Cycle 40에 prefetch 시작"
  └─ Memory System: "Cycle 40에 DRAM 요청 발행" ← ⭐ 이미 여기서 요청!

Cycle 50: (DRAM 레이턴시 = 10 사이클)
  ├─ DRAM 응답: 데이터 아직 도착 안함 (40 + 10 = 50)
  └─ Buffer 0에 저장 (방금 도착!)

Cycle 50:
  ├─ Compute System이 요구: "이 사이클에 주소 X 필요!"
  └─ Memory System이 판단:
     "주소 X가 Buffer 0에 있나? YES (방금 도착)
      도착 사이클 50 <= 필요 사이클 50? YES (겨우 간신히!)
      → SRAM 히트 (하지만 여유 없음)"

결과:
  ├─ Cycle 40: DRAM 요청 발생
  ├─ Cycle 50: DRAM 응답 (딱 그 순간!)
  ├─ Cycle 50: SRAM에서 읽음 (매우 타이트!)
  └─ 성공했지만 매우 위험한 상황
```

### Scenario 3: Prefetch 타이밍이 너무 늦은 경우 (실패 & Stall)

```
Timeline:

Cycle 55:
  ├─ Compute System이 계획: "Cycle 55에 prefetch 시작"
  └─ Memory System: "Cycle 55에 DRAM 요청 발행"

Cycle 65: (DRAM 레이턴시 = 10 사이클)
  └─ DRAM 응답: 데이터 도착

Cycle 50:  ← ⚠️ 문제! 이미 지났는데 데이터 필요!
  ├─ Compute System이 요구: "이 사이클에 주소 X 필요!"
  └─ Memory System이 판단:
     "주소 X가 Buffer에 있나? NO (아직 도착 안함)
      도착 예정 사이클 65 > 필요 사이클 50? YES
      → SRAM 미스! ✗"

결과:
  ├─ Cycle 50: SRAM 미스 발생
  ├─ Cycle 50-65: PE 배열 STALL (기다림)
  ├─ Cycle 55: DRAM 요청 (이미 계획된 것)
  ├─ Cycle 65: DRAM 응답
  ├─ Cycle 65: PE 재개 (데이터 도착)
  └─ 15 사이클 손실 (성능 저하!)

⭐ 중요: 여기서 "긴급 DRAM request"가 발생하지 않음!
   이미 prefetch 계획에 있던 요청일 뿐
```

---

## 코드 레벨에서의 구현

### Read Buffer (prefetch 담당)

```python
class read_buffer:
    def __init__(self):
        self.prefetch_schedule = []  # 미리 계획된 prefetch들
        self.dram_requests_sent = []  # 이미 발행된 DRAM 요청들
        self.dram_responses = {}      # {주소: 도착_사이클}
        self.sram_buffer = set()      # SRAM에 저장된 주소들
    
    def service_prefetch(self):
        """
        Step 1: Prefetch 계획 실행 (시뮬레이션 시작 시)
        """
        for prefetch_cycle, prefetch_addresses in self.prefetch_schedule:
            # 이 시점에 이미 DRAM 요청 발행!
            for address in prefetch_addresses:
                dram_latency = DRAM_LATENCY  # 10 사이클
                arrival_cycle = prefetch_cycle + dram_latency
                
                self.dram_requests_sent.append({
                    'address': address,
                    'sent_cycle': prefetch_cycle,
                    'arrival_cycle': arrival_cycle
                })
    
    def service_demand(self):
        """
        Step 2: Demand 처리 (실제 접근 시)
        """
        for demand_cycle, demand_addresses in self.demand_matrix:
            for address in demand_addresses:
                # DRAM 응답이 도착했나? (아직 도착했나?)
                for dram_req in self.dram_requests_sent:
                    if dram_req['address'] == address:
                        if dram_req['arrival_cycle'] <= demand_cycle:
                            # ✓ 데이터 도착함
                            self.sram_buffer.add(address)
                            print(f"✓ 주소 {address} SRAM 히트 (Cycle {demand_cycle})")
                            return True
                        else:
                            # ✗ 아직 도착 안함
                            stall_cycles = dram_req['arrival_cycle'] - demand_cycle
                            print(f"✗ 주소 {address} SRAM 미스 ({stall_cycles} 사이클 stall)")
                            return False
```

---

## 핵심 개념 정정

### ❌ 잘못된 이해:

```
Demand 발생 → SRAM에 있나 확인 → 없으면 DRAM 요청 발행
```

### ✅ 정확한 이해:

```
미리 Prefetch 계획
  ↓
Prefetch 스케줄에 따라 DRAM 요청 (미리 발행!)
  ↓
DRAM 응답 (레이턴시 후)
  ↓
Demand 시점에 판단
  ├─ 응답 도착했나? YES → SRAM 히트
  └─ 응답 도착했나? NO → Stall
```

---

## 3가지 케이스 비교

| 케이스 | Prefetch 계획 | DRAM 요청 시점 | DRAM 응답 시점 | Demand 시점 | 결과 |
|--------|----------|-----------|-----------|----------|------|
| ✓ 성공 | Cycle 0 | Cycle 0 | Cycle 10 | Cycle 50 | SRAM 히트 |
| ⚠️ 위험 | Cycle 40 | Cycle 40 | Cycle 50 | Cycle 50 | SRAM 히트 (타이트) |
| ✗ 실패 | Cycle 55 | Cycle 55 | Cycle 65 | Cycle 50 | SRAM 미스 → Stall |

---

## 왜 이렇게 설계했나?

### Prefetch 방식 (계획 기반)

```
장점:
1. 미리 계획하므로 DRAM 체계적 활용
2. Double Buffering으로 레이턴시 숨김
3. 성능 예측 가능
4. 버스 경합 최소화

단점:
1. 계획이 틀리면 Stall 발생
2. 데이터 재사용 패턴 변하면 문제
```

### 긴급 요청 방식 (동적)이 아닌 이유

```
❌ 왜 안하나?
1. DRAM 레이턴시가 매우 큼 (10-100 사이클)
2. 필요할 때 요청하면 너무 늦음
3. 예측 불가능한 성능
4. DRAM 버스 경합 심화

✓ 대신 미리 계획:
1. Dataflow를 분석해 prefetch 계획
2. 필요한 시점 전에 미리 요청
3. 거의 항상 SRAM에서 읽음
4. 성능 안정적
```

---

## 최종 정리

### 질문: "Prefetch 없으면 그때 DRAM request 날린다?"

### 답:

```
❌ 아니다!

✓ 정확한 답:

1. Prefetch는 미리 계획됨 (Compute System이 dataflow 분석)

2. 계획된 시점에 DRAM 요청 발행 (시뮬레이션 초기 단계)

3. DRAM에서 응답 (레이턴시 후)

4. Demand 시점에:
   - 응답 도착했으면 → SRAM 히트 (성공)
   - 응답 안 도착했으면 → Stall 발생 (실패)

5. "그때 DRAM request 날린다"는 일은 없음
   (이미 prefetch 스케줄에 포함되어 있음)
```

### 예시:

```
시뮬레이션 시작:
  "Cycle 0에 DRAM 요청을 날릴 거야"
  "Cycle 40에 DRAM 요청을 날릴 거야"
  "Cycle 80에 DRAM 요청을 날릴 거야"
  ← 모두 미리 계획됨!

실행:
  Cycle 0: "계획대로 DRAM 요청 발행"
  Cycle 40: "계획대로 DRAM 요청 발행"
  Cycle 80: "계획대로 DRAM 요청 발행"
  
  (그 사이에 필요할 때 요청하지 않음!)

평가:
  "아, 이 계획으로 충분했나? 부족했나?"
  → TRACE 파일로 확인
```
