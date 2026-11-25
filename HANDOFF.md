# 작업 인수인계서 (HANDOFF) — 집 ↔ 직장 PC 양방향 공용

> **최종 갱신:** 2026-11-25 14:05 (직장 PC 세션 — 재귀 코드 리뷰 Round 2·3 완료 [`[FIX-NOW]` 0건] + ZT411 골든 이미지 로컬 정책 반영 + 과거 Git 평문 암호 이력 완전 소거)  
> **현재 개발 버전:** `v1.0.0-beta.3` (안 A 비밀 분리 + P0 전면 안정화 + ZT411 골든 이미지 로컬 정책 + 재귀 리뷰 Round 1~3 완료)  
> **GitHub 비공개 저장소:** https://github.com/nikin78/asan-printer-manager  
> **자동 규칙 파일:** `AGENTS.md` *(Antigravity IDE가 저장소 루트 오픈 시 자동 로드)*  
> **로컬 빌드 산출물:** `dist/Asan_Printer_Manager.bat` *(`.gitignore` 처리 — 각 PC에서 `secrets.local.json`으로 로컬 빌드 후 사내 경로/USB 배포)*

> **[중요 · 집 PC 복귀 시 1회 동기화 안내]**  
> 이번 세션에서 초기 커밋(`92b6704`~`b2d33f0`)에 남아 있던 병원 공용 암호 평문 및 구형 `dist/Asan_Printer_Manager.bat`을 Git 전체 이력에서 완전 소거하고 강제 푸시했습니다. **집 PC에서 다음 작업 시작 시 1회만** 아래 명령으로 원격 이력에 맞춰 주세요 *(이후에는 평소대로 `git pull --ff-only` 사용)*.
> ```powershell
> git fetch origin --prune --prune-tags
> git reset --hard origin/main
> ```

---

## 1. 현재까지의 완료 현황

