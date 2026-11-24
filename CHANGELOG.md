# 변경 이력 (CHANGELOG)

본 프로젝트는 **시맨틱 버저닝([SemVer 2.0.0](https://semver.org/lang/ko/))** (`v주.부.수정`)을 따릅니다.
* `MAJOR(주)`: 구조 전면 개편·호환성 변경
* `MINOR(부)`: 현장 기능 추가·신규 특수 장비 지원
* `PATCH(수정)`: 버그 수정·문구/안정성 개선
* `-beta.N`: 현장 E2E 테스트 검증 전 사전 배포판

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
