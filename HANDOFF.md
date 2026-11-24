# 작업 인수인계서 (HANDOFF) — 집 ↔ 직장 PC 양방향 공용

> **최종 갱신:** 2026-11-24 (집 PC 세션)  
> **현재 배포 버전:** `v1.0.0-beta.2` (Pre-release)  
> **GitHub 비공개 저장소:** https://github.com/nikin78/asan-printer-manager  
> **최신 릴리스:** https://github.com/nikin78/asan-printer-manager/releases/tag/v1.0.0-beta.2  
> **자동 규칙 파일:** `AGENTS.md` *(Antigravity IDE가 저장소 루트 오픈 시 자동 로드)*

---

## 1. 현재까지의 완료 현황

| 구분 | 내용 | 상태 |
| :--- | :--- | :---: |
| **기반 아키텍처 & 빌드** | 5개 모듈 분리(`src/`), `UTF-8 No BOM + CRLF` 단일 `.bat` 빌드(`scripts/build_single_bat.ps1`), 6대 자동 정적 검증(`scripts/verify_static.ps1`), 비파괴 로컬 GUI 스모크 테스트(`scripts/smoke_test_local.ps1`) | **완료 (ALL PASS)** |
| **버전 관리 & GitHub** | SemVer(`VERSION`, `CHANGELOG.md`), 통일 파일명(`dist/Asan_Printer_Manager.bat`), `.gitattributes`(CRLF 고정), 비공개 repo 생성 및 `v1.0.0-beta.1` / `v1.0.0-beta.2` 릴리스 발행 | **완료** |
| **특수장비 정책 확장** | 기존 4종(`SIP-30M`, `SLK-TE201`, `ZD410/411`, `TX220`) + `EPSON TM-T88VI`(`EPSON_TMT88_LPT`) + `Zebra ZT410/411`(`ZEBRA_ZT411`) + USB 바코드 자동 재인식(`Invoke-UsbBarcodeAutoReenumerate`) | **구현 완료 (감사 이슈 발견 — 2절 참조)** |
| **버그/오류 리포트함** | 상단 `[오류/버그 리포트]` 버튼 + 실패 시 원클릭 제안 → `_PRTBAK\_REPORTS\<일시>_<PC>_<IP>\` 저장 *(오프라인 시 `C:\_AsanPrtOffline\_Reports\` 폴백)* | **구현 완료 (개선 사항 2절 참조)** |
| **집 PC 로컬 환경 연동** | 공식 Git(`2.56.1`), GitHub CLI(`gh 2.105.0`), `nikin78` 인증 연동, `c:\Users\odin\Asan\asan-printer-manager` 클론, 양방향 `AGENTS.md`/`HANDOFF.md` 체계 구축, 기준선 검증(6/6, 3/3) 통과 | **완료** |
| **전면 시니어 코드 감사** | `src/` 5개 모듈(약 8,500줄) + `scripts/` 3종 전수 감사 완료 → 현장 투입 전 필수 수정 항목(P0/P1) 도출 | **완료 (2절 참조)** |

---

## 2. 2026-11-24 정밀 코드 감사 결과 (현장 투입 전 수정 백로그)

> `verify_static`(6/6)과 `smoke_test_local`(3/3)은 모두 통과했지만, 실제 병원 Win 10 → Win 11 교체 현장에서 사고·보안 노출·오작동을 유발할 수 있는 **실제 결함**이 다수 발견되었습니다. **현장 E2E 테스트 전 `v1.0.0-beta.3`로 아래 P0 항목부터 먼저 패치하는 것을 강력히 권장합니다.**

### [P0 · 즉시 수정 필수 — 현장 장애 & 보안 리스크]
1. **`Invoke-UsbBarcodeAutoReenumerate` 오탐 및 `SEWOO_TE201` 격리 우회 (`src/01_core.ps1:932-1020, 2515-2537, 3357-3361`)**
   * `USB Printing Support` / `USB 인쇄 지원`은 정상 상태여도 `PNPClass='USB'`여서 모든 정상 USB 일반 프린터까지 `pnputil /remove-device`로 강제 제거됨. `VID_0525`(범용 Netchip)도 비프린터 장비 오제거 위험.
   * 백업 시 `SLK-TE201` Win 10 INF가 `ExportedDrivers\Printers\`에 함께 추출되고, 복원 5단계(`3358-3360`)가 전체 `$expInfs`를 `pnputil /add-driver /install`로 밀어 넣어 4단계에서 격리 삭제한 Win 10 세우 드라이버를 다시 주입함.
   * 타 USB 프린터(`USB001`)가 이미 있으면 바코드 승격 실패 시에도 `NeedsManualReplug=$false`로 거짓 성공 보고.
2. **보안 사고 위험 — 백업 서버 관리자 자격증명 영구 잔존 & `%TEMP%` 평문 `.bat` 미삭제 (`src/01_core.ps1:708, 237`, `src/00_bootstrap.bat:12, 63-67`)**
   * `Connect-AsanBackupServer`가 `172.25.152.232` `admin` 자격증명을 `Persist=2`(로컬 머신 영구 저장)로 기록하고 종료 시 삭제/연결 해제하지 않아, 교체 완료된 모든 병동 Win 11 PC에 백업 서버 관리자 접근 권한이 영구 잔존함.
   * `00_bootstrap.bat`이 종료 시 `%TEMP%\AsanPrinterMgr\Asan_Printer_Manager.bat`(병원 `admin` 공용 암호 3종 평문 포함)을 삭제하지 않고 영구 방치함.
   * *(아키텍처 논의 필요)* 개인 클라우드 GitHub 저장소에 병원 공용 암호 3종이 평문 커밋되어 있음 → 빌드 시점 로컬 설정 주입(gitignored) 방식 전환 검토 권장.
3. **복원 4·5단계 파괴적 예외 & 거짓 성공 (`src/01_core.ps1:3021-3032, 3249-3252, 3298-3311, 3390-3449`)**
   * 4단계(`3299`)가 `$wasPreExisting`을 검사하지 않아 이미 설치된 Win 11 정상 `SLK-TE201`까지 삭제함.
   * Case A에서 USB 포트 재매핑 실패 시 `else` 분기가 없어 `Success`로 보고되고 `$failures`가 비어 `[실패 항목만 재시도]` 버튼이 비활성화됨. 오프라인 공유 호스트(`HostOffline`)도 `Success`로 오판.
   * `Ensure-RestoredPortSafe`가 사용 중인 `$usbPorts[0]`에 다른 USB 프린터를 중복 매핑할 수 있음.
4. **외부망/개인 PC에서 `IntranetOnly` 오판 (`src/01_core.ps1:756`)**
   * `Test-AsanNetworkAndServer`가 기본 게이트웨이 Ping 성공만으로 `IntranetOnly`를 반환해, 병원 외부망(집 `192.168.0.2` 등)에서도 `오프라인` 대신 `사내망 연결 / 서버 미응답`으로 잘못 표시됨 *(실제 `smoke_test_local.ps1`에서 재현 확인)*.
5. **5일 경과 정리 시 오늘 재백업한 폴더 삭제 위험 + 반올림 불일치 (`src/01_core.ps1:2742, 3913-3940`)**
   * `robocopy /MIR` 덮어쓰기 시 NTFS 폴더 `LastWriteTime`이 갱신되지 않아, 6일 전 백업을 오늘 덮어써도 5일 정리 대상에 걸려 삭제될 수 있음. `PrinterBackup.json`의 `LastWriteTime` 기준으로 통일 필요.
6. **`EPSON_TMT88_LPT` 포트 미검증 (`src/01_core.ps1:867-879`)**
   * `TM-T88` 문자열만으로 무드라이버 정책을 적용해 USB/네트워크 연결 TM-T88까지 백업 제외·복원 시 강제 삭제할 위험. `LPT` 포트 여부 확인 및 `LPT2`/`LPT3` 감지 안내 보완 필요.
7. **`rundll32 PrintUIEntry` 종료코드 `0` 고정으로 오류 감지 데드코드 (`src/01_core.ps1:2548-2553, 3418-3421, 3523-3526`)**
   * `rundll32.exe`는 `PrintUIEntry /Ss·/Sr` 실패 시에도 항상 `ExitCode=0` 반환 → `.dat` 파일 미생성 시 경고 누락(`elseif` → `else`), `.reg` 치환 오류 silent fallback 수정 필요.
8. **`Get-InfDisplayNames` 다국어 `[Strings.xxxx]` 덮어쓰기 버그 (`src/01_core.ps1:1957-1966`)**
   * 다국어 OEM INF에서 마지막 언어 섹션(중국어/러시아어 등)이 영문/한글 문자열을 덮어써 `Add-PrinterDriver` 실패 유발. `pnputil` 종료코드 `3010`(재부팅 필요 성공) 처리도 누락.

### [P1 · 안정성 · UI/UX · 테스트 보강]
* **자격증명/부트스트랩/복사 검증:** `DeleteDomainCredential`에 `Domain:target=` 삭제 추가(`01_core.ps1:252`), 오프라인 ZIP USB 복사 실존 검증(`2712`), `00_bootstrap.bat` `START_LOG` 인스턴스별 분리(`%RANDOM%_%RANDOM%`), `Stop-Service Spooler` 누락된 `try/finally` 및 상태 확인 보강(`3048, 3257`).
* **`ZEBRA_ZT411` 헬퍼 누락 보완:** `Get-DetectedVendors`(`1836`), `Export-PreciseThirdPartyDrivers`(`2422`), `Find-LocalSpecialInstaller`(`3617`)에 `ZT410/ZT411` 추가.
* **버그 리포트 & WinForms UX:** 버그 리포트 메모 `$txtMemo.AcceptsReturn = $true` 추가(엔터키 조기 전송 방지), `HostCredCache` 암호 마스킹 및 `FallbackNote` 표시, 모든 `MessageBox::Show`에 `$script:Ui.Form` 오너 지정, 복원 실행 중 `RestoreRows` 스냅샷 복사(크로스 스레드 변이 차단), 탭 2/탭 3 버튼 스트립 `FlowLayoutPanel` 전환(DPI 125~150% 잘림 방지), `Resolve-WsdPrinterInfo`에서 WSD GUID 우선 매칭, `@($null)` 고스트 행 방어.
* **아키텍처 & 검증 고도화:** `verify_static.ps1`에 `src/`↔`dist/` 일치성·소스 파일 인코딩 검사 추가, `smoke_test_local.ps1`에 핵심 로직 단위테스트 확장, `Build-InfIndexCache` 지연 초기화(Lazy) 적용, `src/01_core.ps1`(4,251줄) 기능별 5개 모듈 소분리 검토.

---

## 3. 우선순위별 다음 작업 및 재개 지점

1. **[1순위 · 즉시 착수 가능 — `v1.0.0-beta.3` 안정화 패치]**
   * 2절의 **P0 치명적 버그 및 보안 결함(1~8번)** 일괄 수정 → 재빌드 및 검증(`verify_static` 6/6 + 확장 단위테스트) → `v1.0.0-beta.3` 릴리스.
   * *(사용자 의사결정 필요)* ① 병원 공용 암호 3종을 Git 소스에서 분리해 로컬 빌드 설정(gitignored)으로 뺄지 여부, ② `PrintBrm -r -o force` 선복원 전략 유지 vs 선택 큐 중심 복원 강화 방향.
2. **[2순위 · 자료 수신 시 즉시 진행] 약제팀 `ZT411` 엑셀 파일 검토 및 세부 설정 보강**
   * 약제팀 ZT411 설정 엑셀 파일을 공유받으면 포트·드라이버 버전·감열/열전사·용지/여백 등 세부 조건을 `ZEBRA_ZT411` 로직과 대조해 보강.
3. **[3순위 · 유지보수/UX] P1 항목 반영 및 `src/01_core.ps1` 소분리**
   * DPI 125~150% 레이아웃·스레드 안전성·단위테스트 확충·`01_core.ps1` 모듈 분할(단일 `dist/Asan_Printer_Manager.bat` 출력 유지).
4. **[4순위 · 보류/선택] 관리번호 DB 연동 (`.xlsx` 자체 파싱)**
   * 필요 시 용도와 DRM 해제 샘플 `.xlsx` 공유 후 `.NET ZipFile + XmlDocument`로 구현.
5. **[최종] Win 10 ↔ Win 11 현장 E2E 테스트 (`docs/E2E_TEST_CHECKLIST_v16.md`, `TC-01`~`TC-22`) → `v1.0.0` 정식 릴리스 승격**

---

## 4. 집 ↔ 직장 PC 동기화 루틴

### 매 세션 시작 시 (집/직장 공통)
```powershell
git pull --ff-only
```
* Antigravity IDE에서 반드시 **`asan-printer-manager` 폴더를 워크스페이스로 직접 열기** (`AGENTS.md` 자동 로드).
* 첫 프롬프트 예시:
  > `HANDOFF.md`를 읽고 최신 상태를 확인해 줘. 이어서 [원하는 작업] 진행하자.

### 매 세션 종료 시 (Antigravity 자동 수행 원칙)
1. 코드 변경 시 `scripts/` 3단계 검증(`build_single_bat.ps1` → `verify_static.ps1` → `smoke_test_local.ps1`) 모두 PASS 확인
2. 본 문서(`HANDOFF.md`)의 완료 현황·이슈·다음 작업·**세션 로그(6절)** 갱신
3. `git add` → `git commit` → `git push origin main`

---

## 5. 오프라인(개인 PC) 개발 환경 참고 사항

* `build_single_bat.ps1`, `verify_static.ps1`, `smoke_test_local.ps1`은 사내망 연결이나 Python 없이 일반 Windows 10/11 PC에서 100% 정상 실행됩니다.
* *(알려진 버그 — P0-4)* 현재 `v1.0.0-beta.2`에서는 개인 PC에서도 게이트웨이 Ping 응답 때문에 상단 배지가 `IntranetOnly`로 표시됩니다. P0 패치에서 `Offline`으로 정확히 판별되도록 수정 예정입니다.

---

## 6. 세션별 작업 로그 (최신순)

* **2026-11-24 (집 PC):** 공식 Git(`2.56.1`)·GitHub CLI(`gh 2.105.0`) 설치 및 `nikin78` 계정 연동 완료, `c:\Users\odin\Asan\asan-printer-manager` 클론 및 상위 빈 `.git` 제거, 기준선 검증(`verify_static` 6/6 PASS, `smoke_test_local` 3/3 PASS) 확인. 전 소스 모듈(약 8,500줄) 시니어 코드 감사 수행 → P0 8건(USB 재인식 오탐/SEWOO 격리 우회, 백업 서버 자격증명 영구 잔존 & `%TEMP%` 평문 `.bat` 미삭제, `IntranetOnly` 오판 등) 및 P1 백로그 도출. `AGENTS.md`(비판적 리뷰 권한 + 집↔직장 동기화 규칙) 및 `HANDOFF.md`(양방향 공용 + 감사 백로그 + 세션 로그) 개편. **다음 재개 지점:** P0 안정화 패치(`v1.0.0-beta.3`) 착수 여부 및 보안/아키텍처 의사결정 확인 후 수정 진행(또는 약제팀 ZT411 엑셀 파일 수신 시 동시 반영).
* **2026-11-24 (직장 PC / `6899c54`):** `AGENTS.md` 및 초기 `HANDOFF.md` 작성·푸시.
* **2026-11-24 (직장 PC / `f808b25`):** `v1.0.0-beta.2` 릴리스 — ZT411 TCP/IP 처리, USB 바코드 자동 재인식, `_PRTBAK\_REPORTS` 버그 리포트함 추가.
* **2026-11-24 (직장 PC / `92b6704`):** `v1.0.0-beta.1` 초기 릴리스 — WinForms 4탭 GUI + EPSON TM-T88VI LPT1 정책 + 자동 빌드/검증 스위트 구축.
