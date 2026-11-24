# 작업 인수인계서 (HANDOFF) — 개인 PC 이어서 작업용

> **최종 갱신:** 2026-11-24  
> **현재 배포 버전:** `v1.0.0-beta.2` (Pre-release)  
> **GitHub 비공개 저장소:** https://github.com/nikin78/asan-printer-manager  
> **최신 릴리스:** https://github.com/nikin78/asan-printer-manager/releases/tag/v1.0.0-beta.2

---

## 1. 현재까지의 완료 현황

| 구분 | 내용 | 상태 |
| :--- | :--- | :---: |
| **기반 아키텍처 & 빌드** | 5개 모듈 분리(`src/`), `UTF-8 No BOM + CRLF` 단일 `.bat` 빌드(`scripts/build_single_bat.ps1`), 6대 자동 정적 검증(`scripts/verify_static.ps1`), 비파괴 로컬 GUI 스모크 테스트(`scripts/smoke_test_local.ps1`) | **완료 (ALL PASS)** |
| **버전 관리 & GitHub** | SemVer(`VERSION`, `CHANGELOG.md`), 통일 파일명(`dist/Asan_Printer_Manager.bat`), `.gitattributes`(CRLF 고정), 비공개 repo 생성 및 `v1.0.0-beta.1` / `v1.0.0-beta.2` 릴리스 발행 | **완료** |
| **특수장비 정책 확장** | 기존 4종(`SIP-30M`, `SLK-TE201`, `ZD410/411`, `TX220`) 외 추가 반영:<br>• **`EPSON TM-T88VI` (`EPSON_TMT88_LPT`)**: LPT1 무드라이버 직결 — 백업/복원 완전 제외, `PrintBrm` 유입 시 자동 격리 삭제, 장치관리자 `LPT1` 상태 자동 확인(`Get-DeviceManagerLptPorts`)<br>• **`Zebra ZT410/ZT411` (`ZEBRA_ZT411`)**: TCP/IP 연결 시 일반 네트워크 프린터처럼 포트·ZPL 드라이버·`.dat`/`.reg` 자동 복원(PCL6 전환/일괄 인쇄만 제외, 수동 도우미 불필요 펼침 방지)<br>• **USB 바코드 자동 재인식 (`Invoke-UsbBarcodeAutoReenumerate`)**: 복원 중 추출 INF 선등록 → `pnputil /remove-device` + `/scan-devices`로 `지정되지 않음` 자동 승격 시도 + 탭 2 **`[USB 재인식]`** 버튼 | **완료 (검증 PASS)** |
| **버그/오류 리포트함** | 상단 **`[오류/버그 리포트]`** 버튼 + 백업/복원 실패 시 원클릭 전송 제안 → 환경·프린터/포트/LPT/USB·실시간 로그(비밀번호 `[REDACTED]` 마스킹)를 `_PRTBAK\_REPORTS\<일시>_<PC>_<IP>\`로 전송 *(오프라인 시 `C:\_AsanPrtOffline\_Reports\` 폴백)* | **완료 (검증 PASS)** |
| **코드 리뷰 안정화** | `_PRTBAK` 조회/5일 정리에서 `_` 접두어 시스템 폴더(`_REPORTS` 등) 및 마커 없는 폴더 완전 격리, `.reg` `$` 치환 안전 이스케이프, `Complete-Sip30mPostInstall` 따옴표 이스케이프, `PrintBrm`/`PrintUI /Ss·/Sr` 오류 로그 기록 | **완료** |
| **문서화** | `README.md`, `CHANGELOG.md`, `docs/E2E_TEST_CHECKLIST_v16.md` (`TC-01`~`TC-22`), 자동 인식 규칙 `AGENTS.md` | **완료** |

---

## 2. 개인 PC에서 이어서 진행할 남은 작업 후보

1. **[대기 · 우선] 약제팀 `ZT411` 엑셀 파일 검토 및 세부 설정 보강**
   * 병원 PC에서 첨부가 누락됐던 **약제팀 ZT411 설정 엑셀 파일**을 개인 PC에서 에이전트에게 올려주시면, TCP/IP 포트 번호·드라이버 버전·감열/열전사·용지/여백 등 세부 조건이 현재 `ZEBRA_ZT411` 로직과 100% 일치하는지 검증 후 보강합니다.
2. **[선택 · 보류 중] 관리번호 DB 연동 (`.xlsx` 자체 파싱 갱신 + DB 날짜 표기)**
   * 4번 안건으로 일단 제외해 둔 항목입니다. 추후 필요 시 용도(조회 표시/백업 폴더명/리포트 기입)와 샘플 `.xlsx` 양식(DRM 해제 여부 포함)을 공유해 주시면 외부 의존성 없이 `.NET ZipFile + XmlDocument`로 구현 가능합니다.
3. **[현장 검증 후] `v1.0.0` 정식 릴리스 승격**
   * 추후 병원 Win 10 / Win 11 PC에서 `docs/E2E_TEST_CHECKLIST_v16.md` (`TC-01`~`TC-22`) 현장 테스트를 진행하고, 발견된 이슈를 패치한 뒤 **`v1.0.0`** 정식 릴리스로 발행합니다.
4. **[유지보수 선택] `src/01_core.ps1` 모듈 소분리**
   * 현재 `01_core.ps1`이 4,251줄이므로, 기능이 더 커지면 `01a_core_infra.ps1` / `01b_core_migration.ps1` / `01c_core_special_report.ps1` 등으로 분리해 가독성을 높일 수 있습니다. *(빌드 결과물은 단일 `dist/Asan_Printer_Manager.bat` 유지)*

---

## 3. 개인 PC에서 작업 이어가기 (초간단 3단계)

개인 PC에 **Git**과 **GitHub CLI(`gh`)**만 설치되어 있으면 아래 3단계로 바로 이어서 작업할 수 있습니다.

### 1단계: 저장소 내려받기 (최초 1회)
PowerShell을 열고 아래 명령을 순서대로 실행합니다.
```powershell
# Git / gh가 없다면 먼저 설치 (이미 있으면 생략)
winget install --id Git.Git -e --source winget
winget install --id GitHub.cli -e --source winget