| 구분 | 내용 | 상태 |
| :--- | :--- | :---: |
| **보안 분리 (안 A) + 과거 이력 완전 소거** | Git 작업 트리 및 **전체 과거 커밋 이력**에서 병원 공용 암호 평문 **0건 완전 소거**, 구형 `dist/Asan_Printer_Manager.bat` 이력 제거, 구 Pre-release 및 태그(`v1.0.0-beta.1`/`.2`) 삭제, `secrets.local.json` 빌드 시점 자동 주입 구현 | **완료 (검증 PASS)** |
| **현장 보안 잔존물 차단** | 백업 서버(`172.25.152.232`) `WriteDomainCredential` 영구 저장 제거 + 앱 종료(`FormClosing`) 시 SMB 세션 즉시 해제, `00_bootstrap.bat` 인스턴스별 `AsanMgr_Staged_*.bat`/`Startup_*.log` 분리 및 종료 시 `%TEMP%` 자가 삭제 | **완료 (검증 PASS)** |
| **P0/P1 전면 안정화 (`v1.0.0-beta.3`)** | • USB 바코드 자동 재인식 오탐 차단(정상 `USB 인쇄 지원`·`VID_0525`·Win10 `Sewoo` 제외, 실제 오류/미지정 `VID_0A5F`/`1504`만 표적 처리)<br>• 백업 시 `SEWOO_TE201` INF 추출 차단 + 복원 4단계 선설치 Win 11 세우 보호(`$wasPreExisting`) + USB/오프라인 공유 실패 시 거짓 성공 차단(`[실패 항목만 재시도]` 정상화)<br>• `Test-AsanNetworkAndServer` 외부망 `IntranetOnly` 오판 수정<br>• 5일 정리 NTFS 재백업 타임스탬프 버그 수정(`PrinterBackup.json` 기준 + 비반올림 통일)<br>• `EPSON_TMT88_LPT` LPT 포트 분기 + `LPT2`/`LPT3` 안내<br>• 다국어 INF `[Strings]` 영문/한글 우선순위 + `pnputil` `3010` 지원 + `PrintUIEntry /Ss` 파일 생성 검증 + `.reg` 치환 오류 보호 + 오프라인 ZIP USB 복사 실존 검증<br>• `DeleteDomainCredential` `Domain:target=` 추가, WSD 전역 3단계(UUID→완전일치→부분일치), `@($null)` 고스트 행 방어, 버그 리포트 `AcceptsReturn`/`HostCredCache` 마스킹/`FallbackNote`, 복원 `RestoreRows` 스냅샷, DPI 125~150% `FlowLayoutPanel`, INF `DriverStore`/`LocalPrt` 지연(Lazy) 구축 | **완료 (ALL PASS)** |
| **약제팀 `ZT411` 골든 이미지 로컬 정책 반영** | • 원격 드라이버 서버(`\\172.23.2.130\driver`) 접근 완전 제거<br>• **기존 PC 추출 드라이버(`PrintBrm`/`ExportedDrivers`) + `.dat`/`.reg` 인쇄 기본 설정 복원 최우선**(`-PreExistingDrivers`/`-PreferExportedFirst`)<br>• 부득이한 경우에만 모든 골든 이미지 공통 로컬 경로(`C:\Users\admin\드라이버(win10_x64)\AMIS 3.0 장비\ZT411 (약국용 신형라벨프린터)\ZD8-6-5-26125\ZDesigner.inf`, `zd86526125-certified.exe`, `.drx`/`.drs`)로 대체 복원(`ZD410`/`ZD411`·`PrnInst.exe` 엄격 제외)<br>• 대체 복원 또는 백업 설정 미확인 시 요약 팝업·배너·도우미에서 **인쇄 기본 설정 마무리 필요** 경고 자동 표시 | **완료 (검증 PASS)** |
| **재귀 코드 리뷰 Round 1~3 완료** | • **Round 1:** 부트스트랩 `"%%SELF%%"`·이중 삭제 방지, 코어 활성 NIC DNS·원자적 백업·USB 자식→부모 재인식·`Set-Printer` try/catch, GUI `Show-AsanMessageBox`·레이아웃 압축·탭 4 비동기 미리보기 전환<br>• **Round 2 (`#2~#11`):** 중복 가드 제거, 원자적 백업 `_OLD_` 데이터 유실 방어, WSD 전역 3단계 및 `UMB\UMB` 누락 수정, `Provider=%Token%` 간접 참조 해석, Case A 공유 연결 가드, `PollTimer` 영구 잠금 해제·`FormClosing` 재진입 차단, 탭 2 `BtnSpecInstall`/`BtnSpecProps` `-RegisterBusy`, 탭 4 미리보기 `Ok` 캐싱·예외 복구·`RetiredPreviews` Dispose·150ms 디바운스·이탈/종료 선중단, `verify_static` AST `MessageBox`·`$previewScript` 검사 강화<br>• **Round 3 (`[FIX-NOW]` 0건 확인):** ZT411 선설치/USB 폴백 시 백업 우선순위 역전 및 안내 누락 경로 봉쇄, `Find-LocalSpecialInstaller` 재귀 `ZD410|ZD411` 완전 차단 + `zd8` 우선, `smoke_test_local` 플레이스홀더 모드 마스킹 검증 보강 | **완료 (`[FIX-NOW]` 0건)** |
| **자동 검증 스위트 고도화** | `verify_static.ps1` **6/6 PASS** (Core=73/GUI=56, AST `MessageBox`·`$previewScript`·`src/`↔`dist/` SHA-256 동기화 포함), `smoke_test_local.ps1` **3/3 PASS** (병원 실환경 Win 11 `NetStatus=Online` · 레이아웃 오류 0건 · `exit 99`) | **완료 (ALL PASS)** |

---

## 2. 직장 PC에서 현장 배포용 `.bat` 빌드 (필수 1회 설정)

이번 `v1.0.0-beta.3`부터 병원 공용 암호와 `dist/Asan_Printer_Manager.bat`은 Git에서 제외되었습니다. 현재 이 직장 PC에는 아직 `secrets.local.json`이 생성되지 않았으므로, 현장 테스트/배포 전 **최초 1회만** 아래를 실행하면 실제 암호가 주입된 현장 배포용 `dist\Asan_Printer_Manager.bat`이 빌드됩니다.

