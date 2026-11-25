# 작업 인수인계서 (HANDOFF) — 집 ↔ 직장 PC 양방향 공용

> **최종 갱신:** 2026-11-26 04:10 (집 PC — 비활성 버튼 점선/사유 툴팁 · 오류 자동 리포트 안내(온·오프라인) · 사내망 네트워크 표기 직관화 · 재귀 UX 보강 · 3단계 검증 및 시각 감사 PASS)  
> **현재 개발 버전:** `v1.0.0-beta.3` (안 A 비밀 분리 + P0 전면 안정화 + ZT411 골든 이미지 로컬 정책 + 재귀 리뷰 Round 1~4 + 코어 5모듈 소분리 + 고시인성 UI/UX·비활성 사유 툴팁·자동 오류 리포트 안내 완료)  
> **GitHub 비공개 저장소:** https://github.com/nikin78/asan-printer-manager  
> **자동 규칙 파일:** `AGENTS.md` *(Antigravity IDE가 저장소 루트 오픈 시 자동 로드)*  
> **로컬 빌드 산출물:** `dist/Asan_Printer_Manager.bat` *(`.gitignore` 처리 — 각 PC에서 `secrets.local.json`으로 로컬 빌드 후 사내 경로/USB 배포)*

---

## 1. 현재까지의 완료 현황

