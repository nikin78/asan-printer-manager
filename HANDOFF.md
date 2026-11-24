# 작업 인수인계서 (HANDOFF) — 집 ↔ 직장 PC 양방향 공용

> **최종 갱신:** 2026-11-25 (집 PC 세션)  
> **현재 개발 버전:** `v1.0.0-beta.3` (안 A 비밀 분리 + P0 전면 안정화 + 약제팀 ZT411 PDF 규격 반영 완료)  
> **GitHub 비공개 저장소:** https://github.com/nikin78/asan-printer-manager  
> **자동 규칙 파일:** `AGENTS.md` *(Antigravity IDE가 저장소 루트 오픈 시 자동 로드)*  
> **로컬 빌드 산출물:** `dist/Asan_Printer_Manager.bat` *(`.gitignore` 처리 — 각 PC에서 `secrets.local.json`으로 로컬 빌드 후 사내 경로/USB 배포)*

---

## 1. 현재까지의 완료 현황

| 구분 | 내용 | 상태 |
| :--- | :--- | :---: |
| **보안 분리 (안 A)** | Git 추적 파일(소스/스크립트/문서)에서 병원 공용 암호 평문 **0건 완전 제거**, `secrets.local.example.json` 템플릿 추가, `secrets.local.json` + `dist/*.bat` `.gitignore` 처리 및 `build_single_bat.ps1` 빌드 시점 자동 주입 구현 | **완료 (검증 PASS)** |
| **현장 보안 잔존물 차단** | 백업 서버(`172.25.152.232`) `WriteDomainCredential` 영구 저장 제거 + 앱 종료(`FormClosing`) 시 SMB 세션 즉시 해제, `00_bootstrap.bat` 인스턴스별 `AsanMgr_Staged_*.bat`/`Startup_*.log` 분리 및 종료 시 `%TEMP%` 자가 삭제 | **완료 (검증 PASS)** |
| **P0/P1 전면 안정화 (`v1.0.0-beta.3`)** | • USB 바코드 자동 재인식 오탐 차단(정상 `USB 인쇄 지원`·`VID_0525`·Win10 `Sewoo` 제외, 실제 오류/미지정 `VID_0A5F`/`1504`만 표적 처리)<br>• 백업 시 `SEWOO_TE201` INF 추출 차단 + 복원 4단계 선설치 Win 11 세우 보호(`$wasPreExisting`) + USB/오프라인 공유 실패 시 거짓 성공 차단(`[실패 항목만 재시도]` 정상화)<br>• `Test-AsanNetworkAndServer` 외부망 `IntranetOnly` 오판 수정(집 PC `Offline` 확인)<br>• 5일 정리 NTFS 재백업 타임스탬프 버그 수정(`PrinterBackup.json` 기준 + 비반올림 통일)<br>• `EPSON_TMT88_LPT` LPT 포트 분기 + `LPT2`/`LPT3` 안내<br>• 다국어 INF `[Strings]` 영문/한글 우선순위 + `pnputil` `3010` 지원 + `PrintUIEntry /Ss` 파일 생성 검증 + `.reg` 치환 오류 보호 + 오프라인 ZIP USB 복사 실존 검증<br>• `DeleteDomainCredential` `Domain:target=` 추가, WSD UUID 우선 매칭, `@($null)` 고스트 행 방어, 버그 리포트 `AcceptsReturn`/`HostCredCache` 마스킹/`FallbackNote`, 복원 `RestoreRows` 스냅샷, DPI 125~150% `FlowLayoutPanel`, INF `DriverStore`/`LocalPrt` 지연(Lazy) 구축 | **완료 (ALL PASS)** |
| **약제팀 `ZT411` PDF 규격 반영** | `ZDesigner ZT411-203dpi ZPL` (`zd51177412-certified.exe` → `C:\ZD5-1-17-7412\ZBRN\ZBRN.inf`) 자동 INF 탐색 추가, `Get-DetectedVendors`/`Export-PreciseThirdPartyDrivers`/`Find-LocalSpecialInstaller` 보완, 도우미 체크리스트에 **마법사 [나가기] 주의 · USB/IP(Generic Network Card) 경로 · `ZebraDriver 설정.drs` 가져오기** 반영 | **완료 (검증 PASS)** |
| **자동 검증 스위트 고도화** | `verify_static.ps1` **6/6 PASS** (`src/`·`scripts/` 인코딩/CRLF + `src/`↔`dist/` SHA-256 동기화 + 안 A 검증 포함), `smoke_test_local.ps1` **3/3 PASS** (신규 단위테스트 7종 + WinForms 4탭·레이아웃 감사 0 오류) | **완료 (ALL PASS)** |

---

## 2. 직장 PC로 복귀 시 필수 1회 설정 (안 A 적용에 따름)

이번 `v1.0.0-beta.3`부터 병원 공용 암호와 `dist/Asan_Printer_Manager.bat`은 Git에서 제외되었습니다. 직장 PC에서 `git pull` 후 **최초 1회만** 아래를 실행하면 바로 현장 배포용 `.bat`이 빌드됩니다.

```powershell
# 1. 최신 코드 내려받기
git pull --ff-only

# 2. 로컬 비밀 설정 파일 생성 (최초 1회 — Git 비추적)
Copy-Item .\secrets.local.example.json .\secrets.local.json
notepad .\secrets.local.json   # DefaultPasswords에 병원 공용 암호 3종 입력 후 저장

# 3. 로컬 단일 .bat 빌드 및 전체 검증
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_single_bat.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_static.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke_test_local.ps1
```

