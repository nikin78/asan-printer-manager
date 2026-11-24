# 아산병원 프린터/드라이버 통합 마이그레이션 도구 v16.0 — 개발 인수인계서 (Antigravity IDE용)

> **문서 목적:** 새로운 AI 개발 에이전트(Antigravity IDE)가 이전 대화 맥락 없이도 본 프로젝트의 기획·아키텍처·현장 예외 규칙·진행 상태를 100% 이해하고, 남은 조립·검증·테스트 단계를 즉시 이어갈 수 있도록 작성된 마스터 명세서입니다.

---

## 1. 프로젝트 개요 및 최종 목표

### 1.1 프로그램 목적
* **최종 산출물:** 단일 실행 파일 `Asan_Printer_Manager_v16.bat` (Batch 래퍼 + 내장 PowerShell 5.1 WinForms GUI 하이브리드 스크립트)
* **핵심 목표:** 서울아산병원 Windows 10 → Windows 11 PC 교체 현장 작업 시 기존 PC의 프린터 큐, 포트, 드라이버 패키지, 특수/바코드 장비 세부 설정, WIA 스캐너 드라이버를 무손실 백업·복원하고 병원 표준 인쇄 정책을 자동화합니다.

### 1.2 실행 환경 및 보안 제약
* **대상 OS:** 교체 전 `Windows 10 x64` → 교체 후 `Windows 11 x64` (24H2 이후 **Windows 보호 인쇄 모드(WPP)** 환경 포함)
* **런타임 및 의존성:** Windows 기본 내장 **Windows PowerShell 5.1** + `.NET Framework 4.x` (`System.Windows.Forms`, `System.Drawing`, `System.IO.Compression.FileSystem`) + `PrintManagement` 모듈 + OS 기본 유틸리티(`PrintBrm.exe`, `pnputil.exe`, `robocopy.exe`, `rundll32 printui.dll`, `reg.exe`). **외부 바이너리/패키지 의존성 0개.**
* **권한 요구사항:** 관리자 권한(Administrator) 필수 (미승격 실행 시 자동 UAC 승격, 32비트 WOW64 실행 시 64비트 `Sysnative` 강제 전환).
* **병원 보안망 환경:** BSone, 매체제어(SaferZone), 문서보안 DRM, Genian NAC 적용 환경이므로 **USB/네트워크 공유 폴더에 임시 파일·로그 쓰기 0바이트(Zero USB Write)**를 철저히 준수해야 합니다.

### 1.3 핵심 사용자 시나리오
1. **표준 온라인 교체 시나리오**
   * 구 Win 10 PC에서 실행 → 자동으로 **[1. 백업]** 탭 진입 및 프린터/스캐너 사전 진단 수행 → `[서버로 백업 시작]`으로 사내 백업 서버(`172.25.152.232`)에 업로드.
   * 새 Win 11 PC에서 고정 IP·DNS 설정 완료 후 실행 → 자동으로 **[2. 복원]** 탭 진입 및 현재 PC와 일치하는 백업 자동 로드 → WPP 점검 통과 후 `[선택 항목 복원 시작]` → 특수 장비 2단계 도우미 처리 → **[3. 검증/테스트]** 탭에서 SNMP/양방향 확인 및 일반 프린터 테스트 인쇄.
2. **오프라인 예외 백업 및 지연 검증 시나리오**
   * 사내망이 끊긴 구 Win 10 PC에서 실행 → 생존 검증 생략 후 `[오프라인 ZIP 백업]` 실행 → 로컬 `C:\_AsanPrtOffline\`에 단일 ZIP 생성 (원본 USB 쓰기 가능 시 `<USB루트>\_AsanPrtOffline\` 동시 복사).
   * 새 Win 11 PC(온라인)에서 **[2. 복원]** → `[오프라인 ZIP 불러오기]` 선택 → **지연 검증(Deferred Live Probe)**이 자동 실행되어 TCP/IP·공유 호스트·WSD 생존 상태를 실시간 판정 후 복원.
3. **동일 Windows Machine SID 충돌 복구 시나리오**
   * 동일 골든 이미지로 배포된 메인 PC의 공유 프린터(`\\IP\공유명`) 연결 시 인증 거부 발생 → 상단 헤더의 `Machine SID` 대조 → 메인 PC SID 조치 후 **[2. 복원]** 하단 인라인 패널에서 `[스풀러·자격증명 초기화 후 재연결]` → `[실패 항목만 재시도]`로 실패 건만 정밀 복원.

---

## 2. 핵심 기능 명세

### 2.1 Zero-USB-Write 하이브리드 부트스트랩 (`.bat`)
* 실행 즉시 자기 자신을 `%TEMP%\AsanPrinterMgr\Asan_Printer_Manager_v16.bat`으로 복사(스테이징)하여 원본 USB/공유 폴더에 쓰기 0바이트 유지.
* 32비트 프로세스(WOW64)에서 실행 시 `PROCESSOR_ARCHITEW6432`를 감지해 `%SystemRoot%\Sysnative\cmd.exe` 및 `powershell.exe`로 전환 (`System32\spool\tools\PrintBrm.exe` 누락 방지).
* UAC 승격 시 원본 경로(`ORIGINAL_SELF`)를 **URL-Safe Base64(`[A-Za-z0-9_-]`)**로 인코딩해 인자로 전달 (폴더명에 `&`, `^`, `%`, 공백이 있어도 무손실 보존).
* 파일 말미의 `##__POWERSHELL_PAYLOAD__` 마커 이후 본문을 UTF-8 BOM 임시 `.ps1`으로 추출해 `-STA` 모드(WinForms 및 `OpenFileDialog` 필수)로 실행.
* 정상 기동 시 Win32 `ShowWindow(hwnd, 0)`으로 배경 CMD 창 숨김. 정상 종료 시 `exit 99` 반환. 종료 코드가 `99`가 아니면(PS 5.1 파싱 오류·크래시 등) 즉시 WinForms 오류 `MessageBox`와 `%TEMP%\AsanPrinterMgr_Startup.log` 내용 표시 (깜빡 꺼짐 원천 차단).