| 구분 | 내용 | 상태 |
| :--- | :--- | :---: |
| **보안 분리 (안 A) + 과거 이력 완전 소거** | Git 작업 트리 및 **전체 과거 커밋 이력**에서 병원 공용 암호 평문 **0건 완전 소거**, 구형 `dist/Asan_Printer_Manager.bat` 이력 제거, 구 Pre-release 및 태그(`v1.0.0-beta.1`/`.2`) 삭제, `secrets.local.json` 빌드 시점 자동 주입 구현 | **완료 (검증 PASS)** |
| **현장 보안 잔존물 차단** | 백업 서버(`172.25.152.232`) `WriteDomainCredential` 영구 저장 제거 + 앱 종료(`FormClosing`) 시 SMB 세션 즉시 해제, `00_bootstrap.bat` 인스턴스별 `AsanMgr_Staged_*.bat`/`Startup_*.log` 분리 및 종료 시 `%TEMP%` 자가 삭제 | **완료 (검증 PASS)** |
| **P0/P1 전면 안정화 (`v1.0.0-beta.3`)** | • USB 바코드 자동 재인식 오탐 차단(정상 `USB 인쇄 지원`·`VID_0525`·Win10 `Sewoo` 제외, 실제 오류/미지정 `VID_0A5F`/`1504`만 표적 처리)<br>• 백업 시 `SEWOO_TE201` INF 추출 차단 + 복원 4단계 선설치 Win 11 세우 보호(`$wasPreExisting`) + USB/오프라인 공유 실패 시 거짓 성공 차단(`[실패 항목만 재시도]` 정상화)<br>• `Test-AsanNetworkAndServer` 외부망 `IntranetOnly` 오판 수정<br>• 5일 정리 NTFS 재백업 타임스탬프 버그 수정(`PrinterBackup.json` 기준 + 비반올림 통일)<br>• `EPSON_TMT88_LPT` LPT 포트 분기 + `LPT2`/`LPT3` 안내<br>• 다국어 INF `[Strings]` 영문/한글 우선순위 + `pnputil` `3010` 지원 + `PrintUIEntry /Ss` 파일 생성 검증 + `.reg` 치환 오류 보호 + 오프라인 ZIP USB 복사 실존 검증<br>• `DeleteDomainCredential` `Domain:target=` 추가, WSD 전역 3단계(UUID→완전일치→부분일치), `@($null)` 고스트 행 방어, 버그 리포트 `AcceptsReturn`/`HostCredCache` 마스킹/`FallbackNote`, 복원 `RestoreRows` 스냅샷, DPI 125~150% `FlowLayoutPanel`, INF `DriverStore`/`LocalPrt` 지연(Lazy) 구축 | **완료 (ALL PASS)** |
| **약제팀 `ZT411` 골든 이미지 로컬 정책 반영** | • 원격 드라이버 서버(`\\172.23.2.130\driver`) 접근 완전 제거<br>• **기존 PC 추출 드라이버(`PrintBrm`/`ExportedDrivers`) + `.dat`/`.reg` 인쇄 기본 설정 복원 최우선**(`-PreExistingDrivers`/`-PreferExportedFirst`)<br>• 부득이한 경우에만 모든 골든 이미지 공통 로컬 경로(`C:\Users\admin\드라이버(win10_x64)\AMIS 3.0 장비\ZT411 (약국용 신형라벨프린터)\ZD8-6-5-26125\ZDesigner.inf`, `zd86526125-certified.exe`, `.drx`/`.drs`)로 대체 복원(`ZD410`/`ZD411`·`PrnInst.exe` 엄격 제외)<br>• 대체 복원 또는 백업 설정 미확인 시 요약 팝업·배너·도우미에서 **인쇄 기본 설정 마무리 필요** 경고 자동 표시 | **완료 (검증 PASS)** |
| **재귀 코드 리뷰 Round 1~3 완료** | • **Round 1:** 부트스트랩 `"%%SELF%%"`·이중 삭제 방지, 코어 활성 NIC DNS·원자적 백업·USB 자식→부모 재인식·`Set-Printer` try/catch, GUI `Show-AsanMessageBox`·레이아웃 압축·탭 4 비동기 미리보기 전환<br>• **Round 2 (`#2~#11`):** 중복 가드 제거, 원자적 백업 `_OLD_` 데이터 유실 방어, WSD 전역 3단계 및 `UMB\UMB` 누락 수정, `Provider=%Token%` 간접 참조 해석, Case A 공유 연결 가드, `PollTimer` 영구 잠금 해제·`FormClosing` 재진입 차단, 탭 2 `BtnSpecInstall`/`BtnSpecProps` `-RegisterBusy`, 탭 4 미리보기 `Ok` 캐싱·예외 복구·`RetiredPreviews` Dispose·150ms 디바운스·이탈/종료 선중단, `verify_static` AST `MessageBox`·`$previewScript` 검사 강화<br>• **Round 3 (`[FIX-NOW]` 0건 확인):** ZT411 선설치/USB 폴백 시 백업 우선순위 역전 및 안내 누락 경로 봉쇄, `Find-LocalSpecialInstaller` 재귀 `ZD410|ZD411` 완전 차단 + `zd8` 우선, `smoke_test_local` 플레이스홀더 모드 마스킹 검증 보강 | **완료 (`[FIX-NOW]` 0건)** |
| **코어 모듈 5분할 (`01a`~`01e`) + 문서 동기화** | 약 4,900줄의 `src/01_core.ps1`을 `01a_ctx_win32.ps1` / `01b_net_diag.ps1` / `01c_driver_inf.ps1` / `01d_backup_restore.ps1` / `01e_special_report_snapshot.ps1`로 **비공백 코드 0줄 차이 무손실 분할**(단일 `.bat` 배포 유지), `AGENTS.md`(2·3-5·4절)·`build_single_bat`·`verify_static`·`README.md`·`E2E_TEST_CHECKLIST_v16.md` 동기화 | **완료 (무손실 검증 PASS)** |
| **재귀 코드 리뷰 Round 4 (17건 패치 + 검증 사각지대 해소)** | • **P0 현장 치명 결함 수정:** WOW64 32비트 진입 시 UAC 승격 100% 실패(`Sysnative\cmd.exe`→`System32\cmd.exe`), 신규 TCP/IP 포트 생성 `HRESULT 0x80070057`(`Add-PrinterPort -SNMP 0` 제거), `신도리코`→`RICOH` 오탐 및 Zebra `203dpi`/`52병동` 교차 매칭 차단, `DriverStore` 중복 INF `break` 누락·`_x86_`/`_arm64_` 제외<br>• **보안·안정성 보강:** `%TEMP%\AsanPrinterMgr_*.ps1` 로드 직후 즉시 삭제, `EnumPrintSharesEx` `try/finally` 버퍼 해제, `Get-SmbMapping` 드라이브 매핑 정리, 백업 서버 `WriteDomainCredential` 이중 가드, `Test-UncSharePrinterAlive` 오류 코드 구분·재시도, WSD 1단계 완료 시 조기 종료, `PrintBrm -b` 0바이트 검증·`_OLD_` 원자 롤백·GUID 임시폴더 격리, 스풀러 중지 실패/USB 바코드 양방향 보호/`.reg` 실패 전파, `Get-BackupEffectiveWriteTime` fail-closed, `Protect-ReportSensitiveText` JSON 이스케이프 마스킹<br>• **검증 사각지대 해소:** `build_single_bat` `-AllowPlaceholderBuild` 버그·`CHANGE_ME_` 차단, `verify_static` 부트스트랩 추출 원라이너 실실행·`CoreToGui=0`·`ScriptVarsInWork=0` 검사 추가, `smoke_test_local` Round 4 회귀 단위테스트 + `960×640` WPP 동시 노출 감사 추가 | **완료 (ALL PASS)** |
| **고시인성 아산 그린·오렌지 UI/UX · 상용 UX 라이팅 · 구 PC Win 10/11 공용 지원** | • **저작권 로고 제외:** 병원 공식 로고 PNG를 완전 제거하고 자체 GDI+ 벡터 프린터 심볼 배지·앱 아이콘만 사용<br>• **가시성 전면 강화:** 딥 아산 그린(`#005658`) 헤더 + 2px 아산 오렌지 라인 + 딥 틸(`#0B4F51`) 흰 글씨 표 헤더 + 선명한 테두리 버튼 + 5색 상태 구분(`정상` 그린 / `WSD 전환` 스카이시안 / `특수 장비` 퍼플 / `확인 필요` 오렌지 / `인증 오류` 레드) + `1단계`/`2단계` 배지 + 툴팁(`ToolTip`)<br>• **구 PC Win 10/11 공용 로직:** 백업 JSON/리포트에 `SourceOsName`/`SourceOsBuild`/`SourceIsWin11` 저장 및 탭 2 표시, 기동 시 서버 자동 매칭 백업 유무로 백업/복원 탭 지능 선택 + 탭 1 최초 진입 지연 자동 스캔 추가, `(Win 10)`/`(Win 11)` 고정 표기 제거<br>• **상용 UX 라이팅 정비:** `※`/`★`/`▶`/`[...]`/괄호 단문 표기 제거 및 직관적 동사형 버튼·친절한 안내 문구(`~해 주세요`) 적용 | **완료 (시각·자동 PASS)** |
| **자동 검증 스위트 고도화** | `verify_static.ps1` **6/6 PASS** (9모듈·Core=73/GUI=60, 부트스트랩 추출 실실행·`CoreToGui=0`·`ScriptVarsInWork=0`·AST `MessageBox`·`$previewScript`·`src/` 미등록 파일·`src/`↔`dist/` SHA-256 동기화), `smoke_test_local.ps1` **3/3 PASS** (Round 4 회귀 단위테스트 + `1040×720`/`960×640`+WPP 레이아웃 오류 0건 · `exit 99`) | **완료 (ALL PASS)** |

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

