# 변경 이력 (CHANGELOG)

본 프로젝트는 **시맨틱 버저닝([SemVer 2.0.0](https://semver.org/lang/ko/))** (`v주.부.수정`)을 따릅니다.
* `MAJOR(주)`: 구조 전면 개편·호환성 변경
* `MINOR(부)`: 현장 기능 추가·신규 특수 장비 지원
* `PATCH(수정)`: 버그 수정·문구/안정성 개선
* `-beta.N`: 현장 E2E 테스트 검증 전 사전 배포판

---

## [v1.0.0-beta.3] - 2026-11-25

### 보안 강화 (Security — 안 A 적용 및 현장 잔존물 차단)
* **Git 저장소 평문 암호 완전 제거 (안 A):** `src/`·`scripts/`·문서 전반에서 병원 공용 암호 평문을 제거하고, 로컬 비추적 `secrets.local.json`에서 `scripts/build_single_bat.ps1` 빌드 시점에만 주입하도록 전환(`secrets.local.example.json` 템플릿 제공, `dist/*.bat` `.gitignore` 처리).
* **교체 PC 내 백업 서버 관리자 자격증명 영구 저장 제거:** `Connect-AsanBackupServer`에서 `WriteDomainCredential`(`Persist=2`) 호출을 제거하고 세션 연결만 사용하며, 프로그램 종료(`FormClosing`) 시 `Disconnect-AllHostSessions`로 백업 서버 SMB 세션을 즉시 해제.
* **`%TEMP%` 스테이징 `.bat` 자동 삭제 및 인스턴스 분리:** `00_bootstrap.bat`이 인스턴스별 임시 스테이징 파일(`AsanMgr_Staged_*.bat`)과 로그(`AsanPrinterMgr_Startup_*.log`)를 사용하고 종료 시 자가 삭제하여 `%TEMP%` 평문 잔존 및 중복 실행 오류를 동시 해소.
* **버그 리포트 민감정보 마스킹 강화:** `HostCredCache` 세션 암호 포함 마스킹, 3글자 미만 문자열 오탐 방지(IP/JSON 훼손 차단), `TargetPrinter`/`LoadedBackupSource`/최종 텍스트·JSON 전면 마스킹 및 서버 전송 실패 사유(`FallbackNote`) 표시.

### 추가 · 개선 (Added / Changed — 약제팀 `ZT411` 골든 이미지 로컬 정책 반영)
* **약제팀 `Zebra ZT411-203dpi ZPL` 기존 PC 복원 최우선 + 골든 이미지 로컬 폴백 전환:**
  * 접근 계정 미확인 원격 서버(`\\172.23.2.130\driver`) 탐색을 완전 제거하고, 모든 골든 이미지 공통 로컬 경로(`C:\Users\admin\드라이버(win10_x64)\AMIS 3.0 장비\ZT411 (약국용 신형라벨프린터)`)의 사전 압축 해제 드라이버(`ZD8-6-5-26125\ZDesigner.inf`, `zd86526125-certified.exe`)와 용지별 설정 파일(`.drx`/`.drs`)을 자동 탐색하도록 전환(`ZD410`/`ZD411`·`PrnInst.exe` 엄격 제외).
  * 복원 시 **기존 PC 추출 드라이버(`PrintBrm`/`ExportedDrivers`) + `.dat`/`.reg` 설정을 최우선** 적용(`-PreExistingDrivers`/`-PreferExportedFirst`)하고, 부득이하게 골든 이미지 로컬 드라이버로 대체 복원되었거나 백업 설정이 미확인된 경우 요약 팝업·배너·도우미에서 **인쇄 기본 설정 마무리 필요** 경고를 자동 표시.
* **코어 모듈 5분할 유지보수 개편 (무손실, 단일 `.bat` 배포 유지):** 약 4,900줄의 `src/01_core.ps1`을 `01a_ctx_win32.ps1` / `01b_net_diag.ps1` / `01c_driver_inf.ps1` / `01d_backup_restore.ps1` / `01e_special_report_snapshot.ps1`로 비공백 코드 0줄 차이 무손실 분할하고, `verify_static.ps1`에 `src/` 미등록 파일 감지를 추가하며, `README.md`·`docs/E2E_TEST_CHECKLIST_v16.md`의 ZT411 로컬 정책 및 `%TEMP%` 자가 삭제 안내를 최신 코드와 동기화.
* **자동 검증 스위트 고도화:** `verify_static.ps1`에 `src/`·`scripts/` 인코딩/CRLF 전수 검사, `src/`↔`dist/` SHA-256 동기화, 안 A 비밀 분리, AST 기반 `Show-AsanMessageBox` 외부 직접 `MessageBox::Show` 0건 검증, 탭 4 베어 Runspace(`$previewScript`) 사용자 함수 호출 금지 검사 추가; `smoke_test_local.ps1`에 다국어 INF·`Provider=%Token%` 간접 참조 해석·5일 정리 NTFS 타임스탬프·TM-T88 포트 분기·ZT411 골든 이미지 정책·`@($null)` 고스트 행·플레이스홀더 호환 동적 마스킹 단위테스트 확장.

### 버그 수정 (Fixed — P0/P1 전면 패치 및 재귀 코드 리뷰 Round 1~3 완료)
* **재귀 코드 리뷰 Round 1~3 전량 반영 (`[FIX-NOW]` 0건):**
  * `00_bootstrap.bat`: `"%%SELF%%"`·`"%CMD_EXE%"` 인용 정규화, `ASAN_PARENT_CLEANUP` 이중 삭제 방지, 오류 시 `pause` 후 자가 삭제.
  * `01_core.ps1`: `Connect-SharedHostSmart` 중복 가드 제거, `Invoke-PrinterBackupEngine` 원자적 교체 실패 시 `_OLD_` 기존 백업 유실 차단(target 부재 시 롤백 1회 시도 + `$swapped -and (Test-Path target)`일 때만 `_OLD_` 삭제 + 최초 백업 `robocopy /MIR` 폴백), `Resolve-WsdPrinterInfo` 전역 3단계(UUID→완전일치→부분일치) 및 `UMB\UMB` 누락 수정, `Build-InfIndexCache` `Provider=%Token%` 간접 참조 해석, Case A `$isSharedConnection` 판정 상단 이동 및 MS 범용 드라이버 교체 가드 추가.
  * GUI(`02`~`04`): `Show-AsanMessageBox` 전면 전환, `PollTimer` 외곽 `catch` UI 영구 잠금 해소 및 `FormClosing` 확인 팝업 중 재진입 차단, 탭 2 `BtnSpecInstall`/`BtnSpecProps` `-RegisterBusy` 및 중앙 상태 동기화, 탭 4 비동기 미리보기 `Ok` 캐싱 가드·예외 UI 복구·`RetiredPreviews` 비차단 `Dispose`·검색 150ms 디바운스·탭 이탈/`FormClosing` 선중단.
* **USB 바코드 자동 재인식 오탐 및 `SEWOO_TE201` 격리 우회 수정:** 정상 `USB 인쇄 지원`(`PNPClass=USB`) 및 범용 `VID_0525` 오제거를 차단하고 실제 오류/미지정 상태의 검증된 바코드 VID(`0A5F`, `1504`)만 표적 재인식; 백업 시 `SEWOO_TE201` INF 추출을 제외하고 복원 5단계 USB 선등록도 해당 제조사 INF만 선별 적용; 신규 포트 생성/오류 해제로 성공 판정 정확화.
* **복원 4·5단계 안정화:** 선설치된 Win 11 `SEWOO_TE201` 보호(`$wasPreExisting`), USB 포트 미할당 시 타 프린터 포트 중복 매핑 금지 및 Case A 실패 기록(`[실패 항목만 재시도]` 정상 활성화), 오프라인 공유 호스트 거짓 성공 차단, Spooler 중지/재시작 `try/finally` 및 상태 대기(`Stop-SpoolerSafe`), INF 인덱스 `DriverStore`/`LocalPrt` 지연(Lazy) 구축.
* **네트워크 외부망 오판 수정:** `Test-AsanNetworkAndServer`가 일반 게이트웨이 Ping만으로 `IntranetOnly`를 반환하던 버그 수정(사내 DNS `10.71.1.5` 응답 또는 NIC DNS 설정 검증).
* **5일 경과 정리 데이터 유실 버그 수정:** NTFS 디렉터리 타임스탬프 대신 `PrinterBackup.json`/`PrinterBackup.printerExport` 최신 수정 시각(`Get-BackupEffectiveWriteTime`)과 비반올림 일수 기준으로 통일.
* **`EPSON_TMT88_LPT` 포트 분기 및 `LPT2`/`LPT3` 안내:** `LPT` 포트일 때만 무드라이버 격리 적용(USB/네트워크 TM-T88 보호) 및 `LPT1` 미감지 시 타 LPT 포트(`LPT2`/`LPT3`) 번호 변경 안내 표시.
* **다국어 INF 파싱 & `PrintUIEntry` / `.reg` / USB 복사 오류 감지 수정:** `Get-InfDisplayNames` 영문/한글 `[Strings]` 우선순위 적용 + `pnputil` `3010` 성공 허용, `PrintUIEntry /Ss` 실제 파일 생성/크기 기반 판정, `.reg` 치환 실패 시 잘못된 원본 키 import 차단, 오프라인 ZIP USB 복사 실존/크기 검증.
* **기타 P1 안정화:** `DeleteDomainCredential`에 `Domain:target=` 삭제 추가, WSD UUID 우선 매칭, `@($null)` 고스트 행/배너 방어, 버그 리포트 메모 `AcceptsReturn=$true`, 복원 중 `RestoreRows` 스냅샷 복사, DPI 125~150% 대응 `FlowLayoutPanel` 전환, 탭 4 단건 삭제 `_` 시스템 폴더 가드, `FormClosing` 비동기 강제 중단 데드락 방지.

---

## [v1.0.0-beta.2] - 2026-11-24

### 추가 (Added)
* **버그/오류 리포트함 (`_PRTBAK\_REPORTS`) 기능:**
  * 상단 헤더에 **`[오류/버그 리포트]`** 버튼 상시 배치 및 백업/복원 실패 시 원클릭 리포트 전송 제안 연동.
  * 앱 버전·OS·IP·`Machine SID`·WPP·망 상태·설치 프린터/TCP 포트/장치관리자 `LPT`·`USB` 바코드 장치·실시간 로그를 자동 수집하여 `_PRTBAK\_REPORTS\<일시>_<PC>_<IP>\`에 `BugReport_Summary.txt` + `BugReport_Detail.json`으로 저장(오프라인 시 `C:\_AsanPrtOffline\_Reports\` 자동 폴백).
  * 전송 전 공용 암호 3종 및 입력 비밀번호를 `[REDACTED]`로 자동 마스킹.
* **USB 바코드 프린터 소프트웨어 자동 재인식 (`Invoke-UsbBarcodeAutoReenumerate`):**
  * 새 Win 11 PC에서 `ZD410`/`BIXOLON` 등 USB 바코드 장비가 **`지정되지 않음`** 상태로 묶여 있을 때, 복원 중 추출 INF 선등록 후 `pnputil /remove-device` → `/scan-devices`로 물리적 USB 재연결 없이 프린터 승격을 자동 시도하고, 실패 시에만 1회 물리 재연결을 안내.
  * 탭 2 특수 프린터 도우미에 수동 **`[USB 재인식]`** 원클릭 버튼 추가.
* **약제팀 `Zebra ZT410/ZT411` TCP/IP 라벨 프린터 반(半)일반 자동 복원:**
  * `ZEBRA_ZT411` 전용 프로파일 추가 — TCP/IP 연결된 ZT411은 포트·드라이버·인쇄 기본 설정(`.dat`/`.reg`)을 일반 네트워크 프린터처럼 자동 복원(불필요한 수동 도우미 자동 펼침 제외), 단 안전을 위해 PCL6 전환 및 일괄 테스트 인쇄 제외는 유지.

### 개선 및 버그 수정 (Fixed / Changed)
* `_PRTBAK` 목록 조회(`Get-ServerBackupEntries`) 및 5일 경과 정리(`Remove-OldServerBackups`)에서 `_` 접두어 시스템 폴더(`_REPORTS` 등)와 마커 없는 폴더를 완전 격리.
* `Import-RewrittenPrinterRegFile`의 `[regex]::Replace` `$` 치환 안전 이스케이프 보강 및 `Complete-Sip30mPostInstall` 따옴표 이스케이프 통일.
* `PrintBrm -b/-r` 및 `PrintUIEntry /Ss·/Sr` 비정상 종료 시 경고 로그/노트 기록으로 현장 진단 가시성 강화.

---

## [v1.0.0-beta.1] - 2026-11-24

> 초기 내부 CLI 프로토타입(v1~v15.2)을 WinForms GUI 4탭 구조로 전면 재설계한 첫 공식 베타 배포판입니다. *(내부 설계 기준: v16.0 마스터 명세서)*

### 주요 기능 (Added)
* **단일 실행 파일 배포 (`dist/Asan_Printer_Manager.bat`):** 외부 의존성(Python 등) 0개, Zero-USB-Write `%TEMP%` 자가 스테이징, WOW64 64비트(`Sysnative`) 강제 전환, URL-Safe Base64 UAC 승격, 비정상 종료(`RC != 99`) GUI 오류 팝업 가드.
* **WinForms 4탭 비동기 GUI:** `1. 백업 (Win 10)` · `2. 복원 (Win 11)` · `3. 검증/테스트` · `4. 서버 관리` + OS별 자동 진입, `Alt+1~4`/`F5` 단축키, DPI/해상도 반응형 `Dock + New-RightFlowStrip` 레이아웃, MTA 자식 Runspace 비동기 실행.
* **환경·보안·네트워크 사전 진단:** Windows 11 보호 인쇄 모드(WPP 로컬/GPO) 감지·복원 차단·해제 안내, 전체 IPv4 대역·다중 NIC 우선순위 선택, `Machine SID` 추출, 3상태 망/서버 판정(`Online`/`IntranetOnly`/`Offline`).
* **정밀 백업 · 지연 검증 · 6단계 복원:**
  * 가상 프린터 자동 제외, TCP/IP·공유 3종 암호 무인 인증(`AsanWin32.NativeApi` P/Invoke)·SetupAPI 기반 WSD IP/모델명 추출.
  * WIA 스캐너 3분류 + `twain_32` 감지.
  * 온라인 서버(`_PRTBAK` 안전 가드 `robocopy /MIR`) + 오프라인 ZIP(`C:\_AsanPrtOffline` & 쓰기 가능 USB 동시 복사) → 온라인 새 PC 자동 지연 검증.
  * 골든 가상 프린터 보존 사후 정제, 모델 줄기/와일드카드 2패스 드라이버 해결(+ 삼성 UPD 3 최후 폴백 경고), Spooler 중지 상태 원자적 SNMP/양방향/`.reg` 적용, `-SkipPrintBrm` 실패 항목 정밀 재시도.
* **특수/라벨 프린터 현장 대응:**
  * `SIP-30M` 진료카드 2단계 반자동 마무리, `Sewoo SLK-TE201` Win 11 전용 설치(체크 잠금·구형 격리), `Zebra ZD410/411` & `BIXOLON SLP-TX220` USB 직결 양방향 유지 및 체크리스트.
  * **`EPSON TM-T88VI` (LPT1 무드라이버 유선 직결):** 드라이버/설정 백업·복원 완전 제외 및 `PrintBrm` 유입 시 자동 격리 삭제, 장치관리자 `LPT1` 포트 인식 상태 자동 조회·안내(`Get-DeviceManagerLptPorts`).
* **자동 빌드 및 검증 체계 (`scripts/`):** `build_single_bat.ps1`, `verify_static.ps1`(6대 자동 정적 검증), `smoke_test_local.ps1`(비파괴 로컬 GUI 스모크 테스트).

### 검증 상태
* 6대 자동 정적 검증 (`verify_static.ps1`): **ALL 6/6 PASS**
* 비파괴 로컬 스모크 테스트 (`smoke_test_local.ps1`): **ALL 3/3 PASS**
* Win 10 ↔ Win 11 현장 E2E 통합 테스트 (`docs/E2E_TEST_CHECKLIST_v16.md`): **예정 (통과 후 `v1.0.0` 정식 릴리스 전환)**