### 2.2 환경·네트워크·SID·WPP 사전 진단
* **다중 NIC 및 전체 IPv4 대역 지원:** 사내 IP 대역을 `172.*`/`10.*`로 제한하지 않으며(`19*.*` 등 포함), `0.*`·`127.*`·`169.254.*`·멀티캐스트(`>=224.*`)만 제외. 다중 NIC 환경에서는 **물리 어댑터(`HardwareInterface`) + 기본 게이트웨이 보유 + 최저 `InterfaceMetric`** 순으로 사내망 NIC 선택.
* **3상태 망/서버 판정:** 사내 DNS(`10.71.1.5`:53/Ping) 및 백업 서버(`172.25.152.232`:445 SMB + 후보 공유 `\\172.25.152.232\백업 작업` / 폴백 `\\172.25.152.232\백업폴더` 하위 숨김 `_PRTBAK`)를 2초 내 판정해 `Online` / `IntranetOnly` / `Offline` 분류.
* **Machine SID 추출:** `Win32_UserAccount`에서 `LocalAccount = True AND SID LIKE '%-500'` 우선 조회하여 현재 PC의 `S-1-5-21-...` 추출.
* **Windows 보호 인쇄 모드(WPP) 사전 감지 및 차단:**
  * 로컬 토글(`HKLM\SYSTEM\CurrentControlSet\Control\Print\WindowsProtectedPrintMode`)과 그룹 정책(`HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers` 및 `\WPP`)을 구분 검사.
  * 활성화 감지 시 상단 붉은 경고 배너 자동 표시 및 복원 시작 차단.
  * 로컬 설정 해제 절차(`Win+I` / `ms-settings:printers` → `Bluetooth 및 장치` → `프린터 및 스캐너` → `Windows 보호 인쇄 모드` 끄기 → `F5`)와 GPO 해제 절차(`gpedit.msc` → `gpupdate /force` → `F5`)를 상황별 안내 팝업으로 제공.

### 2.3 프린터 분류·생존 검증·WSD 추출
* **가상 프린터 제외:** `Microsoft Print to PDF`, `Microsoft XPS Document Writer`, `Fax`, `OneNote*`, `PDF24*`, `Adobe PDF`, `Hancom PDF`, `Foxit*PDF` 등 + 가상 포트(`PORTPROMPT:`, `NUL:`, `FILE:`, `XPSPort:`, `SHRFAX:`, `PDF24`).
* **특수/라벨 프린터 4종 자동 분류:**
  1. `SIP30M_IDCARD` (진료카드 `id카드`, `SIP-30`, `HODOO`, `SISS`): Generic Network Card 특성상 생존 필터 예외(`SkipAliveFilter=$true`), PCL6 전환·일괄 테스트 인쇄 제외.
  2. `SEWOO_TE201` (네임바코드 `SLK-TE`, `LK-TE`, `Sewoo`, `USBPOS*`): **Win 11 전용 재설치 필수(`Win11ReinstallOnly=$true`)**. 복원 그리드 체크박스 잠금, `PrintBrm` 유입 시 구형 큐와 드라이버 바이너리 동시 격리 삭제.
  3. `ZD410_411` (검사/투약 바코드 `ZDesigner`, `ZD410`, `ZD411`, `Zebra`): `.dat`/`.reg` 설정 덤프, USB 포트 자동 재매핑, USB 직결 시 양방향 유지, `.drx` 용지 파일 경로 안내.
  4. `BIXOLON_TX220` (팔찌바코드 `BIXOLON`, `SLP-TX220`, `TX220`): `.dat`/`.reg` 설정 덤프, USB 직결 시 양방향 유지, Darkness/용지/센서 체크리스트 안내.
  * 서브 PC 공유 바코드(`\\IP\...`)인 경우 출력 불가 시 유지보수팀 인계 안내 태그 부착.