1. **[1순위 · 즉시 수행 가능 (직장/병원 PC)] 병원 현장 E2E 통합 테스트 (`v1.0.0-beta.3`)**
   * 직장 PC에서 `git pull --ff-only` 후 위 2절 순서대로 `secrets.local.json` 생성 → 로컬 빌드한 `dist\Asan_Printer_Manager.bat`으로 Win 10 ↔ Win 11 테스트 PC(또는 VM)에서 `docs/E2E_TEST_CHECKLIST_v16.md` (`TC-01`~`TC-22`, 특히 `TC-01` `%TEMP%` 자가 정리, `TC-17B` 약제팀 ZT411 기존 복원 우선/골든 이미지 폴백 및 인쇄 기본 설정 경고, `TC-17C` USB 재인식, `TC-18B` LPT1/LPT2, `TC-22` 버그 리포트)를 수행합니다.
   * 이슈 발견 시 소단위 패치 후 **`v1.0.0`** 정식 버전으로 승격합니다.
2. **[2순위 · 보류/선택] 관리번호 DB 연동 (`.xlsx` 자체 파싱)**
   * 필요 시 용도(조회/폴더명/리포트)와 DRM 해제 샘플 `.xlsx` 공유 후 `.NET ZipFile + XmlDocument`로 외부 의존성 없이 구현.