```powershell
# 1. 로컬 비밀 설정 파일 생성 (최초 1회 — Git 비추적)
Copy-Item .\secrets.local.example.json .\secrets.local.json
notepad .\secrets.local.json   # DefaultPasswords에 병원 공용 암호 3종 입력 후 저장

# 2. 로컬 단일 .bat 빌드 및 전체 검증
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_single_bat.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_static.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke_test_local.ps1
```

> *(참고 — IDE UTF-8 BOM 주의)* Antigravity IDE에서 `.ps1` 파일을 편집/저장하면 기본 인코딩 설정에 따라 UTF-8 BOM이 제거될 수 있습니다. 코드 수정 후 빌드·커밋 전에는 반드시 `verify_static.ps1` CHK-1 통과를 확인하세요.

---

## 3. 우선순위별 다음 작업 및 재개 지점

1. **[1순위 · 즉시 수행 가능] 병원 현장 E2E 통합 테스트 (`v1.0.0-beta.3`)**
   * 직장 PC에서 위 2절 순서대로 `secrets.local.json` 생성 후 로컬 빌드한 `dist\Asan_Printer_Manager.bat`으로 Win 10 ↔ Win 11 테스트 PC(또는 VM)에서 `docs/E2E_TEST_CHECKLIST_v16.md` (`TC-01`~`TC-22`, 특히 `TC-01` `%TEMP%` 자가 정리, `TC-17B` 약제팀 ZT411 기존 복원 우선/골든 이미지 폴백 및 인쇄 기본 설정 경고, `TC-17C` USB 재인식, `TC-18B` LPT1/LPT2, `TC-22` 버그 리포트)를 수행합니다.
   * 이슈 발견 시 소단위 패치 후 **`v1.0.0`** 정식 버전으로 승격합니다.
2. **[2순위 · 유지보수 선택] `src/01_core.ps1` 모듈 소분리**
   * 현재 `01_core.ps1`이 약 4,900줄이므로 현장 E2E 안정화 이후 `01a_ctx_win32.ps1` / `01b_net_diag.ps1` / `01c_driver_inf.ps1` / `01d_backup_restore.ps1` / `01e_special_report_snapshot.ps1`로 분리해 가독성을 높일 수 있습니다. *(단일 `dist/Asan_Printer_Manager.bat` 배포 구조 유지)*
3. **[3순위 · 보류/선택] 관리번호 DB 연동 (`.xlsx` 자체 파싱)**
   * 필요 시 용도(조회/폴더명/리포트)와 DRM 해제 샘플 `.xlsx` 공유 후 `.NET ZipFile + XmlDocument`로 외부 의존성 없이 구현.

---

## 4. 집 ↔ 직장 PC 동기화 루틴

### 매 세션 시작 시 (집/직장 공통)
```powershell
git pull --ff-only
```
* Antigravity IDE에서 반드시 **`asan-printer-manager-v16`(저장소 루트) 폴더를 워크스페이스로 직접 열기** (`AGENTS.md` 자동 로드).

### 매 세션 종료 시 (Antigravity 자동 수행 원칙)
1. 코드 변경 시 `scripts/` 3단계 검증(`build_single_bat.ps1` → `verify_static.ps1` → `smoke_test_local.ps1`) 모두 PASS 확인
2. 본 문서(`HANDOFF.md`)의 완료 현황·이슈·다음 작업·**세션 로그(5절)** 갱신
3. `git add` → `git commit` → `git push origin main` (`secrets.local.json`, `dist/*.bat` 절대 커밋 금지)

---

## 5. 세션별 작업 로그 (최신순)