> *(참고 — Git 과거 커밋 이력)* 현재 작업 트리(`HEAD`)에서는 평문 암호가 0건으로 완전 제거되었습니다. 다만 과거 커밋(`92b6704`, `f808b25`)과 이전 GitHub Pre-release 첨부파일(`v1.0.0-beta.1`, `v1.0.0-beta.2`)에는 이전 평문이 남아 있으므로, 완전 소거가 필요하면 GitHub Releases 기존 Pre-release 2건 삭제 및 `git filter-repo` 이력 정리를 추후 선택 진행할 수 있습니다.

---

## 3. 우선순위별 다음 작업 및 재개 지점

1. **[1순위 · 병원 현장 E2E 통합 테스트 (`v1.0.0-beta.3`)]**
   * 직장 PC에서 위 2절 순서대로 로컬 빌드한 `dist\Asan_Printer_Manager.bat`으로 Win 10 ↔ Win 11 테스트 PC(또는 VM)에서 `docs/E2E_TEST_CHECKLIST_v16.md` (`TC-01`~`TC-22`, 특히 `TC-01` `%TEMP%` 자가 정리, `TC-17B` 약제팀 ZT411 + `.drs`, `TC-17C` USB 재인식, `TC-18B` LPT1/LPT2, `TC-22` 버그 리포트)를 수행합니다.
   * 이슈 발견 시 소단위 패치 후 **`v1.0.0`** 정식 버전으로 승격합니다.
2. **[2순위 · 유지보수 선택] `src/01_core.ps1` 모듈 소분리**
   * 현재 `01_core.ps1`이 4,556줄이므로 현장 E2E 안정화 이후 `01a_ctx_win32.ps1` / `01b_net_diag.ps1` / `01c_driver_inf.ps1` / `01d_backup_restore.ps1` / `01e_special_report_snapshot.ps1`로 분리해 가독성을 높일 수 있습니다. *(단일 `dist/Asan_Printer_Manager.bat` 배포 구조 유지)*
3. **[3순위 · 보류/선택] 관리번호 DB 연동 (`.xlsx` 자체 파싱)**
   * 필요 시 용도(조회/폴더명/리포트)와 DRM 해제 샘플 `.xlsx` 공유 후 `.NET ZipFile + XmlDocument`로 외부 의존성 없이 구현.

---

## 4. 집 ↔ 직장 PC 동기화 루틴

### 매 세션 시작 시 (집/직장 공통)
```powershell
git pull --ff-only
```
* Antigravity IDE에서 반드시 **`asan-printer-manager` 폴더를 워크스페이스로 직접 열기** (`AGENTS.md` 자동 로드).

### 매 세션 종료 시 (Antigravity 자동 수행 원칙)
1. 코드 변경 시 `scripts/` 3단계 검증(`build_single_bat.ps1` → `verify_static.ps1` → `smoke_test_local.ps1`) 모두 PASS 확인
2. 본 문서(`HANDOFF.md`)의 완료 현황·이슈·다음 작업·**세션 로그(5절)** 갱신
3. `git add` → `git commit` → `git push origin main` (`secrets.local.json`, `dist/*.bat` 절대 커밋 금지)

---

## 5. 세션별 작업 로그 (최신순)

* **2026-11-25 (집 PC / `v1.0.0-beta.3`):** 안 A(평문 암호 Git 분리 → `secrets.local.json` 빌드 주입 + `dist/*.bat` gitignore + 추적 파일 평문 0건) 완료, P0/P1 보안·USB 재인식·복원·5일 정리·다국어 INF·DPI·스레드 안전성 전수 패치 완료, 약제팀 `ZT411` 공식 PDF 규격(`zd51177412-certified.exe` 마법사 [나가기] 주의, `C:\ZD5-1-17-7412\ZBRN\ZBRN.inf`, `ZebraDriver 설정.drs`) 완전 반영. `build_single_bat`(424,823B, SHA-256 `9D541761...`), `verify_static`(6/6 PASS, Core=73/GUI=50), `smoke_test_local`(3/3 PASS, 집 PC `NetStatus=Offline` 정상 확인) 통과. **다음 재개 지점:** 직장 PC에서 `git pull` + `secrets.local.json` 1회 생성 후 빌드 → 현장 E2E 테스트(`TC-01`~`TC-22`) 수행.
* **2026-11-24 (집 PC / `b2d33f0`):** 공식 Git/GitHub CLI 연동 및 클론, 전 소스 모듈 시니어 코드 감사(P0 8건 + P1 백로그 도출), `AGENTS.md`(비판적 리뷰 권한 + 집↔직장 양방향 동기화 규칙) 및 `HANDOFF.md` 개편.
* **2026-11-24 (직장 PC / `6899c54`):** `AGENTS.md` 및 초기 `HANDOFF.md` 작성·푸시.
* **2026-11-24 (직장 PC / `f808b25`):** `v1.0.0-beta.2` 릴리스 — ZT411 TCP/IP 처리, USB 바코드 자동 재인식, `_PRTBAK\_REPORTS` 버그 리포트함 추가.
* **2026-11-24 (직장 PC / `92b6704`):** `v1.0.0-beta.1` 초기 릴리스 — WinForms 4탭 GUI + EPSON TM-T88VI LPT1 정책 + 자동 빌드/검증 스위트 구축.