* **TCP/IP 생존 검증:** RAW(9100)/LPR(515)/IPP(631) 포트 확인 → 미응답 시 Ping/80/443 응답 여부로 `Ambiguous`(애매함) vs `SuspectedInactive`(비활성의심) 판별.
* **공유 호스트 Win32 네이티브 인증 & SID 충돌 판별:**
  * `net.exe` 텍스트 파싱 및 `cmdkey.exe` 외부 호출을 사용하지 않고 Win32 API(`WNetAddConnection2W`, `WNetCancelConnection2W`, `NetShareEnum` Level 1 `STYPE_PRINTQ=1`, `CredReadW`, `CredWriteW`, `CredDeleteW`) 직접 호출.
  * 기존 PC에 저장 자격 증명(`CredReadW`) 또는 비-게스트 SMB 세션이 있을 때만 기존 세션 보존(게스트 익명 열거 오탐 차단).
  * 미인증 시 `$HostName\admin` 계정으로 병원 공용 3종 비밀번호(`secrets.local.json` 빌드 주입) 무인 순차 시도. `Win32 1219`(다중 세션 충돌) 시 해당 호스트 세션 정리 후 재시도.
  * Win32 오류 `5`, `86`, `1326`, `1331`, `1909` 발생 시 `AuthOrSidConflict`로 판정. 인증 성공 시 `NetShareEnum`으로 공유 프린터명 실존 확인.
* **WSD IP·실제 모델명 추출:**
  * `WSD Port\Ports\$PortName` 레지스트리에서 `Printer UUID`/`Device UUID` 선추출.
  * 1순위: SetupAPI(`Get-PnpDevice` + `Get-PnpDeviceProperty`로 `SWD\DAFWSDProvider*`, `SWD\PRINTENUM*` 조회하여 `SYSTEM` ACL 우회) / 2순위: 레지스트리 보조 스캔.
  * **`DriverVersion`·`HardwareID`·`CompatibleIDs` 속성은 IP 추출에서 완전 제외**하여 버전 문자열(`10.0.190.1` 등)을 IP로 오인하는 사고 차단.
  * 추출된 IP의 TCP 9100/515 열림 → `TCP/IP` 전환, SMB 445 공유 프린터 존재 → `Local Port(\\IP\공유명)` 전환, 실제 모델명(`WsdModelName`) 백업.

### 2.4 스캐너 3분류 하이브리드 필터 + TWAIN 감지
* `pnputil /enum-drivers`를 언어·CP949 깨짐 내성 3중 폴백 파서(키 매칭 + ASCII 값 패턴 + 블록 고정 줄 위치)로 파싱하고 Imaging Class GUID(`{6bdd1fc6-810f-11d0-bec7-08002be2092f}`)로 필터링.
* **3분류:** ① 자동 백업(제조사 화이트리스트) / ② 자동 제외(웹캠·가상카메라 블랙리스트) / ③ 미분류 이미징 장치(탭 1 수동 체크 팝업 제공).
* `C:\Windows\twain_32` 서드파티 폴더 감지 시 영속 리포트에 네트워크 스캔 IP 바인딩 확인 경고 기록.

### 2.5 이중 백업 엔진 (`Invoke-PrinterBackupEngine`)
* `PrintBrm.exe -b`로 전체 스냅샷(`PrinterBackup.printerExport`) 생성.
* 사용 중인 서드파티 프린터 드라이버 정밀 추출: `Get-PrinterDriver`에서 `Windows x64` + 비어 있지 않은 `InfPath` 우선 매칭, Inbox 기본 INF(`ntprint.inf`, `prn*.inf` 등) 제외, 미매칭 서드파티에 한해 해당 제조사 키워드만 좁혀 `pnputil /export-driver` 추출. 선택된 WIA 스캐너 `oem*.inf` 추출.
* 특수장비 세부 설정 덤프: 로컬 특수장비(Point-and-Print 공유 제외)에 대해 `PrintUIEntry /Ss /q`(`.dat`) + `reg export PrinterDriverData`(`.reg`) 덤프.
* `PrinterBackup.json`(FormatVersion 6, `BackupNotes`, `SourceMachineSID`, `IsOfflineBackup`, `WsdModelName` 포함) 및 `Migration_Report.txt` 생성.
* 온라인 업로드 시 `_PRTBAK\<컴퓨터명>(<IP>)` 직계 하위 경로 안전 가드 검증 후 `robocopy /MIR` 실행 (기존 백업 존재 시 덮어쓰기 1회 확인). 오프라인 ZIP은 `C:\_AsanPrtOffline\<컴퓨터명>_YYYYMMDD_HHmm.zip` 생성 및 USB 쓰기 가능 시 동시 복사.

