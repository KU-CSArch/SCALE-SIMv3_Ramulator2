# Git Merge 전략: 안전하게 최신 코드 업데이트하기

## 📊 현재 상황 분석

### Git 상태:
```
- 현재 브랜치: main
- Origin 대비: 2 commits 뒤쳐짐
- 수정된 파일: 13개 (tracked)
- 추가된 파일: 40개 (untracked - 주로 결과 및 실험 파일)
```

### 수정된 파일 (중요):
```
✏️ Modified (코드 변경):
   scalesim/layout_utils.py          ← 핵심 로직 변경
   scalesim/scale_sim.py             ← 핵심 로직 변경
   scalesim/topology_utils.py        ← 핵심 로직 변경
   scripts/dram_latency.py           ← 스크립트 변경
   scripts/dram_sim.py               ← 스크립트 변경
   configs/google.cfg                ← 설정 변경
   configs/google_ramulator.cfg      ← 설정 변경
   run_ramulator.sh                  ← 스크립트 변경

❌ Deleted:
   layouts/layout_conversion.py      ← 파일 삭제됨

📦 Untracked (결과 파일 - 안전함):
   L2_SHARED_MEMORY_ANALYSIS.md
   Qwen_Qwen2.5-0.5B_orig_out/
   results/
   vit_l_orig_out_*/
   ... (실험 결과들)
```

---

## 🛡️ 안전한 Merge 전략

### 1단계: 변경사항 백업 (필수!)

```bash
# 현재 변경사항을 새 브랜치로 저장
git checkout -b my-changes-backup

# 또는 각 파일을 tar로 백업
cd /scalesim/SCALE-Sim
tar -czf my_changes_backup_$(date +%Y%m%d_%H%M%S).tar.gz \
  scalesim/ configs/ scripts/

# 백업 확인
ls -lh *.tar.gz
```

### 2단계: 각 수정 파일별 diff 확인

```bash
git diff scalesim/scale_sim.py | head -100    # 변경 내용 확인
git diff scalesim/layout_utils.py | head -100
git diff scalesim/topology_utils.py | head -100
```

### 3단계: 최신 코드 업데이트 (3가지 옵션)

#### **옵션 A: Fetch만 (권장 - 안전)**
```bash
git fetch origin main
git log --oneline HEAD...origin/main  # 새로운 커밋 확인
```
- 장점: 로컬 코드는 안전함
- 단점: 최신 코드 기능 미사용

#### **옵션 B: Rebase (권장 - 깔끔)**
```bash
# 1) 현재 변경사항을 임시 저장
git stash

# 2) 최신 코드로 업데이트
git pull origin main

# 3) 변경사항 다시 적용
git stash pop
```
- 장점: 커밋 히스토리 깔끔
- 주의: Conflict 가능성

#### **옵션 C: 수동 Merge (안전)**
```bash
# 1) Merge 시작 (자동 처리 시도)
git pull origin main --no-edit

# 2) Conflict 있으면 수동 해결
# scalesim/*.py 파일들을 확인하며 수정
```

---

## ⚠️ 잠재적 Conflict 포인트

### 높은 Risk 파일들:
1. **scalesim/scale_sim.py** - 메인 진입점
2. **scalesim/layout_utils.py** - 레이아웃 로직
3. **scalesim/topology_utils.py** - Spatio-temporal 파라미터

### 낮은 Risk 파일들:
- configs/ (설정 파일)
- scripts/ (스크립트)
- *.sh (쉘 스크립트)

---

## 🎯 추천 절차

### **시나리오 1: 변경사항이 중요한 경우 (권장)**

