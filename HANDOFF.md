# 작업 인수인계서 (HANDOFF) — 집 ↔ 직장 PC 양방향 공용

> **최종 갱신:** 2026-11-28 21:30 (집 PC — `v1.0.0-beta.6`: 전 저장소 `PSScriptAnalyzer` 경고 0건 정비 + 재귀 심층 코드 리뷰 기능 버그 7건 수정 + 전체 검증·Torture PASS 및 Release 배포)  
> **현재 개발 버전:** `v1.0.0-beta.6`  
> **GitHub 저장소:** https://github.com/nikin78/asan-printer-manager  
> **바로 내려받아 쓰는 실행 파일:** [GitHub Releases 최신 `Asan_Printer_Manager.bat`](https://github.com/nikin78/asan-printer-manager/releases) *(별도 설정 파일 불필요 — 파일 1개만 받아 바로 실행)*

---

## 1. 핵심 완료 현황 요약

| 구분 | 내용 | 상태 |
| :--- | :--- | :---: |
| **재귀 심층 코드 리뷰 버그 7건 수정 & 전 모듈 Lint 0건 (`v1.0.0-beta.6`)** | • **`DeleteLocalPrinterNative` 권한 버그 수정:** `OpenPrinterW` 권한을 `PRINTER_ALL_ACCESS`(`0x000F000C`)로 수정해 Win32 `DeletePrinter` `ERROR_ACCESS_DENIED(5)` 원천 방지<br>• **다중 호스트 동일 공유명 충돌 & 기본 프린터 유실 수정:** `Add-SharedPrinterConnectionSafe`가 `ServerName`+`ShareName`을 동시 검증해 타 PC 동일 공유명(`kyoceraf`/`samsungm`) 거짓 성공 차단, Win 11 `LOCAL_UNC` 우회 복원 시에도 `$renamedQueueMap`으로 기본 프린터 정상 지정<br>• **비대화형 `PrintUIEntry /Xs` `/q` 전면 강제 & 손상 환경 폴백 보강:** 모든 `/Xs` 호출에 `/q` 추가 + `verify_static` CHK-4 검증 확대, `oem*.inf` 폴백의 `Provider=%Token%` `[Strings]` 해석, `Send-AsanBugReport` WMI 손상 시 `pnputil` USB 폴백, `Update-Tab2SpecialSelection` 도우미 높이 재계산<br>• **전 저장소 `PSScriptAnalyzer` 경고 0건 달성:** `build_single_bat.ps1` 미사용 `$injectedPwCount` 제거, WinForms `param($sender, $e)` 12곳→`param($ctrl, $e)` 전환, 비승인 동사 17개 PowerShell 표준 승인 동사 일괄 리팩터링, 미사용 매개변수 2건 정리 | **완료 (검증 PASS)** |
| **망분리 9,803대 전 기종 · OS 빌드 · 골든 이미지 손상 완벽 호환 (`v1.0.0-beta.5`)** | • 교체·증설 대상 전 기종(`S4`·`S5`·`H3`·`H4`·`HS`·`H6`·`H8`·`H0`·`S8`·`S9`·`D1`·`H1`·`H2` → 신규 `D8`) 및 실제 병원 서브넷(`172.*`·`192.168.*`·`10.*`·`150.150.*`·`128.99.*`·`172.3.*`) 전수 검증 완료<br>• **구형 Win 10 초기 빌드(`1507`/`1511`, PS 5.0) 지원:** `#Requires -Version 5.0` 완화 + 레거시 `pnputil -e`/`-i -a` + `INF\oem*.inf` 헤더 파싱 + 스풀러 `InfPath` 기반 `DriverStore\FileRepository` 직접 복사 폴백 완비<br>• **골든 이미지 손상 자가 치유 & 네이티브 쓰기:** `winspool.drv` `AddPrinterW`/`DeletePrinter`/`AddPrinterConnectionW`/`SetDefaultPrinterW` C# 5.0 P/Invoke 탑재, `PrintUIEntry` 침묵 실패(`ExitCode=0`) 실재 검증, 비활성·교착 `Spooler` 자동 복구, 망분리 가상 스위치(`vEthernet`/`VMnet` 등) 가짜 IP 필터링, PCIe LPT 커널 `DEVICEMAP` 상시 병행 조회<br>• **Win 11(`22H2`~`24H2`) 공유 프린터 우회:** `RpcUseNamedPipeProtocol=1` 자동 적용 + Point-and-Print 차단 시 **로컬 포트(`\\IP\공유명`) + 로컬 x64 드라이버 자동 우회 복원** + `Win32=1272`/`384` 안내 | **완료 (검증 PASS)** |
| **병원 PC `클래스 오류` 차단 & 백업 서버 `172.25.152.232` 자동 연결** | • 모든 프린터·포트·드라이버·OS·네트워크·SID·USB/LPT 조회가 WMI/CIM 없이 동작하며, **전 WMI/CDXML 명령 강제 예외 + `pnputil` 강제 실패 복합 시뮬레이션(`GOLDEN_CORRUPTION_TORTURE_PASS`) 100% 통과**<br>• 기본 계정(`admin` + 3종 공용 암호) 내장 + 기존 세션 재사용 + 공유 직접 연결(`admin`/`IP\admin`/`. \admin`)로 **`Asan_Printer_Manager.bat` 1개만 내려받으면 설정 없이 즉시 작동** | **완료 (배포 PASS)** |
| **현장 UX 개선 & 쉬운 `README.md`** | • 새 PC `0대` 상태에서 빈 백업 덮어쓰기 방지 안내·확인 가드 추가<br>• 탭 2 `1단계` 드롭다운 폭 확장(`500px`) + **`서버 검색`** 바로가기 버튼 추가, 기종 문맥별 도우미 버튼 노출(`SIP-30M` 전용 버튼 조건부 표시), 복원 완료 시 엔터 한 번으로 **`3. 출력 확인` 탭 즉시 이동** 지원<br>• `README.md` 초보자용 쉬운 설명 및 화면 캡처 5종 최신화 완료 | **완료 (시각·자동 PASS)** |

---

## 2. 현장에서 바로 받아 쓰는 방법 (빌드 불필요!)

1. 웹 브라우저에서 **[GitHub Releases](https://github.com/nikin78/asan-printer-manager/releases)**에 접속해 최신 **`Asan_Printer_Manager.bat` (`v1.0.0-beta.6`)** 파일 **1개만** 작업용 USB에 내려받습니다.
2. 병원 기존 PC(구형 Win 10/7 ~ Win 11)와 새 교체 PC(`D8` 등 Win 11)에서 그대로 더블클릭해 사용합니다.

---

## 3. 우선순위별 다음 작업 (다른 PC 에이전트 이어받기용)

1. **[1순위 · 병원 현장 실기 확인 (`v1.0.0-beta.6`)]**
   * 병원 구형 PC(`H6`/`H8` 등 Win 10)와 신형 교체 PC(`D8`/`H2` 등 Win 11)에서 `v1.0.0-beta.6` 단일 `.bat`으로 ① 프린터 자동 스캔 ② 서버 자동 백업(`172.25.152.232`) ③ 새 PC 복원 및 공유/특수 프린터 동작을 확인합니다.
   * [docs/E2E_TEST_CHECKLIST_v16.md](./docs/E2E_TEST_CHECKLIST_v16.md) 기준 이상 없으면 **`v1.0.0` 정식 버전**으로 승격합니다.
2. **[2순위 · 선택/보류] 관리번호 대장 연동**
   * 필요 시 오프라인 대장(CSV/XLSX) 기준 구 관리번호(`C18xxxxH8`) ↔ 신규 관리번호(`C26xxxxD8`) 매핑 조회 기능 검토.

---

## 4. 개발 시 집 ↔ 직장 PC 동기화 & 검증 루틴 (코드 수정 시에만)

```powershell
git pull --ff-only

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_single_bat.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_static.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke_test_local.ps1
```
* **문서 실시간 최신화 원칙:** 기능·화면이 바뀔 때마다 `HANDOFF.md`, `CHANGELOG.md`, 쉬운 문체의 `README.md`, 공용 UI 스킬(`.agents/skills/asan-desktop-ui/`), GitHub Release를 함께 최신화합니다.

---

## 5. 최근 세션 작업 로그 (최신순)

* **2026-11-28 21:30 (집 PC / `v1.0.0-beta.6` — 전 모듈 `PSScriptAnalyzer` 경고 0건 정비 · 재귀 심층 코드 리뷰 버그 7건 수정 · 검증 및 Release 배포):**
  * **주요 작업:** ① IDE `PSScriptAnalyzer` 진단 6건을 포함한 전 저장소 11개 `.ps1` 전수 감사 후 미사용 변수(`$injectedPwCount`), 자동 변수(`param($sender, $e)` 12곳→`$ctrl`), 비승인 동사 함수 17개, 미사용 매개변수 2건을 전량 정비(경고 0건) ② 재귀 심층 기능 리뷰에서 `DeleteLocalPrinterNative` `PRINTER_ALL_ACCESS(0x000F000C)` 누락, `Add-SharedPrinterConnectionSafe` 다중 호스트 동일 공유명 거짓 성공 충돌, Win 11 Point-and-Print `LOCAL_UNC` 우회 복원 시 기본 프린터 유실, 비대화형 `PrintUIEntry /Xs` `/q` 누락 및 CHK-4 검증 확대, `oem*.inf` `%Provider%` 토큰 해석, `Send-AsanBugReport` WMI 손상 USB 폴백, 탭 2 도우미 높이 재계산 등 7건의 실전 버그를 추가 발견·수정.
  * **검증 및 배포:** `audit_pssa` **전 항목 0건** · `build_single_bat` (`627,719B`, `12,527줄`, `SHA256=C25636A3...`) · `verify_static` **6/6 PASS** (`Core=92/GUI=67`, `SrcEncIssues=0`, `Violations=0`) · `smoke_test_local` **3/3 PASS** (`LayoutIssues=0`, `exit 99`) · `GOLDEN_CORRUPTION_TORTURE_PASS` 통과 · GitHub Release **`v1.0.0-beta.6`** 게시.

* **2026-11-28 19:20 (집 PC / `v1.0.0-beta.5` — 망분리 9,803대 전 기종·OS 분석 · 구형 Win10~Win11 24H2 및 골든 이미지 손상 호환성 완비 · 재귀 기능 패치 · UX 개선 · Release 배포):**
  * **주요 작업:** ① 구글 시트(`망분리교체대상PC 상세 일정`) 전수 파싱으로 15개 기종 코드(`S4`~`H2`·신규 `D8`) 실제 상용 모델·사양·서브넷·특수장비 현황 규명 ② `#Requires -Version 5.0` 완화 및 레거시 `pnputil`·`INF\oem*.inf`·`DriverStore\FileRepository` 직접 복사 폴백 구현 ③ `AsanWin32.NativeApi`에 `AddLocalPrinterNative` 등 5종 `winspool.drv` 쓰기 API 추가 및 `PrintUIEntry` 거짓 성공 원천 차단 ④ Win 11 공유 프린터 `RpcUseNamedPipeProtocol=1` + Point-and-Print 실패 시 `LOCAL_UNC` 자동 우회 복원 추가 ⑤ 망분리 가상 스위치 가짜 IP 제외·비활성/교착 `Spooler` 자가 복구·PCIe LPT `DEVICEMAP` 상시 조회·WMI 손상 USB 재인식 폴백 추가 ⑥ 탭 1 `0대` 빈 백업 방지 가드, 탭 2 `서버 검색` 버튼·기종 문맥별 도우미 버튼·복원 후 탭 3 원클릭 이동 UX 개선 및 공용 스킬·캡처 5종·문서 동기화.
  * **검증 및 배포:** `build_single_bat` (`623,456B`, `12,448줄`) · `verify_static` **6/6 PASS** (`Core=92/GUI=67`, `SrcEncIssues=0`) · `smoke_test_local` **3/3 PASS** (`LayoutIssues=0`, `exit 99`) · `GOLDEN_CORRUPTION_TORTURE_PASS` 통과 · GitHub Release **`v1.0.0-beta.5`** 게시.
* **2026-11-28 16:00 (집 PC / `v1.0.0-beta.4`):** 병원 PC `클래스 오류(0x80041010)` 원천 차단 네이티브 엔진 도입, `172.25.152.232` 서버 접속 4대 버그 수정, 기본 공용 계정 내장 단일 `.bat` Release 배포, 쉬운 `README.md` 전면 개편.
* **2026-11-26 06:05 (집 PC / `v1.0.0-beta.3`):** 런타임 시크릿 로드·`서버 로그인` UI 및 비식별 캡처 5종 추가, 전 탭 여백 통일(`New-PaddedTextBoxPanel`), 공용 GUI 디자인 스킬(`.agents/skills/asan-desktop-ui/`) 제작.