### 2.6 지연 검증 & 사후 정제 복원 엔진 (`Invoke-PrinterRestoreEngine`)
* **지연 검증(`Test-BackupDataDeferred`):** 오프라인 백업본을 온라인 새 PC에서 불러오거나 사용자가 요청 시 실시간 포트·공유·WSD 검증 수행 (`비활성의심` 및 `SEWOO_TE201` 기본 체크 해제).
* **6단계 복원 파이프라인:**
  1. 로컬 스테이징(`%TEMP%\AsanPrinterMgr\Work_Res_<PID>`) + 복원 직전 새 Win 11 골든 이미지 기존 프린터 스냅샷(`$preExistingPrinters`) 촬영.
  2. `LOCAL_UNC` 호스트 3종 인증 및 Spooler 중지 상태에서 `HKLM\...\Ports` 선등록.
  3. `PrintBrm.exe -r -o force` 선복원 (**실패 항목 정밀 재시도 `-SkipPrintBrm` 시 생략**).
  4. 사후 정제(`-SkipPrintBrm` 시 생략): 새 Win 11 골든 이미지에 원래 있던 가상 프린터는 보존하고 구 PC 유입 가상 프린터만 삭제, Win 10 세우테크 큐 + 드라이버 바이너리 동시 삭제, 미선택(원래 없던) 큐 및 WSD 원본 큐 삭제. 모든 큐 조작은 `-InputObject` 사용.
  5. **복원당 1회 INF 인덱싱 캐시 + 2패스 4단계 드라이버 해결:**
     * 불량 MS 인박스 범용(`MicrosoftInboxGenericRegex`) vs 제조사 공식 통합(`VendorUniversalRegex`: `KX DRIVER for Universal Printing` 등) 2단계 분리.
     * 모델 줄기(`Get-ModelStems`) + `x` 와일드카드 매칭(`SL-M3820ND` ↔ `M332x 382x 402x`, `PA5000dn` ↔ `PA5000x`), 복수 브랜드 가드(`Vendors`), 조건부 PCL6 우선 가중치(`PCL6 > KX > PCL5 > PS > XPS`, 특수장비 제외).
     * **Pass 1 (모델 전용 한정):** 1-A 원본 유지 → 1-B `ExportedDrivers\Printers` → 2-A Win 11 골든 스풀러 → 2-B Win 11 Driver Store(최신 패키지 우선, `Printer`+`PrintQueue` GUID) → 3 로컬 `PRT` 폴더(`스캔유틸` 제외).
     * **Pass 2 (3.5단계):** 제조사 공식 통합 드라이버 폴백.
     * **Pass 3 (4단계):** 삼성 최후 폴백(`Samsung Universal Print Driver 3`, `us003.inf`) + 테스트 페이지 오류 시 전용 교체 및 PCL6 설정 경고.
     * 거짓 성공 차단: `PrintBrm`으로 큐가 생겼더라도 호스트 인증 실패 목록에 있으면 `Warning` + 실패 목록으로 격하.
     * 특수장비 USB 포트 자동 재매핑 + `.dat`(`/Sr /q`) 복원 + `.reg` 대기열 등록.
  6. **원자적 아산 표준 정책(`Invoke-AsanStandardPolicyAtomic`):** `Stop-Service Spooler` → TCP/IP `SNMP Enabled = 0`, 프린터 `Attributes` `[uint32]` 안전 비트 마스킹(`0xFFFFF7FF`, USB 직결 특수 바코드 양방향 유지), 특수장비 `.reg` 프린터명 치환 import → `Start-Service Spooler` → WIA 스캐너 드라이버 설치 → 기본 프린터 복원.

### 2.7 특수 프린터 4종 2버튼 도우미 & SID 클라이언트 복구
* 로컬 설치 파일 재귀 탐색(`C:\Users\admin\드라이버(win10_x64)`, `win10x64`, `Desktop\admin`) + `ZD410` `.drx` 파일 탐색.
* `Complete-Sip30mPostInstall` (SIP-30M 2단계 마무리): 신규 설치된 `SISS HODOO SIP-30(Class)` 우선 선택 → TCP/IP 포트 생성 → 중복 `id카드` 정리 후 이름 `id카드` 변경 → 현재 백업 원본에서 최우선 `.dat`/`.reg` 추출·주입(이전 PC 캐시 오염 방지) → 원자적 SNMP/양방향 OFF → 인쇄 기본 설정 창(`/e`) 자동 팝업.
* `Reset-ClientSpoolerAndHostCred`: 대상 호스트 SMB 세션·Win32 자격 증명 삭제 + Spooler 중지 + `System32\spool\PRINTERS` 대기열 비우기 + Spooler 재시작 + 재인증.

---

## 3. UI/UX 및 입출력 구조

### 3.1 창 규격 및 레이아웃 원칙
* **창 크기/폰트:** `1040×720` (`MinimumSize 960×640`), `맑은 고딕`, `AutoScaleMode = Font`, `DoubleBuffered` 적용 `DataGridView`.
* **단축키:** `Alt+1`~`Alt+4` (4개 탭 전환), `F5` (환경 및 서버 새로고침).
* **반응형 배치 원칙:** 우측 고정 컨트롤에 하드코딩 X 좌표 + `Anchor=Right`를 절대 사용하지 않고, 모든 상/하단 바에 `Dock` + `New-RightFlowStrip`(`Dock=Right`, `FlowDirection=RightToLeft`)을 적용해 19인치(`1280×1024`)~27인치(`2560×1440`) 및 DPI 125%/150% 배율에서도 버튼 이탈을 방지.