# GitHub 로그인 (nikin78 계정, 브라우저 인증 1회)
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git

# 원하는 폴더로 이동 후 비공개 저장소 클론
gh repo clone nikin78/asan-printer-manager
```

### 2단계: Antigravity IDE로 폴더 열기
* Antigravity IDE에서 방금 내려받은 **`asan-printer-manager`** 폴더를 워크스페이스로 엽니다.
* 루트에 있는 **`AGENTS.md`를 Antigravity IDE가 자동으로 인식·로드**하므로, 모든 제약사항·빌드/검증 규칙·바이브 코딩 방식이 즉시 적용됩니다!

### 3단계: 첫 마디 프롬프트 예시
새 대화창을 열고 아래처럼 한 줄만 입력하시면 이전 맥락을 100% 이어받아 바로 시작합니다.
> `HANDOFF.md`를 읽고 현재 상태를 요약해 줘. 이제 약제팀 ZT411 엑셀 파일을 첨부할 테니 분석해서 반영해 줘.

---

## 4. 개인 PC 작업 시 참고 사항 (오프라인 정상 동작)

* 개인 PC는 병원 사내망 외부이므로 `172.25.152.232` / `10.71.1.5`에 접속되지 않아 프로그램 상단 배지가 **`오프라인`**으로 표시되는 것이 정상입니다.
* **`build_single_bat.ps1`**, **`verify_static.ps1`(6/6)**, **`smoke_test_local.ps1`(3/3)**은 모두 **사내망 연결이나 Python 없이 개인 Windows 10/11 PC에서도 100% 정상 실행·통과**되도록 설계되어 있습니다.
* 병원 PC로 돌아오셔서 최신 수정본을 받으실 때는 병원 PC 프로젝트 폴더에서 `git pull` 한 번만 실행하거나, GitHub Releases 페이지에서 최신 `Asan_Printer_Manager.bat`을 내려받으시면 됩니다.