---

## 4. 집 ↔ 직장 PC 동기화 루틴

### 매 세션 시작 시 (집/직장 공통)
```powershell
git pull --ff-only
```
* Antigravity IDE에서 반드시 **`asan-printer-manager`(저장소 루트) 폴더를 워크스페이스로 직접 열기** (`AGENTS.md` 자동 로드).

### 매 세션 종료 시 (Antigravity 자동 수행 원칙)
1. 코드 변경 시 `scripts/` 3단계 검증(`build_single_bat.ps1` → `verify_static.ps1` → `smoke_test_local.ps1`) 모두 PASS 확인
2. 본 문서(`HANDOFF.md`)의 완료 현황·이슈·다음 작업·**세션 로그(5절)** 갱신
3. `git add` → `git commit` → `git push origin main` (`secrets.local.json`, `dist/*.bat` 절대 커밋 금지)

---

## 5. 세션별 작업 로그 (최신순)

* **2026-11-26 04:10 (집 PC / 비활성 버튼 점선·사유 툴팁 · 작업 오류 자동 리포트 안내 · 네트워크 표기 직관화 · 재귀 UX 보강):**
  * **완료 작업:**
    1. **비활성 버튼 직관성 & 사유 툴팁 (`02_gui_shell_tab1.ps1`):** WinForms 비활성 `GrayText` 한계를 GDI+ `Add_Paint`로 대체해 점선 테두리·연한 무채색·비굵은 글씨로 즉시 구분되게 개선하고, 비활성 컨트롤 툴팁 미발동 한계를 부모 컨테이너 `MouseMove`/`GetChildAtPoint` 라우팅(`Register-DisabledTooltipTree`) + `Set-ButtonTipState`로 해결해 전 탭 모든 비활성 버튼에 실시간 사유 툴팁 제공.
    2. **전 작업 오류 자동 리포트 구성 안내 (`02`~`04`):** `Invoke-ErrorWithAutoReportPrompt`를 환경 진단·스캔·백업·복원·공유 인증·SIP-30M·USB 재인식·표준 설정·스풀러 초기화·서버 정리/삭제 전체 오류 경로에 통합(사내망 연결 시 서버 리포트함 전송, 사내망 미연결 시 로컬 `C:\_AsanPrtOffline\_Reports` 저장 + 폴더 열기 안내; `Show-BugReportDialog`도 온/오프라인 자동 적응).
    3. **네트워크 상태 표기 직관화 (`01b`, `02`, `03`, `04`):** `오프라인` → `사내망 미연결` / `사내망 연결 · 서버 미응답` / `사내망 · 서버 연결됨` 및 `네트워크 미확인` 상태로 통일 + 배지 상세 툴팁 추가.
    4. **재귀 UX 개선:** 전 탭 표 잘린 셀 전체 내용 `ToolTipText`, 탭 2 `1단계` 드롭다운 선택 즉시 로드(`SelectionChangeCommitted`)·`3단계` 배지·접힌 도우미 건수 표시, 탭 4 행 더블클릭 즉시 로드·검색어 `지우기` 버튼, `SID 복사` 즉각 피드백(`복사됨` 1.5초 표시 + 하단 상태 바 안내), 하단 상태 바 실행/오류 색상 구분 적용.
  * **검증 결과:** `build_single_bat` (529,392B, 10,584줄, `secrets.local.json` 실암호 3종 주입, SHA-256 `28E48F9F...`), `verify_static` **6/6 PASS** (`Core=73/GUI=64`, `UndefinedCalls=0`, `GuiInWork=0`, `ScriptVarsInWork=0`, `CoreToGui=0`, `SrcEncIssues=0`), `smoke_test_local` **3/3 PASS** (`DisabledReasons` 등록 검증 포함, `RuntimeErrors=0`, `LayoutIssues(1040×720 & 960×640)=0`, `exit 99`), 4화면(`Tab1 사내망 미연결`, `Tab2`, `Tab4`, `Tab2 960×640`) 실제 렌더링 시각 감사 완료.
  * **다음 재개 지점:** 직장 PC에서 `git pull --ff-only` → `secrets.local.json` 1회 생성 후 `dist\Asan_Printer_Manager.bat` 로컬 빌드 → 병원 현장 E2E 통합 테스트(`docs/E2E_TEST_CHECKLIST_v16.md` `TC-01`~`TC-22`) 수행 후 **`v1.0.0`** 정식 승격.