### 3.2 화면 구성 (공용 상/하단 + 4개 탭)
* **상단 고정 헤더 (3행 Dock):**
  * 1행: 프로그램 타이틀 | 사내망 3상태 배지(`초록 온라인` / `주황 서버미응답` / `빨강 오프라인`) + `[새로고침(F5)]`
  * 2행: OS 명칭, `PC명(IP)`, `Machine SID` | `[SID 복사]`
  * 3행: 백업 서버 경로 또는 네트워크 안내 메시지
* **WPP 경고 배너 (WPP 활성 시에만 표시):** 붉은 배너 + `[조치 방법 안내]` + `[프린터 설정 열기]`/`[그룹 정책 열기]`
* **하단 Footer (접이식):** `ProgressBar` + 진행 상태 텍스트 + `[로그 지우기]` + `[로그 접기/펼치기]` + 다크 테마 실시간 로그창
* **탭 1 — 백업 (Win 10 / Alt+1):**
  * 진단 요약/오프라인 경고 배너, `[프린터/스캐너 다시 스캔]`, 가상 프린터 함께 보기 토글, 상태별 색상 구분 진단 그리드
  * 하단 스캐너 3분류 바(자동 백업 수, `[미분류 이미징 장치 선택]` 팝업 버튼, TWAIN 경고)
  * 액션 바: `[서버로 백업 시작]`(온라인 전용, 중복 덮어쓰기 확인) / `[오프라인 ZIP 백업]` / `[오프라인 백업 폴더 열기]`
* **탭 2 — 복원 (Win 11 / Alt+2):**
  * 서버 백업 자동매칭 드롭다운 + `[불러오기]` + `[오프라인 ZIP 불러오기]` + `[지연 검증 실행]`
  * 영속 리포트 배너(`BackupNotes` + 복원 후 삼성 `UPD 3`/실패 경고 고정 표시)
  * 선택 복원 그리드(`전체 선택`/`정상만 선택`/`선택 해제`, `SEWOO_TE201` 체크박스 `ReadOnly` 잠금)
  * 접이식 2탭 미니 도우미 패널(인증 실패 또는 특수장비 감지 시 자동 펼침):
    * Tab A: `[공유 인증 / SID 조치]` — 호스트 IP, ID, 암호, `[재인증 및 검증]`, `[스풀러·자격증명 초기화 후 재연결]`, 대조 안내
    * Tab B: `[특수 프린터 도우미]` — 감지된 특수장비 드롭다운, `[1단계: 전용 설치 실행]`, `[2단계: SIP-30M 포트/설정 마무리]`, `[폴더 열기]`, `[속성 열기]`(미설치 안내 포함), 기종별 체크리스트
  * 액션 바: `[선택 항목 복원 시작]` + `[실패 항목만 재시도]`(`-SkipPrintBrm`)
* **탭 3 — 검증/테스트 (Alt+3):**
  * `[목록 새로고침]`, `[SNMP / 양방향 일괄 수정]`, `[클라이언트 스풀러 초기화]`, 가상 프린터 토글
  * 설치 프린터 표(일반/네트워크 `SNMP=ON`·`양방향=ON` 빨강 강조, USB 특수 바코드 `ON(유지)` 정상 표시)
  * 액션 바: `[일반 프린터 전체 인쇄 (특수제외)]`(제외 목록 확인 팝업), `[선택 테스트 인쇄]`(특수장비 경고), `[프린터 속성]`, `[인쇄 기본 설정]`, `[기본 프린터 지정]`
* **탭 4 — 서버 관리 (Alt+4):**
  * 폴더명 실시간 검색, `[서버 목록 새로고침]`, `[5일 경과 일괄 정리 (N개)]`
  * 서버 백업 목록 그리드(자동매칭 초록, 5일 경과 주황), 탭 활성 시에만 조회+캐시(`PreviewCache`)하는 `Migration_Report.txt` 미리보기 창
  * 액션 바: `[선택 백업을 복원 탭으로 불러오기]`, `[탐색기로 폴더 열기]`, `[선택 백업 삭제]`
* **OS별 진입 자동화 (`Form.Shown`):**
  * Win 10: 탭 1 선택 + 프린터/스캐너 사전 진단 자동 시작
  * Win 11: 탭 2 선택 + `MatchRank <= 2`(정확/IP 매칭) 서버 백업 자동 로드

