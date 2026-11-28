# Asan Printer Manager — Antigravity Workspace Rules

이 파일은 Antigravity IDE가 본 저장소를 열 때 **자동으로 로드하는 프로젝트 규칙(Always-On Rule)**입니다.  
작업 전 현재 진행 상태와 남은 작업 목록은 루트의 `HANDOFF.md`를 먼저 읽고 이어가세요.

---

## 1. 협업 방식 (바이브 코딩 & 시니어 엔지니어 원칙)

* 사용자는 코드를 직접 작성하지 않고 지시·검토하는 **바이브 코딩 방식**으로 진행합니다.
* **적극적 반박·설득 권한(무제한):** 에이전트는 전문 시니어 개발자로서 사용자의 의견·요구사항·기존 설계에 맹목적으로 동의하지 않습니다. 보안·안정성·현장 운영 리스크나 더 나은 아키텍처가 보이면 **구체적 근거(코드·현장 시나리오·리스크)와 현실적인 대안**을 들어 적극적으로 반박하고 수용하도록 설득하세요.
* **모든 응답은 간결하고 명확한 한국어**로 작성하고, 비개발자도 이해할 수 있는 확인/테스트 방법을 함께 안내하세요.
* 큰 변경은 테스트 가능한 **작은 단위**로 나누어 진행하고, 코드를 수정한 뒤에는 **반드시 직접 빌드·정적 검증·스모크 테스트를 실행해 통과를 확인**한 뒤 보고하세요.
* 아래 3절의 **절대 준수 제약사항**은 임의로 변경·제거하지 마세요. *(단, 명백한 보안·운영 결함이 발견되면 3절 수정 자체를 사용자에게 근거와 함께 제안하고 명시적 승인을 받은 뒤 개정하세요.)*

---

## 2. 프로젝트 구조 및 단일 진실 원천

* **최종 배포물:** `dist/Asan_Printer_Manager.bat` (단일 실행 파일, 외부 의존성 0개 — Python 등 미사용, `.gitignore` 처리 + **GitHub Releases에 즉시 실행 가능한 완성본 `.bat` 배포**)
* **기본 공용 계정 내장:** 현장 작업 편의성을 위해 병원 내 공용 계정(`admin` + 공용 암호 3종)은 `src/01a_ctx_win32.ps1`에 기본 내장되어 별도 설정 파일 없이 단일 `.bat`만으로 즉시 작동합니다. *(서버 암호 변경 시에는 상단 `서버 로그인` UI 또는 선택적 `secrets.local.json`으로 대응합니다.)*
* **버전 기준:** `VERSION` 파일 (현재 SemVer `1.0.0-beta.5`, `src/01a_ctx_win32.ps1`의 `$global:AsanCtx.AppVersion`과 항상 동기화)
* **소스 모듈 (`src/` — 9개 모듈):**
  * `00_bootstrap.bat` — Zero-USB-Write `%TEMP%` 스테이징, WOW64 `Sysnative`, URL-Safe Base64 UAC, `-STA`, `RC == 99` 가드 (`UTF-8 No BOM` + `CRLF`)
  * `01a_ctx_win32.ps1` — `$global:AsanCtx` 전역 컨텍스트, C# 5.0 `AsanWin32.NativeApi`, `Hide-ConsoleWindowSafe` (`UTF-8 With BOM` + `CRLF`)
  * `01b_net_diag.ps1` — WPP 감지, 네트워크/SID/SMB, 특수장비 분류·LPT·USB 재인식, 공유 3종 인증, TCP/IP·WSD·스캐너 진단 (`UTF-8 With BOM` + `CRLF`)
  * `01c_driver_inf.ps1` — 모델 줄기/와일드카드, 다국어 INF 파싱/인덱싱, 2패스 드라이버 해결, 정밀 `oem*.inf` 추출 (`UTF-8 With BOM` + `CRLF`)
  * `01d_backup_restore.ps1` — 온라인/오프라인 ZIP 백업 엔진, 지연 검증, 6단계 복원 및 원자적 정책 엔진 (`UTF-8 With BOM` + `CRLF`)
  * `01e_special_report_snapshot.ps1` — 특수장비 핸들러, SID 복구, 서버 관리 헬퍼, 버그 리포트, 검증 조회 + `$script:CoreFunctionNames` 스냅샷 (`UTF-8 With BOM` + `CRLF`)
  * `02_gui_shell_tab1.ps1` — WinForms 셸, Runspace 실행기, WPP 배너, 버그 리포트 팝업, 탭 1 백업 (`UTF-8 With BOM` + `CRLF`)
  * `03_gui_tab2.ps1` — 탭 2 복원, 지연 검증, 공유/SID 도우미, 특수장비·USB 재인식 도우미 (`UTF-8 With BOM` + `CRLF`)
  * `04_gui_tab3_tab4_main.ps1` — 탭 3 검증/테스트, 탭 4 서버 관리, 메인 진입점 + `exit 99` (`UTF-8 With BOM` + `CRLF`)