* **2026-11-26 03:41 (집 PC / 저작권 로고 제거 · 고시인성 UI/UX 개편 · 구 PC Win 10/11 공용 로직 · 상용 UX 라이팅 정비):**
  * **완료 작업:**
    1. **저작권 로고 완전 제거:** `02_gui_shell_tab1.ps1`에서 병원 공식 로고 PNG(`AsanLogoB64`) 제거 → 순수 GDI+로 직접 그리는 자체 프린터 심볼 배지(`New-AsanPrinterBadgeImage`)·앱 아이콘으로 대체(산출물 약 4.4KB 경량화).
    2. **고시인성 UI/UX 개편:** 딥 아산 그린(`#005658`) 헤더 + 2px 아산 오렌지 포인트 바 + 고대비 환경 요약 바 + 딥 틸(`#0B4F51`) 흰 글씨 표 헤더 + 선명한 테두리 보조 버튼 + 5색 상태 구분(`정상` `#006769`, `WSD 전환` `#0280A8`, `특수 장비` `#6224C6`, `확인 필요` `#E07008`, `인증 오류` `#C0392B`) + 탭 2 `1단계`/`2단계` 컬러 배지 + 툴팁(`ToolTip`) 적용.
    3. **구 PC Win 10/11 공용 코드·문구 정비:** `01d_backup_restore.ps1` 백업 JSON/리포트에 `SourceOsName`/`SourceOsBuild`/`SourceIsWin11` 저장 + 탭 2 원본 요약 표시, `04_gui_tab3_tab4_main.ps1` 기동 시 `IsWin11`만으로 복원 탭 강제 이동하던 로직을 **서버 자동 매칭 백업 존재 시에만 복원 탭 자동 진입, 미존재 시 백업 탭 자동 진단**으로 개선 + 탭 1 최초 진입 지연 자동 스캔 추가, 전 화면 `(Win 10)`/`(Win 11)` 고정 문구 및 `Win 10 구형` 단정 문구 정비(`SEWOO_TE201` 격리/잠금 안전 규칙은 유지).
    4. **상용 UX 라이팅 정비:** Microsoft Windows·한국어 상용 UX 라이팅 기준에 따라 `※`/`★`/`▶`/`[...]`/괄호 단문 표기를 전수 제거하고 간결한 동사형 버튼·`~해 주세요` 안내 문구로 개편.
  * **검증 결과:** `build_single_bat` · `verify_static` **6/6 PASS** (`Core=73/GUI=61`, `UndefinedCalls=0`, `GuiInWork=0`, `ScriptVarsInWork=0`, `CoreToGui=0`, `SrcEncIssues=0`), `smoke_test_local` **3/3 PASS** (`InitTab=0 (IsWin11=True)`, `SewooLocked=True`, `RuntimeErrors=0`, `LayoutIssues(1040×720 & 960×640)=0`, `exit 99`), 실제 렌더링 5화면(`Tab1`~`Tab4` 1040×720 + `Tab2` 960×640) 시각 감사 완료.
  * **다음 재개 지점:** 직장 PC에서 `git pull --ff-only` → `secrets.local.json` 1회 생성 후 `dist\Asan_Printer_Manager.bat` 로컬 빌드 → 병원 현장 E2E 통합 테스트(`docs/E2E_TEST_CHECKLIST_v16.md` `TC-01`~`TC-22`) 수행 후 **`v1.0.0`** 정식 승격.