### 3.3 입출력 파일 및 경로 포맷
* **온라인 서버 백업 경로:** `\\172.25.152.232\백업 작업\_PRTBAK\<컴퓨터명>(<IP>)\` *(폴백: `백업폴더`)*
* **오프라인 백업 ZIP 경로:** `C:\_AsanPrtOffline\<컴퓨터명>_YYYYMMDD_HHmm.zip` *(원본 USB 쓰기 가능 시 `<USB루트>\_AsanPrtOffline\` 동시 복사)*
* **백업 패키지 내부 구조:**
  * `PrinterBackup.printerExport` (PrintBrm 바이너리)
  * `PrinterBackup.json` (UTF-8 BOM, FormatVersion 6, 전체 메타데이터·포트·WSD·`BackupNotes`)
  * `Migration_Report.txt` (UTF-8 BOM, 현장 가독성 리포트)
  * `ExportedDrivers\Printers\<oemN>\` 및 `ExportedDrivers\Scanners\<oemN>\`
  * `SpecialSettings\<SpecialType>_<SafeName>.dat` 및 `.reg`
* **로컬 임시 작업 경로:** `%TEMP%\AsanPrinterMgr\` (`Asan_Printer_Manager_v16.bat`, `Work_Bak_<PID>`, `Work_Res_<PID>`, `LastSpecialSettings\`), 기동 오류 로그 `%TEMP%\AsanPrinterMgr_Startup.log`.

---

## 4. 기술 스택 및 아키텍처

### 4.1 기술 스택
* **래퍼:** Windows Batch (`.bat`, `UTF-8 No BOM` + `CRLF`)
* **코어/GUI:** Windows PowerShell 5.1 + WinForms (`System.Windows.Forms`, `System.Drawing`)
* **네이티브 연동:** 인라인 C# 5.0 (`Add-Type` → `AsanWin32.NativeApi`, 1회 컴파일 후 AppDomain 공유)

### 4.2 Runspace 비동기 아키텍처
* **단일 공유 컨텍스트:** 모든 상수·정규식·캐시를 `$global:AsanCtx = [hashtable]::Synchronized(@{ ... })`로 통합 (`HostCredCache` 동기화 해시테이블 + `LogQueue` `ConcurrentQueue[psobject]`).
* **순수 코어 함수 스냅샷:** 코어 함수(Part 1, `Get-InstalledPrintersVerifyInfo` 포함) 정의 직후 GUI 함수 정의 전에 `$script:CoreFunctionNames`를 1회 캡처.
* **비동기 실행 (`Invoke-AsanAsyncTask`):** 자식 MTA Runspace에 순수 코어 함수 + `$global:AsanCtx`만 `InitialSessionState`로 주입. 백그라운드 스레드는 WinForms 컨트롤을 절대 직접 건드리지 않고 `LogQueue`에만 진행률·메시지를 push.
* **UI 폴링 및 상태 동기화:** 메인 UI의 150ms `WinForms.Timer`가 `LogQueue`를 드레인해 진행률/로그를 갱신하고, 완료 시 `$script:AsyncState.CallbackState`와 함께 완료 콜백 실행 후 중앙 함수 `Sync-AllUiButtonStates`로 전 탭 버튼 활성 상태를 일괄 재계산.

### 4.3 Antigravity IDE 권장 모듈 분리 및 빌드 구조
최종 배포물은 단일 `.bat` 파일이지만, Antigravity IDE에서는 유지보수와 자동 검증을 위해 아래처럼 소스 모듈을 분리하고 빌드 스크립트로 단일 `.bat`을 생성하는 구조를 권장합니다.

```text
asan-printer-manager-v16/
├── src/
│   ├── 00_bootstrap.bat          # Zero-USB-Write 런처 + Base64 UAC + WOW64 처리
│   ├── 01_core.ps1               # $global:AsanCtx, NativeApi(C# 5.0), 진단/백업/복원/특수장비 코어 + 스냅샷
│   ├── 02_gui_shell_tab1.ps1     # WinForms 셸, Runspace 실행기, WPP 배너/팝업, 탭 1 백업
│   ├── 03_gui_tab2.ps1           # 탭 2 복원, 지연 검증, 인라인 인증/SID 및 특수장비 4종 도우미
│   └── 04_gui_tab3_tab4_main.ps1 # 탭 3 검증/테스트, 탭 4 서버 관리, 진입점 + exit 99
├── scripts/
│   ├── build_single_bat.py       # src/ 병합 -> dist/Asan_Printer_Manager_v16.bat (UTF-8 No BOM + CRLF)
│   └── verify_static.py          # 인코딩/CRLF/마커/PS 5.1 AST/C# 5.0/함수 교차참조 자동 정적 검증
├── dist/
│   └── Asan_Printer_Manager_v16.bat
└── README.md                     # v16.0 사용자 매뉴얼 (개정 예정)
```

---

## 5. 현재까지의 진행 상황 및 미해결 이슈

### 5.1 이미 구현·검토 완료된 부분
* **전체 기획 및 아산병원 현장 예외 정책 확정 완료** (v16.0 스펙).
* **코어 엔진(Part 1) 완성 및 4차 재귀 자가 감사 완료 (Rev.5 + 3-5B 패치 `H1`, `H2` 반영):**
  * 부트스트랩, WPP 감지/가이드, Win32 네이티브 SMB/Credential/Share API, SetupAPI WSD 추출, 모델 줄기/와일드카드 2패스 드라이버 해결, 원자적 Spooler 정책, 특수장비 4종 핸들러, `-SkipPrintBrm` 재시도 분기, 순수 코어 함수 스냅샷 완료.
* **WinForms GUI 전체(Part 2 · Part 3 · Part 4) 완성 및 3-5A/3-5B 감사 패치 10건 전량 반영 완료:**
  * `C1` PS 5.1 클로저 소실 제거(`CallbackState`, `DialogResult`, `$sender.Tag`)
  * `C2` 전 영역 `Dock` + `New-RightFlowStrip` 재구성
  * `C3` 중앙 버튼 상태 동기화(`Sync-AllUiButtonStates`)
  * `C4` 공백 포함 경로 안전 탐색기 열기(`Open-FolderInExplorerSafe`)
  * `C5` 탭 1 온라인 재스캔 후 덮어쓰기 팝업 중복 차단(`-SkipOverwritePrompt`)
  * `H1`~`H5` 실패 건 정밀 재시도, 코어 스냅샷 전용 주입, 탭 4 비활성 SMB 차단+`PreviewCache`, `SEWOO_TE201` 체크 잠금+미설치 속성 안내, 호스트명 명시 반환.

### 5.2 현재 미해결 이슈 / 주의 사항
* **기존 채팅 Canvas 아티팩트 폐기 필요:** 직전 단계에서 Canvas에 생성 시도되었던 `Asan_Printer_Manager_v16.bat` 파일은 마크다운 서식으로 잘못 열리며 `__STAGED__` → `**STAGED**` 변조, 백슬래시 중복, 중간 잘림이 발생했으므로 **절대 사용하지 말고 폐기**해야 합니다. (Part 1~4 최종 확정 코드를 기반으로 `src/`에서 새로 조립해야 함.)
* **실제 통합 `.bat` 파일 생성 및 정적/동적 검증 미수행:** 4개 파트의 개별 코드는 모두 완성되었으나, 단일 `.bat` 파일로 무손실 병합(3-5C-5) 및 자동 정적 검증(3-5D)이 아직 남아 있습니다.
* **`README.md` 미갱신:** 현재 저장소의 `README.md`는 구 버전(v15.2 CLI) 기준이므로 v16.0 GUI 기준으로 전면 개정이 필요합니다.

### 5.3 남은 작업 목록 (우선순위 순)
1. **[P0 · 최우선] 모듈 파일화 및 단일 `.bat` 무손실 병합 (`3-5C-5`):**
   * 확정된 Part 1~4 코드를 `src/`에 저장하고 `build_single_bat.py`로 `dist/Asan_Printer_Manager_v16.bat`을 **UTF-8(No BOM) + 순수 CRLF**로 생성.
2. **[P0 · 최우선] 자동 정적 검증 실행 (`3-5D`):**
   * 검증 항목: ① `UTF-8 No BOM` 및 단독 `LF` 0건(순수 `CRLF`), ② `##__POWERSHELL_PAYLOAD__` 마커 단일 존재 및 추출 테스트, ③ PowerShell 5.1 실제 파서(`[System.Management.Automation.Language.Parser]::ParseInput`) 0 에러 확인, ④ PS 5.1 금지 구문(해시테이블 내 `if` 등) 0건, ⑤ C# 5.0 `Add-Type` 컴파일 테스트, ⑥ 모든 호출 함수의 정의 존재 여부 및 코어 함수 스냅샷 누락 여부 교차 검증.
