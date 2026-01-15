# INT8 vs FP16 시뮬레이션 가이드

## 개요

SCALE-Sim에서 INT8과 FP16 두 가지 데이터 포맷으로 시뮬레이션을 비교할 수 있습니다.

## 생성된 설정 파일

### 1. google_int8.cfg
- **WordSize**: 1 byte per element
- **설명**: 정수 8비트 양자화 모델 (INT8)
- **SRAM 용량**: 6MB = 6,291,456 elements
- **사용 시나리오**: DNN 추론 (TPU v1 기본 설정)

### 2. google_fp16.cfg
- **WordSize**: 2 bytes per element
- **설명**: 16비트 부동소수점 모델 (FP16)
- **SRAM 용량**: 6MB = 3,145,728 elements (절반)
- **사용 시나리오**: 더 높은 정밀도가 필요한 경우

## 실행 방법

### INT8 시뮬레이션

```bash
cd /scalesim/SCALE-Sim
source venv/bin/activate

python scalesim/scale.py \
    -t topologies/GEMM_mnk/test_simple.csv \
    -l layouts/GEMM_mnk/gpt2.csv \
    -c configs/google_int8.cfg \
    -i gemm
```

결과: `results/GoogleTPU_v1_ws_INT8/`

### FP16 시뮬레이션

```bash
cd /scalesim/SCALE-Sim
source venv/bin/activate

python scalesim/scale.py \
    -t topologies/GEMM_mnk/test_simple.csv \
    -l layouts/GEMM_mnk/gpt2.csv \
    -c configs/google_fp16.cfg \
    -i gemm
```

결과: `results/GoogleTPU_v1_ws_FP16/`

## 예상되는 차이점

### SRAM 효율

| 설정 | Bytes | Elements | Layer 0 크기 |
|------|-------|----------|------------|
| INT8 | 6 MB | 6,291,456 | 4 KB |
| FP16 | 6 MB | 3,145,728 | 8 KB |

### 시뮬레이션 결과

#### INT8 설정
```
Total cycles: 2877
Compute cycles: 829
SRAM Bandwidth: 4.941 words/cycle
DRAM start cycle: 1639
```

#### FP16 설정
```
Total cycles: (같을 수 있음 - word 단위 계산이므로)
Compute cycles: (같음)
SRAM Bandwidth: (같음 - word 기준)
DRAM start cycle: (더 빨리 시작될 가능성)
```

### 주요 차이

1. **SRAM 용량 (요소 기준)**
   - INT8: 6,291,456 요소
   - FP16: 3,145,728 요소 (절반)

2. **메모리 주소 해석**
   - INT8: address 0-4095 = 4096 바이트
   - FP16: address 0-2047 = 4096 바이트 (2 바이트씩)

3. **DRAM 요청 시점**
   - FP16이 INT8보다 더 빨리 SRAM 초과로 DRAM 요청 가능

## 결과 분석

### 결과 디렉토리 비교

```bash
# INT8 결과
ls -la results/GoogleTPU_v1_ws_INT8/layer0/

# FP16 결과
ls -la results/GoogleTPU_v1_ws_FP16/layer0/

# 두 결과 비교
diff results/GoogleTPU_v1_ws_INT8/layer0/IFMAP_DRAM_TRACE.csv \
     results/GoogleTPU_v1_ws_FP16/layer0/IFMAP_DRAM_TRACE.csv
```

### 메트릭 비교

```bash
# INT8 메트릭 확인
python scalesim/scale.py -t topologies/GEMM_mnk/test_simple.csv \
    -l layouts/GEMM_mnk/gpt2.csv -c configs/google_int8.cfg -i gemm | grep -E "Total|Compute|Bandwidth"

# FP16 메트릭 확인
python scalesim/scale.py -t topologies/GEMM_mnk/test_simple.csv \
    -l layouts/GEMM_mnk/gpt2.csv -c configs/google_fp16.cfg -i gemm | grep -E "Total|Compute|Bandwidth"
```

## SCALE-Sim에서 WordSize 적용

### 현재 상황

SCALE-Sim v2 코드는 아직 config 파일의 `WordSize` 설정을 자동으로 읽지 않습니다.

### 대안 1: Python 코드 직접 수정 (임시)

파일: `scalesim/memory/read_buffer.py`

```python
# 현재 (라인 25)
self.word_size = 1    # Bytes

# 변경 (FP16 테스트 시)
self.word_size = 2    # Bytes for FP16
```

### 대안 2: Config 지원 추가 (향후)

`scale_config.py`에서 config 파일의 WordSize를 읽도록 수정 가능:

```python
# scale_config.py에 추가
if config.has_option(section, 'WordSize'):
    self.word_size = int(config.get(section, 'WordSize'))
else:
    self.word_size = 1  # Default INT8
```

## 지금까지의 발견

### INT8 설정 검증 ✓

- **DRAM trace addresses**: 0-4095 (4096개)
- **IFMAP elements**: M×K = 64×64 = 4,096개
- **Ratio**: 1.00 (완벽 일치)
- **결론**: INT8이 맞음!

### FP16 설정 (테스트 준비 완료)

- Config 파일 생성됨
- 실행 스크립트 준비됨
- 결과 비교 가능

## 다음 단계

1. **수동 테스트** (권장)
   - `read_buffer.py`에서 word_size를 2로 변경
   - FP16 시뮬레이션 실행
   - 결과 비교

2. **자동 지원** (향후)
   - `scale_config.py` 수정
   - `read_buffer.py`에 word_size 파라미터 전달
   - 재사용 가능한 설정 구조화

## 참고

- Google TPU v1: INT8 + FP32 (v3부터 FP16 지원)
- SCALE-Sim: 메모리 주소 추적 (실제 데이터값 아님)
- Bandwidth 계산: word 단위 (바이트 아님)