* **2026-11-25 22:03 (집 PC / `AGENTS.md` 3-5 갱신 · 재귀 코드 리뷰 Round 4 17건 패치 · 서울아산병원 CI UI/UX 전면 리뉴얼):**
  * **완료 작업:**
    1. 사용자 승인에 따라 `AGENTS.md` 3절 규칙 5의 코어 파일 경로를 `src/01a_ctx_win32.ps1`~`01e_special_report_snapshot.ps1`(`01e` 스냅샷 기준)로 최신화.
    2. **재귀 코드 리뷰 Round 4(전체 9모듈 + `scripts/` 3종 심층 감사) 17건 전량 패치:** WOW64 `Sysnative\cmd.exe` UAC 승격 실패, `Add-PrinterPort -SNMP 0` `0x80070057`, `신도리코`→`RICOH`·Zebra `203dpi`/`52병동` 교차 매칭, `DriverStore` `break` 누락·`_x86_`/`_arm64_` 제외, `%TEMP%` 추출 `.ps1` 로드 직후 자가 삭제, `EnumPrintSharesEx` `try/finally` 해제, `Get-SmbMapping` 세션 정리, 백업 서버 자격증명 저장 가드, `Test-UncSharePrinterAlive` Win32 오류 판별/재시도, WSD 1단계 조기 종료, `PrintBrm -b` 0바이트 검사·GUID 임시폴더·`_OLD_` 롤백, 스풀러 중지 실패/USB 바코드 양방향 보호/고아 특수 드라이버 격리/ZT411 `.reg` 실패 경고 전파, `Get-BackupEffectiveWriteTime` fail-closed, `Protect-ReportSensitiveText` JSON 이스케이프 마스킹, `build_single_bat` `-AllowPlaceholderBuild`/`CHANGE_ME_` 가드, `verify_static` CHK-2 실추출·CHK-6 `CoreToGui`/`ScriptVarsInWork` 검사, `smoke_test_local` 회귀 테스트·`960×640` WPP 감사 추가.
    3. **서울아산병원 공식 CI 기반 UI/UX 전면 리뉴얼 (`02`~`04`):** 원내 공식 로고(`140×38` PNG 내장) + GDI+ 커스텀 아산 그린 프린터 앱 아이콘 + 공식 CI 컬러(`#006769`/`#004F51`/`#EC7A08`/`#F3F6F5`), 2단 화이트 헤더 + 3px 브랜드 바 + 컴팩트 메타 바, `OwnerDrawFixed` 4단계 번호 탭(`①~④`), 4계층 버튼 위계 및 `EnabledChanged` 비활성 음영 자동화, 탭 1 실색상 범례 칩, 탭 2 `1단계→2단계→3단계` 작업 흐름 카드 및 적응형 도우미 높이 계산, 탭 3 선택 연동, 하단 작업 로그 기본 접힘(`작업 로그 보기 ▲`) 적용.
  * **검증 결과:** `build_single_bat`(512,172B, 10,131줄, `secrets.local.json` 실암호 3종 주입, SHA-256 `F32C09E3...`), `verify_static` **6/6 PASS**(Core=73/GUI=60, `Duplicates=0`, `UndefinedCalls=0`, `GuiInWork=0`, `ScriptVarsInWork=0`, `CoreToGui=0`, `BarePreviewCalls=0`, `SrcEncIssues=0`, `RUNSPACE_OK`), `smoke_test_local` **3/3 PASS**(Round 4 회귀 테스트 + `1040×720`/`960×640`+WPP 동시 노출 `LayoutIssues=0`, `RuntimeErrors=0`, `exit 99`), 실제 렌더링 PNG 5화면(`Tab1`~`Tab4` 1040×720 + `Tab2` 960×640) 시각 감사 완료.
  * **다음 재개 지점:** 직장 PC에서 `git pull --ff-only` → `secrets.local.json` 1회 생성 후 `dist\Asan_Printer_Manager.bat` 로컬 빌드 → 병원 현장 E2E 통합 테스트(`docs/E2E_TEST_CHECKLIST_v16.md` `TC-01`~`TC-22`) 수행 후 **`v1.0.0`** 정식 승격.