```bash
# Step 1: 백업
git checkout -b my-changes-backup
cd /scalesim/SCALE-Sim
git add .
git commit -m "backup: my experimental changes before update"

# Step 2: 원래 브랜치로 돌아가기
git checkout main

# Step 3: 각 파일 diff 확인
git diff origin/main -- scalesim/scale_sim.py | head -50
git diff origin/main -- scalesim/layout_utils.py | head -50

# Step 4: 조심히 pull
git pull origin main

# Step 5: Conflict가 있으면 수동 해결
# (VS Code의 Merge Editor 사용)

# Step 6: 검증
python3 -m scalesim.scale -c configs/test.cfg -t topologies/test.csv
```

### **시나리오 2: 변경사항을 버려도 되는 경우**

```bash
# 매우 간단: 현재 코드를 원격으로 덮어쓰기
git fetch origin main
git reset --hard origin/main

# 주의: 모든 로컬 변경사항 사라짐!
```

---

## 📋 현재 수정사항 정리 및 선택

### 당신이 수정한 것 중:

| 파일 | 내용 | 필요성 | 액션 |
|------|------|--------|------|
| `scalesim/scale_sim.py` | ? | 확인 필요 | diff 확인 후 결정 |
| `scalesim/layout_utils.py` | ? | 확인 필요 | diff 확인 후 결정 |
| `scalesim/topology_utils.py` | Spatio-temporal 개선? | 확인 필요 | diff 확인 후 결정 |
| `configs/google_int8.cfg` | INT8 설정 추가 | ✅ 유용 | 유지 권장 |
| `configs/google_fp16.cfg` | FP16 설정 추가 | ✅ 유용 | 유지 권장 |
| `scalesim/memory/read_buffer.py.INT8.backup` | 백업 | ✅ 안전 | 유지 권장 |
| `scalesim/memory/read_buffer.py.FP16` | FP16 변형 | ✅ 유용 | 유지 권장 |

---

## 🔍 각 파일별 상세 Diff 확인

```bash
# 1) scale_sim.py 변경사항 확인
git diff scalesim/scale_sim.py > /tmp/scale_sim.diff
cat /tmp/scale_sim.diff | less

# 2) layout_utils.py 변경사항 확인
git diff scalesim/layout_utils.py > /tmp/layout_utils.diff

# 3) topology_utils.py 변경사항 확인
git diff scalesim/topology_utils.py > /tmp/topology_utils.diff

# 4) 파일별 라인 수 확인
wc -l /tmp/*.diff
```

---

## ✅ 안전한 Merge 체크리스트

- [ ] 1) 변경사항을 새 브랜치로 백업했는가?
- [ ] 2) 각 수정 파일의 diff를 확인했는가?
- [ ] 3) 수정 내용이 왜 필요한지 기록했는가?
- [ ] 4) 테스트 설정(test.cfg, test_simple.csv)은 있는가?
- [ ] 5) Merge 후 테스트 커맨드를 준비했는가?

---

## 🚀 권장 다음 단계

### **즉시 할 일:**

1. **각 파일의 변경사항 정리**
   ```bash
   git diff scalesim/ > my_changes.patch
   git diff configs/ >> my_changes.patch
   cat my_changes.patch | less  # 검토
   ```

2. **변경사항을 commit으로 저장**
   ```bash
   git add scalesim/ configs/ scripts/
   git commit -m "my: INT8/FP16 support and optimizations"
   ```

3. **그 후에 업데이트**
   ```bash
   git pull origin main
   # Conflict 해결
   ```

---

## 📞 도움이 필요한 경우

**Conflict 발생 시:**
```bash
# 모든 conflict 파일 확인
git status | grep "both modified"

# 특정 파일의 conflict 확인
git diff --name-only --diff-filter=U

# VS Code Merge Editor 사용 (권장)
# Conflict 파일을 VS Code에서 열어서 해결
```

---

**결론:** 지금 상황은 안전합니다! 추천은:
1. **먼저** git diff로 모든 변경사항 검토
2. **그 후** git commit으로 저장
3. **마지막** git pull로 최신 업데이트 적용

이렇게 하면 어떤 문제가 생기든 쉽게 되돌릴 수 있습니다! 🛡️