* **2026-11-25 14:05 (직장 PC / Round 2·3 완료 & ZT411 정책 확정 & 평문 이력 소거):** 재귀 코드 리뷰 Round 2 `[FIX-NOW]` #2~#11 전량 반영 + ZT411 원격 서버(`172.23.2.130`) 접근 제거 및 골든 이미지 로컬 경로(`C:\Users\admin\드라이버(win10_x64)\AMIS 3.0 장비\ZT411 (약국용 신형라벨프린터)\ZD8-6-5-26125\ZDesigner.inf`) 폴백·기존 PC 복원 우선·인쇄 기본 설정 마무리 경고 구현 → Round 3 재귀 감사 지적 3건(ZT411 선설치/USB 폴백 우선순위 역전, `ZD410|ZD411` 재귀 누수, BOM 정규화) 수정 및 재확인 **`[FIX-NOW]` 0건** 달성. 검증: `build_single_bat`(464,992B, 플레이스홀더 모드), `verify_static` 6/6 PASS(Core=73/GUI=56, BarePreview=0), `smoke_test_local` 3/3 PASS(병원 실환경 Win 11 `Online`, 레이아웃 오류 0). 초기 커밋(`92b6704`~`b2d33f0`) 평문 암호·`dist/*.bat` 이력 완전 소거 및 강제 푸시 완료. **다음 재개 지점:** 직장 PC `secrets.local.json` 1회 생성 후 실제 배포용 `.bat` 빌드 → 현장 E2E 테스트(`TC-01`~`TC-22`) 수행.
* **2026-11-25 05:00 (집 PC / 재귀 리뷰 Round 1):** 구 Pre-release `v1.0.0-beta.1/2` 삭제, 재귀 코드 리뷰 Round 1 지적 11개 그룹 전량 반영(수정 파일: `src/00_bootstrap.bat`, `src/01_core.ps1`, `src/02_gui_shell_tab1.ps1`, `src/03_gui_tab2.ps1`, `src/04_gui_tab3_tab4_main.ps1`, `scripts/build_single_bat.ps1`, `scripts/verify_static.ps1`, `scripts/smoke_test_local.ps1`). 검증: `build_single_bat`(442,171B, SHA-256 `669B0568...`), `verify_static` 6/6 PASS(Core=73/GUI=54), `smoke_test_local` 3/3 PASS(레이아웃 이슈 0, `NetStatus=Offline`). Round 2 감사에서 `[FIX-NOW]` 11건 도출 → **사용자 요청으로 수정 전 중단·커밋**. **다음 재개 지점:** 3절 0순위 항목 2~11 수정 → Round 3 감사.

* **2026-11-25 (집 PC / `v1.0.0-beta.3`):** 안 A(평문 암호 Git 분리 → `secrets.local.json` 빌드 주입 + `dist/*.bat` gitignore + 추적 파일 평문 0건) 완료, P0/P1 보안·USB 재인식·복원·5일 정리·다국어 INF·DPI·스레드 안전성 전수 패치 완료, 약제팀 `ZT411` 공식 PDF 규격(`zd51177412-certified.exe` 마법사 [나가기] 주의, `C:\ZD5-1-17-7412\ZBRN\ZBRN.inf`, `ZebraDriver 설정.drs`) 완전 반영. `build_single_bat`(424,823B, SHA-256 `9D541761...`), `verify_static`(6/6 PASS, Core=73/GUI=50), `smoke_test_local`(3/3 PASS, 집 PC `NetStatus=Offline` 정상 확인) 통과. **다음 재개 지점:** 직장 PC에서 `git pull` + `secrets.local.json` 1회 생성 후 빌드 → 현장 E2E 테스트(`TC-01`~`TC-22`) 수행.
* **2026-11-24 (집 PC / `b2d33f0`):** 공식 Git/GitHub CLI 연동 및 클론, 전 소스 모듈 시니어 코드 감사(P0 8건 + P1 백로그 도출), `AGENTS.md`(비판적 리뷰 권한 + 집↔직장 양방향 동기화 규칙) 및 `HANDOFF.md` 개편.
* **2026-11-24 (직장 PC / `6899c54`):** `AGENTS.md` 및 초기 `HANDOFF.md` 작성·푸시.
* **2026-11-24 (직장 PC / `f808b25`):** `v1.0.0-beta.2` 릴리스 — ZT411 TCP/IP 처리, USB 바코드 자동 재인식, `_PRTBAK\_REPORTS` 버그 리포트함 추가.
* **2026-11-24 (직장 PC / `92b6704`):** `v1.0.0-beta.1` 초기 릴리스 — WinForms 4탭 GUI + EPSON TM-T88VI LPT1 정책 + 자동 빌드/검증 스위트 구축.