* **2026-11-25 21:10 (집 PC / 원격 이력 동기화 · 코어 모듈 5분할 무손실 완료 · 운영 문서 동기화):**
  * **완료 작업:** 원격 강제 푸시 이력 동기화(`git fetch --prune --prune-tags` + `git reset --hard origin/main` + 로컬 `.git` 과거 평문 객체 `reflog expire`/`gc --prune=now` 정리) → 집 PC `secrets.local.json` 실암호 3종 주입 3단계 검증 사전 확인 → 2순위 작업인 `src/01_core.ps1`(4,902줄)을 5개 코어 모듈(`01a_ctx_win32.ps1` 328줄, `01b_net_diag.ps1` 1,669줄, `01c_driver_inf.ps1` 742줄, `01d_backup_restore.ps1` 1,353줄, `01e_special_report_snapshot.ps1` 806줄)로 무손실 분할하고 `build_single_bat.ps1`·`verify_static.ps1`·`smoke_test_local.ps1` 갱신(`verify_static`에 `src/` 미등록 파일 잔존 감지 추가) → `README.md`(구형 ZT411 `zd51177412`/`C:\ZD5-1-17-7412` 안내를 최신 골든 이미지 로컬 정책 `zd86526125`/`ZDesigner.inf`으로 동기화, 9모듈 트리 반영), `docs/E2E_TEST_CHECKLIST_v16.md`(`TC-01` `%TEMP%` 자가 정리 파일명 보강), `AGENTS.md`(2·4절 모듈 경로 갱신, 3절 원문 보존), `CHANGELOG.md`, `HANDOFF.md` 최신화.
  * **무손실 교차 검증:** 분할 전(`464,991B`, 9,374줄) ↔ 분할 후(`464,983B`, 9,370줄) 비교 결과 경계 빈 줄 4개(8B) 외 **비공백 8,441줄 100% 일치(`ExactDiffs=0`, 코드/주석/문자열 변화 0바이트)**.
  * **검증 결과:** `build_single_bat`(464,983B, `secrets.local.json` 3종 암호 주입, SHA-256 `59325E97...`), `verify_static` **6/6 PASS**(9모듈, Core=73/GUI=56, SrcEncIssues=0, BarePreview=0), `smoke_test_local` **3/3 PASS**(집 PC Win 11 `Offline`, 레이아웃 오류 0, `exit 99`).
  * **다음 재개 지점:** 직장 PC에서 `git pull --ff-only` → `secrets.local.json` 1회 생성 후 실제 배포용 `dist\Asan_Printer_Manager.bat` 로컬 빌드 → 병원 현장 E2E 통합 테스트(`docs/E2E_TEST_CHECKLIST_v16.md` `TC-01`~`TC-22`) 수행 후 **`v1.0.0`** 정식 승격.
* **2026-11-25 16:20 (직장 PC / Round 2·3 완료 · ZT411 정책 확정 · 평문 이력 소거 · 세션 마감):**
  * **완료 작업:** 재귀 코드 리뷰 Round 2 `[FIX-NOW]` #2~#11 전량 반영 + ZT411 원격 서버(`172.23.2.130`) 접근 제거 및 골든 이미지 로컬 경로(`C:\Users\admin\드라이버(win10_x64)\AMIS 3.0 장비\ZT411 (약국용 신형라벨프린터)\ZD8-6-5-26125\ZDesigner.inf`) 폴백·기존 PC 복원 우선·인쇄 기본 설정 마무리 경고 구현 → Round 3 재귀 감사 지적 3건(ZT411 선설치/USB 폴백 우선순위 역전, `ZD410|ZD411` 재귀 누수, BOM 정규화) 수정 및 재확인 **`[FIX-NOW]` 0건** 달성 + 초기 커밋 평문 암호 및 구형 `dist/*.bat` 전체 Git 이력 소거·강제 푸시 완료.
  * **수정/추가된 파일 (10개):** `src/01_core.ps1`, `src/02_gui_shell_tab1.ps1`, `src/03_gui_tab2.ps1`, `src/04_gui_tab3_tab4_main.ps1`, `scripts/verify_static.ps1`, `scripts/smoke_test_local.ps1`, `docs/E2E_TEST_CHECKLIST_v16.md`, `CHANGELOG.md`, `HANDOFF.md`, `.editorconfig`.
  * **검증 결과:** `build_single_bat`(464,992B, 플레이스홀더 모드), `verify_static` **6/6 PASS**(Core=73/GUI=56, BarePreview=0, SrcEncIssues=0), `smoke_test_local` **3/3 PASS**(병원 실환경 Win 11 `Online`, 레이아웃 오류 0, `exit 99`).
  * **다음 재개 지점:** ① *(집 PC 최초 1회)* `git fetch origin --prune --prune-tags && git reset --hard origin/main` 동기화 ② *(직장 PC)* `secrets.local.json` 1회 생성 후 실제 배포용 `dist\Asan_Printer_Manager.bat` 로컬 빌드 → 병원 현장 E2E 테스트(`docs/E2E_TEST_CHECKLIST_v16.md` `TC-01`~`TC-22`) 수행 후 `v1.0.0` 정식 승격.
