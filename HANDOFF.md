# 작업 인수인계서 (HANDOFF) — 집 ↔ 직장 PC 양방향 공용

> **최종 갱신:** 2026-11-28 16:00 (집 PC — `v1.0.0-beta.4`: 병원 PC `클래스 오류` 원천 해결 네이티브 엔진 전환 + `172.25.152.232` 서버 접속 버그 4종 수정 + 기본 계정 내장 단일 `.bat` Release 배포 + 쉬운 `README.md` 개편)  
> **현재 개발 버전:** `v1.0.0-beta.4`  
> **GitHub 저장소:** https://github.com/nikin78/asan-printer-manager  
> **바로 내려받아 쓰는 실행 파일:** [GitHub Releases 최신 `Asan_Printer_Manager.bat`](https://github.com/nikin78/asan-printer-manager/releases) *(별도 설정 파일 불필요 — 파일 1개만 받아 바로 실행)*

---

## 1. 핵심 완료 현황 요약

| 구분 | 내용 | 상태 |
| :--- | :--- | :---: |
| **병원 PC `클래스 오류` 원천 해결 (`v1.0.0-beta.4`)** | • 병원 Win 10/11 골든 이미지 PC에서 WMI/CIM 클래스(`Win32_Printer`, `Win32_TCPIPPrinterPort`, `MSFT_Printer`, `MSFT_NetAdapter`, `Win32_PnPEntity` 등) 손상으로 초기 스캔부터 멈추던 문제를 근본 해결<br>• `AsanWin32.NativeApi`(C# 5.0)에 `winspool.drv` `EnumPrintersW`/`GetDefaultPrinterW`, `netapi32.dll` `NetUserModalsGet`(Machine SID), `EnumDiskSharesEx` 추가<br>• 프린터·포트·드라이버·OS·네트워크(`.NET NetworkInterface` + 커널 라우팅 역추적)·LPT 조회를 모두 **WMI 비의존 네이티브/레지스트리 1순위**로 전환하고 복원 단계에도 `PrintUIEntry`/레지스트리 폴백 완비<br>• **모든 WMI/CDXML 명령 강제 예외(`0x80041010`) 시뮬레이션 테스트 100% 통과** | **완료 (검증 PASS)** |
| **백업 서버 `172.25.152.232` 접속 오류 4종 수정 + 기본 계정 내장** | • 네트워크 어댑터 WMI 실패 시 서버(445) 확인을 건너뛰던 게이트 제거 → 항상 직접 포트·세션 확인<br>• 기존 열린 윈도우 공유 세션 우선 재사용(`1219` 충돌 방지) + 공유 폴더 직접 연결(`백업 작업`/`백업폴더`) + 다중 계정 포맷(`admin`, `172.25.152.232\admin`, `.\admin`) + 디스크 공유 자동 탐색 적용<br>• 별도 `secrets.local.json` 생성 없이 **`Asan_Printer_Manager.bat` 단일 파일만 받아 실행하면 즉시 연결**되도록 기본 계정(`admin` + 3종 암호) 내장 (암호 변경 대비용 `서버 로그인` 버튼 유지) | **완료 (배포 PASS)** |
| **쉬운 `README.md` & 고시인성 UI/UX 완비** | • 비개발자·초보 작업자 눈높이에 맞춰 `README.md`를 쉬운 3단계 따라 하기 중심 문장으로 전면 재작성(비식별 실제 화면 캡처 5종 + 흐름도 포함)<br>• 고시인성 아산 그린·오렌지 UI, 전 탭 여백 통일(`New-PaddedTextBoxPanel`), 비활성 버튼 점선·사유 툴팁, 온·오프라인 자동 오류 리포트, 구 PC Win 10/11 공용 지원, 공용 디자인 스킬(`.agents/skills/asan-desktop-ui/`) 완비 | **완료 (시각·자동 PASS)** |
| **보안 · 특수장비 · 자동 검증 스위트** | • 종료 시 서버 SMB 세션 즉시 해제, 오류 리포트 암호 `[REDACTED]` 마스킹, `%TEMP%` 임시 파일 자가 삭제<br>• `SIP-30M` · `Sewoo SLK-TE201` · `Zebra ZT411`(기존 복원 최우선 + 골든 로컬 폴백) · `ZD410` · `TX220` · `EPSON TM-T88VI`(LPT1 무드라이버) 현장 규칙 완비<br>• `verify_static.ps1` **6/6 PASS** (`Core=87/GUI=67`) · `smoke_test_local.ps1` **3/3 PASS** (`LayoutIssues=0`, `exit 99`) | **완료 (ALL PASS)** |

---

## 2. 현장에서 바로 받아 쓰는 방법 (빌드 불필요!)

이제 직장/병원 PC에서 따로 코드를 빌드하거나 `json` 설정 파일을 만들 필요가 없습니다.

1. 웹 브라우저에서 **[GitHub Releases](https://github.com/nikin78/asan-printer-manager/releases)**에 접속해 최신 **`Asan_Printer_Manager.bat`** 파일 **1개만** 작업용 USB에 내려받습니다. *(기존에 만들어 두셨던 `secrets.local.json` 파일은 지우셔도 됩니다.)*
2. 병원 기존 PC(Win 10/11)와 새 PC(Win 11)에서 그대로 더블클릭해 사용합니다.

---

## 3. 우선순위별 다음 작업 (다른 PC 에이전트 이어받기용)

1. **[1순위 · 병원 현장 실기 확인 (`v1.0.0-beta.4`)]**
   * 새로 배포된 `v1.0.0-beta.4`의 `Asan_Printer_Manager.bat`을 내려받아 병원 Win 10 / Win 11 PC에서 아래 2가지를 먼저 확인합니다.
     1. 이전에 막혔던 병원 PC에서 **클래스 오류 없이 프린터 목록이 즉시 뜨는지**
     2. 별도 설정 파일 없이 상단에 초록색 **`● 사내망 · 서버 연결됨`**(`172.25.152.232`)이 바로 뜨는지 *(혹시 안 뜨면 하단 `상세 로그 보기`에 찍히는 `백업 서버 인증 진단: ...` 코드만 알려주시면 즉시 핀포인트 조치 가능)*
   * 정상 확인 후 [docs/E2E_TEST_CHECKLIST_v16.md](./docs/E2E_TEST_CHECKLIST_v16.md) 실환경 백업·복원 테스트를 마치고 이상 없으면 **`v1.0.0` 정식 버전**으로 승격합니다.
2. **[2순위 · 선택/보류] 관리번호 엑셀(`.xlsx`) 연동**
   * 필요해질 때 DRM 해제 샘플 파일과 표시 위치를 정해 외부 의존성 없이 추가합니다.

---

## 4. 개발 시 집 ↔ 직장 PC 동기화 & 검증 루틴 (코드 수정 시에만)

```powershell
# 1. 작업 시작 시 최신 코드 받기
git pull --ff-only

# 2. 코드 수정 후 필수 3단계 검증 (모두 PASS 확인)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_single_bat.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_static.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke_test_local.ps1
```
* **문서 실시간 최신화 원칙:** 기능·동작·화면이 바뀔 때마다 `HANDOFF.md`뿐 아니라 **`README.md`도 비개발자가 읽기 쉬운 평이한 문장으로 함께 업데이트**하고, 새 실행 파일이 필요하면 GitHub Release도 함께 갱신합니다.
* *(IDE 주의)* Antigravity IDE에 `src/*.ps1` 탭을 열어 두면 자동 저장 시 UTF-8 BOM이 빠지거나 구버전 버퍼가 덮어쓰일 수 있으므로 커밋 전 반드시 `verify_static.ps1` CHK-1 통과와 `git diff`를 확인합니다.

---

## 5. 최근 세션 작업 로그 (최신순)

* **2026-11-28 16:00 (집 PC / `v1.0.0-beta.4` — 병원 PC 클래스 오류 원천 차단 · 서버 접속 4대 버그 수정 · 기본 계정 내장 단일 `.bat` Release 배포 · 쉬운 `README.md` 개편):**
  * **원인 규명 및 해결:**
    1. **병원 Win 10/11 `클래스 오류` 해결:** 기존 코드가 프린터·포트·네트워크·SID·OS 조회를 모두 WMI/CIM(`Win32_Printer`, `Win32_TCPIPPrinterPort`, `MSFT_Printer`, `MSFT_NetAdapter` 등)에 의존해 병원 골든 이미지의 WMI 클래스 손상(`0x80041010`) 시 스캔 단계부터 중단됨 → `01a_ctx_win32.ps1`에 `winspool.drv`(`EnumInstalledPrinters`), `netapi32.dll`(`GetLocalMachineSid`, `EnumDiskSharesEx`) C# P/Invoke를 추가하고 `01b`~`03` 전 경로를 네이티브/레지스트리/`.NET NetworkInterface` 1순위 + `PrintUIEntry` 폴백으로 전환.
    2. **백업 서버 `172.25.152.232` 접속 실패 해결:** ① WMI 어댑터 실패(`NO_IP`) 시 서버 445 확인을 건너뛰던 게이트 제거 ② 기존 열린 공유 세션 우선 재사용 ③ `172.25.152.232\admin` 단일 포맷 및 `IPC$` 선행 강제를 제거하고 공유폴더 직접 연결 + `admin`/`IP\admin`/`. \admin` 다중 포맷 + 디스크 공유 자동 탐색 적용 ④ 실패 시 Win32 오류 코드 로그 기록.
    3. **단일 파일 즉시 실행 전환:** 별도 `secrets.local.json` 파일 생성 없이 `Asan_Printer_Manager.bat` 1개만 내려받아 바로 쓰도록 기본 계정(`admin` + 3종 암호) 내장(`AGENTS.md`, `build_single_bat.ps1`, `verify_static.ps1` 동기화).
    4. **문서 전면 이지라이팅 개편:** `README.md`와 `HANDOFF.md`를 초보자도 한눈에 읽을 수 있는 쉬운 문장과 Release 직접 다운로드 기준으로 전면 개편.
  * **수정 파일:** `VERSION`, `src/01a_ctx_win32.ps1`, `src/01b_net_diag.ps1`, `src/01c_driver_inf.ps1`, `src/01d_backup_restore.ps1`, `src/01e_special_report_snapshot.ps1`, `src/02_gui_shell_tab1.ps1`, `src/03_gui_tab2.ps1`, `scripts/build_single_bat.ps1`, `scripts/verify_static.ps1`, `scripts/smoke_test_local.ps1`, `AGENTS.md`, `CHANGELOG.md`, `README.md`, `HANDOFF.md`.
  * **검증 및 배포:** `build_single_bat` (`594,629B`, `11,922줄`, SHA-256 `04F15879...`) · `verify_static` **6/6 PASS** (`Core=87/GUI=67`, `SrcEncIssues=0`) · `smoke_test_local` **3/3 PASS** (`LayoutIssues=0`, `exit 99`) · 전 WMI/CDXML 강제 예외 시뮬레이션(`WMI_BROKEN_TORTURE_PASS`) 통과 · GitHub Release **`v1.0.0-beta.4`** 단일 `.bat` 게시.
* **2026-11-26 06:05 (집 PC / `v1.0.0-beta.3`):** 런타임 시크릿 로드·`서버 로그인` UI 및 `README.md` 비식별 캡처 5종 추가, 전 탭 여백 통일(`New-PaddedTextBoxPanel`), 공용 GUI 디자인 스킬(`.agents/skills/asan-desktop-ui/`) 제작.
* **2026-11-25 (집·직장 PC / `v1.0.0-beta.3`):** 코어 5분할(`01a`~`01e`), 재귀 코드 리뷰 Round 1~4 패치, 약제팀 `ZT411` 기존 복원 최우선 + 골든 이미지 로컬 폴백 확정, 고시인성 아산 그린·오렌지 UI 리뉴얼.