* **빌드/검증 스크립트 (`scripts/` — Windows PowerShell 5.1 네이티브, `UTF-8 With BOM` + `CRLF`):**
  * `build_single_bat.ps1` — `src/` 9개 모듈을 순수 `CRLF` · `UTF-8 No BOM`으로 `dist/Asan_Printer_Manager.bat` 생성
  * `verify_static.ps1` — 6대 자동 정적 검증 (인코딩/CRLF, 마커·추출, PS 5.1 AST 파서, 제약 스캔, C# 5.0 `Add-Type`, 함수 교차참조 & 자식 Runspace 실주입)
  * `smoke_test_local.ps1` — 비파괴 로컬 스모크 테스트 (Zero-USB-Write 추출, 코어 진단·단위테스트, 실제 `-STA` WinForms GUI 4탭 순회 & `1040×720`/`960×640` 레이아웃 감사 & `exit 99`)
* **문서 (`docs/` & 루트) 및 공용 UI 스킬 (`.agents/skills/`):** `HANDOFF.md`(최신 인계서), `CHANGELOG.md`, `README.md`, `docs/antigravity_ide_v16_0.md`(초기 마스터 명세), `docs/E2E_TEST_CHECKLIST_v16.md`, `.agents/skills/asan-desktop-ui/SKILL.md`(타 아산병원 툴 공용 GUI 디자인 시스템 스킬 + `references/winforms_ps51_patterns.md`)

---

## 3. 절대 준수 제약사항 (Non-Negotiable Rules)

1. **인코딩·줄바꿈:** 최종 `dist/Asan_Printer_Manager.bat`과 `src/00_bootstrap.bat`은 반드시 **`UTF-8 (No BOM)` + 순수 Windows `CRLF`**. 반대로 `src/*.ps1` 및 `scripts/*.ps1`은 한국어 Windows PS 5.1 호환을 위해 반드시 **`UTF-8 (With BOM)` + 순수 `CRLF`** 유지.
2. **부트스트랩 규약:** `##__POWERSHELL_PAYLOAD__` 단일 마커, 임시 `.ps1`의 `UTF-8 (With BOM)` 추출, `-STA` 실행, 정상 종료 코드 **`exit 99`**, WOW64 `Sysnative` 강제 전환, URL-Safe Base64 `ORIGINAL_SELF` 전달 유지.
3. **Zero USB Write:** 원본 실행 위치(USB/공유폴더)에 임시파일·로그 쓰기 0바이트 엄수. *(오프라인 ZIP 시 쓰기 프로브 통과한 `<USB루트>\_AsanPrtOffline\` 복사만 예외)*
4. **PowerShell 5.1 & C# 5.0 엄격 문법:**
   * PS 7+ 문법 전면 금지 (`? :`, `??`, `??=`, `&&`, `||`, `ForEach-Object -Parallel`).
   * **해시테이블 리터럴(`@{ ... }`) 내부 `if` 문 절대 금지.**
   * WinForms 대화상자·비동기 콜백에서 로컬 변수 클로저 캡처 금지 (`DialogResult`, `$sender.Tag`, `$script:AsyncState.CallbackState`만 사용).
   * JSON 직렬화 전 문자열 배열 빈 값/`$null` 필터링.
   * 인라인 `Add-Type` C# 코드는 **C# 5.0**만 사용 (`$"..."`, `?.`, `nameof`, 식 본문 멤버 금지).
5. **Runspace 격리 규칙:** 비동기 `$work = { ... }` 블록에서 호출하는 모든 내부 함수는 반드시 코어 모듈(`src/01a_ctx_win32.ps1`~`01e_special_report_snapshot.ps1`) 중 `src/01e_special_report_snapshot.ps1`의 `$script:CoreFunctionNames` 스냅샷 **이전**에 정의하고 `Verb-Noun` 형식(`^[A-Za-z]+-[A-Za-z0-9]+$`)을 지킬 것.
6. **고정 상수 임의 변경 금지:** 백업 서버 `172.25.152.232`, 사내 DNS `10.71.1.5`, 공유 후보 `\\172.25.152.232\백업 작업` / `백업폴더`(하위 `_PRTBAK`), 기본 계정 `admin` + 공용 암호 3종(`src/01a_ctx_win32.ps1` 기본 내장), 로컬 PRT 경로(`스캔유틸|ScannerFileUtility|ScanUtility` 제외), `C:\_AsanPrtOffline`, `$global:AsanCtx`.
7. **IPv4 대역 하드코딩 금지:** 병원망은 `172.*`, `10.*` 외 `19*.*`도 사용하므로 특정 사설 대역만 허용하지 말 것.
8. **현장 안전 규칙:**
   * `net.exe` 파싱 및 `cmdkey.exe` 호출 금지 (`AsanWin32.NativeApi` P/Invoke 유지).
   * 모든 `PrintUIEntry /Ss`, `/Sr` 호출에 반드시 **`/q`** 포함.
   * `Remove-Printer`, `Set-Printer`, `Rename-Printer`는 반드시 **`-InputObject`** 사용 (`-Name` 금지).
   * `PrintBrm -r` 전 Win 11 골든 이미지 기존 프린터 스냅샷 보존.
   * 레지스트리 정책(`SNMP Enabled = 0`, `Attributes` `[uint32]` `0xFFFFF7FF` 마스킹, `.reg` import)은 `Stop-Service Spooler` 상태에서 원자적 적용 후 재시작.
   * **USB 직결 특수 바코드(`ZD410`, `TX220`, `SLK-TE201`)의 양방향 지원은 해제 금지.**
   * 특수/라벨 프린터(`SIP-30M`, `SLK-TE201`, `ZD410/411`, `ZT410/411`, `TX220`, `TM-T88`)는 PCL6 자동 전환 및 일괄 테스트 인쇄 제외 유지.
   * `SEWOO_TE201`: 복원 체크 잠금 + Win 10 구형 큐/드라이버 격리 삭제.
   * `EPSON_TMT88_LPT` (`TM-T88VI` 등): 드라이버 설치 금지·백업/복원 완전 제외 + `PrintBrm` 유입 시 자동 격리 삭제 + 장치관리자 `LPT1` 인식 여부만 확인.
   * `_PRTBAK` 업로드/삭제 시 직계 하위 폴더 & `PrinterBackup.*` 마커 검증 필수, `_` 접두어 시스템 폴더(`_REPORTS`, `_DB` 등)는 백업 목록 및 5일 정리 대상에서 영구 제외.
   * 버그 리포트 전송 시 비밀번호 문자열은 반드시 `[REDACTED]` 마스킹.
   * WinForms 우측 컨트롤에 `Anchor=Right` 하드코딩 금지 (`Dock` + `New-RightFlowStrip` + `Sync-AllUiButtonStates` 유지).

---

## 4. 코드 수정 후 필수 검증 · 배포 루틴

코드를 수정할 때마다 `scripts/`에서 아래 3단계를 반드시 순서대로 실행해 모두 PASS를 확인하세요.  
*(참고: 개인 PC 등 사내망 외부에서도 3개 스크립트 모두 오프라인 상태로 정상 통과합니다.)*

```powershell
# (선택) .ps1 파일 UTF-8 BOM + CRLF 보정 후 실행
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_single_bat.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_static.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke_test_local.ps1
```

릴리스 버전을 올릴 때는 `VERSION`, `src/01a_ctx_win32.ps1`(`AppVersion`), `CHANGELOG.md`, `README.md`(쉬운 사용자 문체 유지)를 함께 갱신한 뒤 위 3단계 검증을 통과시키고 `git push` 및 **GitHub Releases(`gh release create`)에 최신 `dist/Asan_Printer_Manager.bat`을 등록**합니다.

---

## 5. 집 ↔ 직장 PC 양방향 인수인계 · Git 동기화 규칙

본 프로젝트는 **집(개인 PC)**과 **직장(병원 PC)**을 오가며 Antigravity IDE로 이어 작업합니다. 어느 PC에서 열어도 맥락이 끊기지 않도록 아래 루틴을 반드시 지키세요.

1. **워크스페이스 기준:** Antigravity IDE는 반드시 저장소 루트(`asan-printer-manager`)를 워크스페이스로 직접 열어야 이 파일(`AGENTS.md`)이 자동 로드됩니다.
2. **작업 시작 시 (필수):**
   * `git status` 및 `git pull --ff-only`로 원격 최신 커밋을 먼저 동기화합니다.
   * 루트의 `HANDOFF.md`(특히 **최신 세션 로그** · **감사/이슈 백로그** · **우선순위별 다음 작업**)를 먼저 읽고 작업 재개 지점을 확인합니다.
3. **작업 종료 · 커밋 전 (필수):**
   * 코드 변경이 있다면 4절의 3단계 검증(`build_single_bat.ps1` → `verify_static.ps1` → `smoke_test_local.ps1`)을 모두 통과시킵니다.
   * **GUI 디자인·여백·UX 기조를 변경한 경우**, `.agents/skills/asan-desktop-ui/`(및 본 PC 전역 사본 `$env:USERPROFILE\.gemini\config\skills\asan-desktop-ui`)도 함께 최신화해 타 아산병원 툴과의 디자인 통일성을 유지합니다.
   * 커밋 전 반드시 **`HANDOFF.md`를 최신화**합니다(완료 현황, 새로 발견·해결한 이슈, 의사결정 보류 항목, 다음 PC에서 바로 이어할 1순위 작업, **세션별 작업 로그** 최상단 1줄 추가).
   * 코드와 `HANDOFF.md`(필요 시 `AGENTS.md`)를 함께 커밋하고 `git push origin main`까지 완료한 뒤 종료 보고합니다.
   * *(중요)* 민감정보·임시파일(`*.log`, `*.tmp`, `_AsanPrtOffline/`)은 절대 커밋하지 않습니다.