* **2026-11-25 05:00 (집 PC / 재귀 리뷰 Round 1):** 구 Pre-release `v1.0.0-beta.1/2` 삭제, 재귀 코드 리뷰 Round 1 지적 11개 그룹 전량 반영(수정 파일: `src/00_bootstrap.bat`, `src/01_core.ps1`, `src/02_gui_shell_tab1.ps1`, `src/03_gui_tab2.ps1`, `src/04_gui_tab3_tab4_main.ps1`, `scripts/build_single_bat.ps1`, `scripts/verify_static.ps1`, `scripts/smoke_test_local.ps1`). 검증: `build_single_bat`(442,171B, SHA-256 `669B0568...`), `verify_static` 6/6 PASS(Core=73/GUI=54), `smoke_test_local` 3/3 PASS(레이아웃 이슈 0, `NetStatus=Offline`). Round 2 감사에서 `[FIX-NOW]` 11건 도출 → **사용자 요청으로 수정 전 중단·커밋**. **다음 재개 지점:** 3절 0순위 항목 2~11 수정 → Round 3 감사.

* **2026-11-25 (집 PC / `v1.0.0-beta.3`):** 안 A(평문 암호 Git 분리 → `secrets.local.json` 빌드 주입 + `dist/*.bat` gitignore + 추적 파일 평문 0건) 완료, P0/P1 보안·USB 재인식·복원·5일 정리·다국어 INF·DPI·스레드 안전성 전수 패치 완료, 약제팀 `ZT411` 공식 PDF 규격(`zd51177412-certified.exe` 마법사 [나가기] 주의, `C:\ZD5-1-17-7412\ZBRN\ZBRN.inf`, `ZebraDriver 설정.drs`) 완전 반영. `build_single_bat`(424,823B, SHA-256 `9D541761...`), `verify_static`(6/6 PASS, Core=73/GUI=50), `smoke_test_local`(3/3 PASS, 집 PC `NetStatus=Offline` 정상 확인) 통과. **다음 재개 지점:** 직장 PC에서 `git pull` + `secrets.local.json` 1회 생성 후 빌드 → 현장 E2E 테스트(`TC-01`~`TC-22`) 수행.
* **2026-11-24 (집 PC / `b2d33f0`):** 공식 Git/GitHub CLI 연동 및 클론, 전 소스 모듈 시니어 코드 감사(P0 8건 + P1 백로그 도출), `AGENTS.md`(비판적 리뷰 권한 + 집↔직장 양방향 동기화 규칙) 및 `HANDOFF.md` 개편.
* **2026-11-24 (직장 PC / `6899c54`):** `AGENTS.md` 및 초기 `HANDOFF.md` 작성·푸시.
* **2026-11-24 (직장 PC / `f808b25`):** `v1.0.0-beta.2` 릴리스 — ZT411 TCP/IP 처리, USB 바코드 자동 재인식, `_PRTBAK\_REPORTS` 버그 리포트함 추가.
* **2026-11-24 (직장 PC / `92b6704`):** `v1.0.0-beta.1` 초기 릴리스 — WinForms 4탭 GUI + EPSON TM-T88VI LPT1 정책 + 자동 빌드/검증 스위트 구축.