3. **[P1] Windows 10 / Windows 11 실환경(또는 VM) E2E 통합 테스트:**
   * Win 10(온라인/오프라인 ZIP) 백업 → Win 11(WPP ON/OFF 경고·차단, WSD→TCP/IP·LocalPort 전환, 3종 비밀번호 무인 인증, 동일 SID 충돌 복구, 특수장비 4종 2버튼 도우미, 탭 3 일괄 수정·일반 테스트 인쇄, 탭 4 5일 정리) 전 흐름 검증.
4. **[P2] `README.md` v16.0 매뉴얼 개정:**
   * WinForms 4개 탭 사용법, 오프라인 ZIP 지연 검증 절차, WPP 해제 안내, 동일 SID 조치 절차, 특수장비 4종(ZD410·TX220·SLK-TE201·SIP-30M) 현장 체크리스트 반영.

---

## 6. 절대 준수 제약사항 (Non-Negotiable Rules)

에이전트는 아래 규칙을 **어떠한 리팩터링이나 최적화 명목으로도 임의 변경·제거해서는 안 됩니다.**

### 6.1 파일 인코딩·부트스트랩·보안 규칙
1. 최종 `.bat` 파일은 반드시 **`UTF-8 (No BOM)` + `Windows (CRLF)`**로 저장할 것. (UTF-8 BOM 포함 시 CMD 첫 줄 실패).
2. 페이로드 마커 `##__POWERSHELL_PAYLOAD__`, 임시 `.ps1`의 `UTF-8 (With BOM)` 추출, `-STA` 실행 옵션, 정상 종료 코드 **`exit 99`** 규약을 유지할 것.
3. **Zero USB Write 준수:** 원본 실행 위치(USB/공유폴더)에 임시파일·로그 생성 절대 금지. 오프라인 ZIP 백업 시 쓰기 가능 프로브 통과한 경우의 `<USB루트>\_AsanPrtOffline\` 복사만 유일한 예외.
4. WOW64 64비트 강제 전환(`Sysnative`)과 URL-Safe Base64 `ORIGINAL_SELF` 전달 로직을 제거하지 말 것.

### 6.2 PowerShell 5.1 · C# 5.0 엄격 문법 규칙
5. **PowerShell 7+ 문법 전면 금지:** 삼항 연산자(`? :`), null 병합(`??`, `??=`), 체인 연산자(`&&`, `||`), `ForEach-Object -Parallel` 사용 금지.
6. **해시테이블 리터럴(`@{ ... }`) 내부 `if` 문 절대 금지:** 모든 조건 분기는 해시테이블 바깥에서 변수에 대입 후 사용할 것.
7. **이벤트·콜백 클로저 캡처 금지:** 대화상자 버튼은 WinForms `DialogResult`와 `$sender.Tag`만 사용하며, 비동기 후속 콜백은 `$script:AsyncState.CallbackState`를 통해 전달할 것.
8. `@($null)` 1-원소 배열 함정 주의: JSON 직렬화 전 문자열 배열은 반드시 빈 값 필터링을 거칠 것.
9. 인라인 `Add-Type` C# 코드는 **C# 5.0 문법**만 사용할 것 (`$"..."` 문자열 보간, `?.`, `nameof`, 식 본문 멤버 등 금지).

### 6.3 고정 상수·경로·네트워크 규칙
10. 고정 상수 임의 변경 금지:
    * 백업 서버 IP: `172.25.152.232` / 사내 DNS: `10.71.1.5`
    * 공유 후보 경로: `\\172.25.152.232\백업 작업`, `\\172.25.152.232\백업폴더` (하위 숨김 `_PRTBAK`)
    * 기본 계정 및 3종 비밀번호: `admin` / 로컬 비추적 `secrets.local.json`에서 빌드 시 주입 (Git 평문 커밋 금지)
    * 로컬 PRT 드라이버 탐색 경로: `C:\Users\admin\드라이버(win10_x64)\PRT`, `win10x64\PRT`, `AMIS3.0장비\PRT` (`스캔유틸|ScannerFileUtility|ScanUtility` 제외)
    * 오프라인 로컬 저장 루트: `C:\_AsanPrtOffline`
    * Runspace 공유 컨텍스트 변수명: `$global:AsanCtx`
11. **사내 IPv4 대역 하드코딩 금지:** 병원 사내망은 `172.*`, `10.*` 외 `19*.*` 대역도 사용하므로 특정 사설 대역만 필터링하지 말 것.

### 6.4 현장 안전·드라이버·UI 불변 규칙
12. `net.exe` 텍스트 파싱 및 `cmdkey.exe` 외부 프로세스 호출 금지 (`AsanWin32.NativeApi` P/Invoke 유지).
13. 모든 `rundll32 printui.dll,PrintUIEntry /Ss`, `/Sr` 호출에 반드시 **`/q`** 옵션 포함 (백그라운드 스레드 Hang 방지).
14. `Remove-Printer`, `Set-Printer`, `Rename-Printer` 호출 시 `-Name` 대신 **`-InputObject`** 사용 (`[3병동]` 같은 대괄호 와일드카드 오류 방지).
15. `PrintBrm -r` 실행 전 새 Win 11 골든 이미지의 기존 프린터 스냅샷을 촬영해 원래 있던 가상 프린터를 삭제하지 말 것.
16. 레지스트리 정책(`SNMP Enabled = 0`, 양방향 `Attributes` `[uint32]` 안전 마스킹, `.reg` import)은 반드시 `Stop-Service Spooler` 상태에서 원자적으로 적용 후 재시작할 것.
17. **USB 직결 특수 바코드(`ZD410`, `TX220`, `SLK-TE201`)의 양방향 지원은 해제하지 말 것.**
18. 특수/라벨 프린터 4종은 PCL6 자동 전환 및 `[일반 프린터 전체 테스트 인쇄]`에서 반드시 제외할 것. `SEWOO_TE201`은 복원 체크 잠금 및 Win 10 구형 큐/드라이버 격리 삭제 유지.
19. `robocopy /MIR` 업로드와 서버 백업 삭제(5일 정리/단건 삭제)는 반드시 `_PRTBAK` 직계 하위 폴더 여부와 `PrinterBackup.*` 마커 존재를 검증한 뒤에만 실행할 것.
20. WinForms 우측 컨트롤은 하드코딩 X 좌표 + `Anchor=Right`를 쓰지 말고 `Dock` + `New-RightFlowStrip`을 유지하며, 비동기 작업 종료 후 반드시 `Sync-AllUiButtonStates`를 호출할 것.