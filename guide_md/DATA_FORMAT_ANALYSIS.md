# SCALE-Sim 데이터 포맷 분석 결과

## 최종 결론

**SCALE-Sim은 INT8 (1 byte per element) 데이터 포맷을 사용합니다.**

## 분석 방법

DRAM trace 파일의 주소(address) 값을 역산하여 데이터 포맷을 결정했습니다.

### 핵심 원리

SCALE-Sim의 주소 생성 과정:
1. `operand_matrix.py`: 각 element의 **byte offset** 계산
2. `single_layer_sim.py`: 이 offset들을 DRAM trace에 기록
3. Config 파일: `IfmapOffset: 0 (in Bytes)` - 주소는 바이트 단위

### 주소 해석

```
Address = element_index × (bytes_per_element)
```

만약:
- **1 address per element** → INT8 (1 byte/element)
- **2 addresses per element** → FP16 (2 bytes/element)  
- **4 addresses per element** → FP32 (4 bytes/element)

## 증거

### 1. Test Topology (M=64, K=64, N=64)

| Operand | Elements | Unique Addresses | Ratio | Format |
|---------|----------|------------------|-------|--------|
| IFMAP | 4,096 | 4,096 | 1.00 | INT8 ✓ |
| FILTER | 4,096 | 4,096 | 1.00 | INT8 ✓ |
| OFMAP | 4,096 | 4,096 | 1.00 | INT8 ✓ |

### 2. Address 시퀀스 분석

**Layer 0 IFMAP:**
```
First 10 addresses: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, ...]
Min: 0, Max: 4095
All sequential? YES ✓
```

**Layer 1 IFMAP:**
```
Total unique: 50,176
Min: 0, Max: 50,175
Gap analysis: 99% gaps are size 1
Address density: 1.0000 (perfect sequential)
```

### 3. 수학적 검증

Test topology에서:
- IFMAP elements = M × K = 64 × 64 = **4,096**
- DRAM trace unique addresses = **4,096**
- Ratio = 4,096 / 4,096 = **1.00** ✓

Configuration:
- SRAM capacity: 6 MB = 6,291,456 bytes
- If INT8: 4,096 bytes needed ✓ (fits easily)
- If FP16: 8,192 bytes needed ✓ (fits easily)
- If FP32: 16,384 bytes needed ✓ (fits easily)

**하지만 addresses are 0-4095 (정확히 4096개), not 0-8191 or 0-16383**

따라서 각 element = 1 byte = **INT8**

## 주요 발견

1. **Address Sequentiality**: 모든 layer에서 주소가 거의 완벽하게 순차적
   - Layer 0: 100% sequential (0, 1, 2, 3, ...)
   - Layer 1: 99% gaps of size 1

2. **1:1 Address-Element Mapping**: 고유 주소 개수 = element 개수

3. **Address Offsets Match Byte Boundaries**:
   - FILTER DRAM addresses: 10,000,000 ~ 10,004,095 (4,096 bytes = 4KB)
   - OFMAP DRAM addresses: 20,000,000 ~ 20,004,095 (4,096 bytes = 4KB)

## 추론

```
DRAM_TRACE_ADDRESS = ELEMENT_OFFSET_IN_BYTES

For IFMAP:
  - Element 0 at byte address 0
  - Element 1 at byte address 1
  - Element 4095 at byte address 4095
  - All elements fit in 4,096 bytes = 4 KB

For FILTER:
  - Element 0 at byte address 10,000,000
  - Element 4095 at byte address 10,004,095
  - All elements fit in 4,096 bytes = 4 KB

For OFMAP:
  - Element 0 at byte address 20,000,000
  - Element 4095 at byte address 20,004,095
  - All elements fit in 4,096 bytes = 4 KB
```

## 결론

각 element가 정확히 1 byte로 매핑되므로:

**SCALE-Sim Data Format = INT8**

## 시뮬레이션 환경

- Simulator: SCALE-Sim v2
- Architecture: GoogleTPU v1 (256×256 PE array)
- Config: google.cfg
- Test topology: M=64, K=64, N=64 (simple GEMM)
- Analysis date: [Generated from DRAM traces]

## 다음 단계

이 INT8 포맷 정보를 사용하여:
1. Memory bandwidth 계산 정확화
2. DRAM access pattern 분석
3. 다른 데이터 포맷과의 성능 비교
4. Sparsity optimization의 영향 분석
