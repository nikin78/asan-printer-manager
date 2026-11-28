# ============================================================================
# 모델 줄기/와일드카드 매칭 + 2패스 드라이버 해결 엔진
# ============================================================================
function Format-NormalizedText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return (($Text -replace '[^\p{L}\p{Nd}]', '').ToLowerInvariant())
}

function Get-DetectedVendors {
    param([string]$Text)
    $list = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    if ($Text -match '(?i)Samsung|삼성')                                { $list.Add('SAMSUNG') }
    if ($Text -match '(?i)Kyocera|교세라|ECOSYS|TASKalfa|\bKX DRIVER\b') { $list.Add('KYOCERA') }
    if ($Text -match '(?i)Hewlett-Packard|\bHP\b|LaserJet|OfficeJet')   { $list.Add('HP') }
    if ($Text -match '(?i)Canon|캐논')                                  { $list.Add('CANON') }
    if ($Text -match '(?i)Epson|엡손')                                  { $list.Add('EPSON') }
    if ($Text -match '(?i)Brother|브라더')                              { $list.Add('BROTHER') }
    if ($Text -match '(?i)Ricoh|(?<!신도)리코|Savin|Lanier')            { $list.Add('RICOH') }
    if ($Text -match '(?i)Konica|Minolta|코니카')                       { $list.Add('KONICA') }
    if ($Text -match '(?i)Fuji(?!tsu)|Xerox|제록스')                    { $list.Add('XEROX') }
    if ($Text -match '(?i)Sindoh|신도리코')                             { $list.Add('SINDOH') }
    if ($Text -match '(?i)Zebra|ZDesigner|ZD410|ZD411|ZT410|ZT411|ZBRN') { $list.Add('ZEBRA') }
    if ($Text -match '(?i)Bixolon|빅솔론|SLP-TX|TX220|TX-220')           { $list.Add('BIXOLON') }
    if ($Text -match '(?i)Sewoo|세우|SLK-TE|LK-TE')                     { $list.Add('SEWOO') }
    if ($Text -match '(?i)SISS|HODOO|SIP-30|IDCOS')                     { $list.Add('SISS') }
    return @($list.ToArray())
}

function Get-DetectedVendor {
    param([string]$Text)
    $vs = @(Get-DetectedVendors -Text $Text)
    if ($vs.Count -gt 0) { return $vs[0] }
    return $null
}

function Get-SignificantTokens {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $stopWords = @(
        'kyocera','samsung','driver','drivers','printer','printing','model','series',
        'kx','pcl','pcl5','pcl5e','pcl5c','pcl6','pclxl','ps','postscript','xps','spl',
        'v3','v4','type3','type4','classic','package','packaged','microsoft','windows',
        'win10','win11','x64','64bit','class','universal','generic','for','sl'
    )
    $tokens = [regex]::Matches($Text.ToLowerInvariant(), '[\p{L}\p{Nd}]+') |
        ForEach-Object { $_.Value } |
        Where-Object { $_.Length -ge 3 -and $_ -notin $stopWords } |
        Select-Object -Unique
    return @($tokens)
}

function Get-ModelStems {
    param([string[]]$Tokens)
    $stems = [System.Collections.Generic.List[string]]::new()
    foreach ($t in @($Tokens)) {
        if ($t -notmatch '^[a-z0-9]+$' -or $t -notmatch '\d' -or $t -match '^\d+(?:dpi|bit)$') { continue }
        $clean = $t.ToLowerInvariant() -replace '^sl', ''
        if ($clean.Length -ge 3 -and -not $stems.Contains($clean)) { $stems.Add($clean) }

        $stripped = $clean -replace '(?<=\d)(?:idn|dwf|fdn|fdw|cdw|nd|dn|dw|nx|nf|fw|fn|cw|cn|f|d|n|w|x)$', ''
        if ($stripped.Length -ge 3 -and -not $stems.Contains($stripped)) { $stems.Add($stripped) }

        $numM = [regex]::Match($stripped, '\d{3,}')
        if ($numM.Success -and -not $stems.Contains($numM.Value)) { $stems.Add($numM.Value) }
    }
    return @($stems.ToArray())
}

function Test-WildcardModelMatch {
    param(
        [string]$CandidateDisplayName,
        [string[]]$WantedStems
    )
    if ([string]::IsNullOrWhiteSpace($CandidateDisplayName) -or -not $WantedStems -or $WantedStems.Count -eq 0) { return $false }

    $candTokens = [regex]::Matches($CandidateDisplayName.ToLowerInvariant(), '[a-z]*\d+[a-z0-9]*') | ForEach-Object { $_.Value }
    foreach ($ct in @($candTokens)) {
        if ($ct -match '^([a-z]*\d+)x+$') {
            $pat = '^' + [regex]::Escape($matches[1]) + '[0-9a-z]*$'
            foreach ($ws in $WantedStems) {
                if ($ws -match $pat) { return $true }
            }
        }
        $ctStripped = $ct -replace '(?<=\d)(?:idn|dwf|fdn|fdw|cdw|nd|dn|dw|nx|nf|fw|fn|cw|cn|f|d|n|w|x)$', ''
        if ($ctStripped.Length -ge 3) {
            foreach ($ws in $WantedStems) {
                if ($ws -eq $ctStripped) { return $true }
            }
        }
    }
    return $false
}

function Get-DriverProtocolTag {
    param([string]$DriverName)
    if ([string]::IsNullOrWhiteSpace($DriverName)) { return 'UNKNOWN' }
    if ($DriverName -match '(?i)PCL\s*6|PCL6|PCL\s*XL')  { return 'PCL6' }
    if ($DriverName -match '(?i)\bKX\b')                  { return 'KX' }
    if ($DriverName -match '(?i)PCL\s*5|PCL5')            { return 'PCL5' }
    if ($DriverName -match '(?i)\bPS\b|PostScript|KPDL')  { return 'PS' }
    if ($DriverName -match '(?i)\bXPS\b')                 { return 'XPS' }
    if ($DriverName -match '(?i)\bSPL\b')                 { return 'SPL' }
    if ($DriverName -match '(?i)\bZPL\b|\bEPL\b|\bSLCS\b') { return 'LABEL' }
    return 'OTHER'
}

function Get-ProtocolPreferenceBonus {
    param([string]$DriverName)
    $tag = Get-DriverProtocolTag -DriverName $DriverName
    switch ($tag) {
        'PCL6'  { return 180 }
        'KX'    { return 150 }
        'PCL5'  { return 80 }
        'PS'    { return 40 }
        'XPS'   { return 10 }
        default { return 0 }
    }
}

function Get-InfTextSafe {
    param([string]$InfPath)
    try {
        return (Get-Content -LiteralPath $InfPath -Raw -ErrorAction Stop)
    } catch {
        try { return [IO.File]::ReadAllText($InfPath, [Text.Encoding]::Default) } catch { return $null }
    }
}

function Get-InfDisplayNames {
    param([string]$InfText)
    if ([string]::IsNullOrWhiteSpace($InfText)) { return @() }

    $stringTable    = @{}
    $stringPriority = @{}
    $directNames    = [System.Collections.Generic.List[string]]::new()
    $tokenRefs      = [System.Collections.Generic.List[string]]::new()
    $section        = ''
    $skipDirectSec  = '(?i)^(Version|SourceDisksNames(?:\..+)?|SourceDisksFiles(?:\..+)?|DestinationDirs|ControlFlags|ClassInstall32(?:\..+)?|Manufacturer|DefaultInstall(?:\..+)?)$'

    foreach ($rawLine in ($InfText -split "`r?`n")) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith(';')) { continue }
        $secM = [regex]::Match($line, '^\s*\[([^\]]+)\]\s*(?:;.*)?$')
        if ($secM.Success) { $section = $secM.Groups[1].Value.Trim(); continue }
        if ($section -match '(?i)^strings(?:\.([0-9a-f]+))?$') {
            $langTag = ''
            if ($matches[1]) { $langTag = $matches[1].ToLowerInvariant() }
            # 우선순위: [Strings](영문 기본)=3, [Strings.0412](한국어)=2, [Strings.0409]=2, 기타 언어(중국어/러시아어 등)=1
            $prio = 1
            if ($langTag -eq '') { $prio = 3 }
            elseif ($langTag -in @('0412', '0409')) { $prio = 2 }

            $strM = [regex]::Match($line, '^\s*([^=;]+?)\s*=\s*"([^"]+)"')
            if ($strM.Success) {
                $k = $strM.Groups[1].Value.Trim().Trim('%').ToLowerInvariant()
                $v = $strM.Groups[2].Value.Trim()
                if ($k -and $v) {
                    $prevPrio = 0
                    if ($stringPriority.ContainsKey($k)) { $prevPrio = [int]$stringPriority[$k] }
                    if ($prio -ge $prevPrio) {
                        $stringTable[$k]    = $v
                        $stringPriority[$k] = $prio
                    }
                }
            }
            continue
        }
        if ($section -match $skipDirectSec) { continue }
        $dirM = [regex]::Match($line, '^\s*"([^"]+)"\s*=')
        if ($dirM.Success) {
            $v = $dirM.Groups[1].Value.Trim()
            if ($v -match '^%([^%]+)%$') {
                $qk = $matches[1].Trim().ToLowerInvariant()
                if ($qk -and -not $tokenRefs.Contains($qk)) { $tokenRefs.Add($qk) }
            } elseif ($v -and -not $directNames.Contains($v)) {
                $directNames.Add($v)
            }
        }
        $tokM = [regex]::Match($line, '^\s*%([^%]+)%\s*=')
        if ($tokM.Success) {
            $k = $tokM.Groups[1].Value.Trim().ToLowerInvariant()
            if ($k -and -not $tokenRefs.Contains($k)) { $tokenRefs.Add($k) }
        }
    }

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($n in $directNames) { if (-not $names.Contains($n)) { $names.Add($n) } }
    foreach ($k in $tokenRefs) {
        if ($stringTable.ContainsKey($k)) {
            $v = [string]$stringTable[$k]
            if ($v -and -not $names.Contains($v)) { $names.Add($v) }
        }
    }
    if ($names.Count -eq 0) {
        foreach ($v in $stringTable.Values) {
            $s = [string]$v
            if ($s.Length -ge 3 -and $s.Length -le 160 -and -not $names.Contains($s)) { $names.Add($s) }
        }
    }
    return @($names.ToArray())
}

function New-InfIndexCache {
    param([IO.FileInfo[]]$InfFiles)
    $cache = [System.Collections.Generic.List[object]]::new()
    if (-not $InfFiles -or $InfFiles.Count -eq 0) { return @() }

    foreach ($inf in $InfFiles) {
        $text = Get-InfTextSafe -InfPath $inf.FullName
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $dispNames = @(Get-InfDisplayNames -InfText $text)
        $vendorHintText = ($dispNames -join ' ') + ' ' + $inf.Name

        # [Strings] 토큰 테이블 구축 (Provider=%EP% 등 간접 참조 해석용)
        $infStrings = @{}
        $infStrPrio = @{}
        $curSec     = ''
        foreach ($rawL in ($text -split "`r?`n")) {
            $ln = $rawL.Trim()
            if (-not $ln -or $ln.StartsWith(';')) { continue }
            $sm = [regex]::Match($ln, '^\s*\[([^\]]+)\]\s*(?:;.*)?$')
            if ($sm.Success) { $curSec = $sm.Groups[1].Value.Trim(); continue }
            if ($curSec -match '(?i)^strings(?:\.([0-9a-f]+))?$') {
                $lTag = ''
                if ($matches[1]) { $lTag = $matches[1].ToLowerInvariant() }
                $pr = 1
                if ($lTag -eq '') { $pr = 3 }
                elseif ($lTag -in @('0412', '0409')) { $pr = 2 }
                $kv = [regex]::Match($ln, '^\s*([^=;]+?)\s*=\s*"([^"]+)"')
                if ($kv.Success) {
                    $sk = $kv.Groups[1].Value.Trim().Trim('%').ToLowerInvariant()
                    $sv = $kv.Groups[2].Value.Trim()
                    if ($sk -and $sv) {
                        $prevP = 0
                        if ($infStrPrio.ContainsKey($sk)) { $prevP = [int]$infStrPrio[$sk] }
                        if ($pr -ge $prevP) {
                            $infStrings[$sk] = $sv
                            $infStrPrio[$sk] = $pr
                        }
                    }
                }
            }
        }

        # 모델명 문자열에 제조사 브랜드가 생략된 INF를 위해 Provider 헤더(+ %Token% 해석) 보조 확인
        $hdrMatches = [regex]::Matches($text, '(?im)^\s*Provider\s*=\s*([^;\r\n]+)')
        foreach ($hm in $hdrMatches) {
            $pRaw = $hm.Groups[1].Value.Trim()
            $vendorHintText += ' ' + $pRaw
            foreach ($tm in [regex]::Matches($pRaw, '%([^%]+)%')) {
                $tk = $tm.Groups[1].Value.Trim().ToLowerInvariant()
                if ($infStrings.ContainsKey($tk)) {
                    $vendorHintText += ' ' + [string]$infStrings[$tk]
                }
            }
        }
        $vendors = @(Get-DetectedVendors -Text $vendorHintText)
        $cache.Add([pscustomobject]@{
            Path         = $inf.FullName
            FileName     = $inf.Name
            TextNorm     = (Format-NormalizedText $text)
            DisplayNames = $dispNames
            Vendors      = $vendors
        })
    }
    return @($cache.ToArray())
}

function Get-DriverStorePrinterInfFiles {
    $infList = [System.Collections.Generic.List[IO.FileInfo]]::new()
    $seen    = @{}
    $repoDir = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
    if (-not (Test-Path -LiteralPath $repoDir)) { return @() }

    $blocks       = @(Get-PnpUtilDriverBlocks)
    $origInfNames = [System.Collections.Generic.List[string]]::new()
    foreach ($b in $blocks) {
        if (($global:AsanCtx.PrinterClassGuids -contains $b['ClassGuid']) -and -not [string]::IsNullOrWhiteSpace([string]$b['OriginalName'])) {
            $o = ([string]$b['OriginalName']).ToLowerInvariant()
            if (-not $origInfNames.Contains($o)) { $origInfNames.Add($o) }
        }
    }

    foreach ($orig in $origInfNames) {
        $prefix = [IO.Path]::GetFileNameWithoutExtension($orig)
        $dirs   = @(Get-ChildItem -LiteralPath $repoDir -Directory -Filter "$prefix.inf_*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        foreach ($sub in $dirs) {
            if ([Environment]::Is64BitOperatingSystem -and $sub.Name -match '(?i)_(x86|arm64)_') { continue }
            $cand = Join-Path $sub.FullName $orig
            if (Test-Path -LiteralPath $cand) {
                $key = $cand.ToLowerInvariant()
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $infList.Add((Get-Item -LiteralPath $cand))
                }
            }
        }
    }
    return @($infList.ToArray())
}

function Get-LocalPrtFolderInfFiles {
    $infList = [System.Collections.Generic.List[IO.FileInfo]]::new()
    $seen    = @{}
    $roots   = [System.Collections.Generic.List[string]]::new()
    foreach ($r in @($global:AsanCtx.DriverRoots)) { $roots.Add([string]$r) }

    # 약제팀 ZT411 골든 이미지 로컬 드라이버 폴백 경로 자동 포함 (기존 PC 백업 드라이버 부재 시에만 사용)
    foreach ($ztCand in @(
        'C:\Users\admin\드라이버(win10_x64)\AMIS 3.0 장비\ZT411 (약국용 신형라벨프린터)',
        'C:\Users\admin\드라이버(win10x64)\AMIS 3.0 장비\ZT411 (약국용 신형라벨프린터)',
        'C:\ZD8-6-5-26125',
        'C:\ZD5-1-17-7412'
    )) {
        if (-not $roots.Contains($ztCand)) { $roots.Add($ztCand) }
    }
    foreach ($amisRoot in @(
        'C:\Users\admin\드라이버(win10_x64)\AMIS 3.0 장비',
        'C:\Users\admin\드라이버(win10x64)\AMIS 3.0 장비',
        'C:\Users\admin\드라이버(win10_x64)\AMIS3.0장비',
        'C:\Users\admin\드라이버(win10x64)\AMIS3.0장비'
    )) {
        if (Test-Path -LiteralPath $amisRoot) {
            foreach ($zd in @(Get-ChildItem -LiteralPath $amisRoot -Directory -Filter '*ZT411*' -ErrorAction SilentlyContinue)) {
                if ($zd.FullName -notmatch '(?i)ZD410|ZD411' -and -not $roots.Contains($zd.FullName)) {
                    $roots.Add($zd.FullName)
                }
            }
        }
    }

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $root -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($f.FullName -match $global:AsanCtx.DriverExcludeFolderPattern) { continue }
            $key = $f.FullName.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $infList.Add($f)
            }
        }
    }
    return @($infList.ToArray())
}

function Measure-DriverDisplayName {
    param(
        [string]$DisplayName,
        [string]$SearchTarget,
        [string]$WantedNorm,
        [string]$WantedVendor,
        [string[]]$Tokens,
        [string[]]$ModelStems,
        [bool]$WantedHasDigits,
        [bool]$PreferPcl6,
        [bool]$AllowVendorUniversal = $false
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) { return -1 }
    if ($DisplayName -match $global:AsanCtx.MicrosoftInboxGenericRegex) { return -1 }
    if ($DisplayName -match '(?i)Samsung Universal Print Driver') { return -1 }

    $isVendorUniv = ($DisplayName -match $global:AsanCtx.VendorUniversalRegex)
    if ($isVendorUniv -and -not $AllowVendorUniversal) { return -1 }

    $dnVendors = @(Get-DetectedVendors -Text $DisplayName)
    if ($WantedVendor -and $dnVendors.Count -gt 0 -and ($dnVendors -notcontains $WantedVendor)) { return -1 }

    if ($isVendorUniv) {
        if ($WantedVendor -and ($dnVendors -contains $WantedVendor)) {
            $uScore = 200
            if ($PreferPcl6) { $uScore += (Get-ProtocolPreferenceBonus -DriverName $DisplayName) }
            return $uScore
        }
        return -1
    }

    $dnNorm = Format-NormalizedText $DisplayName
    $dScore = 0
    if ($DisplayName -eq $SearchTarget) { $dScore += 1200 }
    elseif ($WantedNorm -and $dnNorm -eq $WantedNorm) { $dScore += 1100 }

    $tokHits  = 0
    $digitHit = $false
    foreach ($t in @($Tokens)) {
        $tNorm = Format-NormalizedText $t
        if ($dnNorm.Contains($tNorm)) {
            $tokHits++
            if ($t -match '^[a-z0-9]+$' -and $t -match '\d' -and $t -notmatch '^\d+(?:dpi|bit)$') {
                $dScore += 160
                $digitHit = $true
            } else {
                $dScore += 40
            }
        }
    }

    if (-not $digitHit -and $WantedHasDigits) {
        if (Test-WildcardModelMatch -CandidateDisplayName $DisplayName -WantedStems $ModelStems) {
            $dScore += 280
            $digitHit = $true
        }
    }

    if ($Tokens.Count -gt 0 -and $tokHits -eq $Tokens.Count) { $dScore += 300 }
    if ($PreferPcl6) { $dScore += (Get-ProtocolPreferenceBonus -DriverName $DisplayName) }

    if ($WantedHasDigits -and -not $digitHit -and $dScore -lt 900) { return -1 }
    return $dScore
}

function Install-DriverInfSafe {
    param([string]$InfPath)
    if ([string]::IsNullOrWhiteSpace($InfPath) -or (-not (Test-Path -LiteralPath $InfPath))) { return $false }
    $r1 = Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/add-driver', $InfPath, '/install')
    if ($r1.ExitCode -eq 0 -or $r1.ExitCode -eq 259 -or $r1.ExitCode -eq 3010) { return $true }
    # 구형 Windows 10 초기 빌드(1507/1511) 레거시 문법 폴백
    $r2 = Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('-i', '-a', $InfPath)
    return ($r2.ExitCode -eq 0 -or $r2.ExitCode -eq 259 -or $r2.ExitCode -eq 3010)
}

function Find-AndInstallDriverFromIndex {
    param(
        [object[]]$InfIndex,
        [string]$SearchTarget,
        [string]$WantedDriverName,
        [string]$WantedVendor,
        [bool]$PreferPcl6 = $true,
        [bool]$AllowVendorUniversal = $false
    )

    if (-not $InfIndex -or $InfIndex.Count -eq 0) { return $null }

    $isWantedInboxGen = ($WantedDriverName -match $global:AsanCtx.MicrosoftInboxGenericRegex)
    $wantedNorm       = Format-NormalizedText $SearchTarget
    $tokens           = @(Get-SignificantTokens $SearchTarget)
    $modelStems       = @(Get-ModelStems -Tokens $tokens)
    $wantedHasDigits  = ($modelStems.Count -gt 0)

    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $InfIndex) {
        if ($WantedVendor -and $entry.Vendors -and $entry.Vendors.Count -gt 0 -and ($entry.Vendors -notcontains $WantedVendor)) { continue }

        $score = 0
        if ($wantedNorm -and $entry.TextNorm.Contains($wantedNorm)) { $score += 1000 }

        $bestDispName  = $null
        $bestDispScore = -1

        foreach ($dn in $entry.DisplayNames) {
            $dScore = Measure-DriverDisplayName -DisplayName $dn -SearchTarget $SearchTarget -WantedNorm $wantedNorm -WantedVendor $WantedVendor -Tokens $tokens -ModelStems $modelStems -WantedHasDigits $wantedHasDigits -PreferPcl6 $PreferPcl6 -AllowVendorUniversal $AllowVendorUniversal
            if ($dScore -ge 160 -and $dScore -gt $bestDispScore) {
                $bestDispScore = $dScore
                $bestDispName  = $dn
            }
        }

        if ($bestDispScore -ge 160 -and $bestDispName) {
            $candidates.Add([pscustomobject]@{
                Path        = $entry.Path
                Score       = ($score + $bestDispScore)
                BestDisplay = $bestDispName
            })
        }
    }

    foreach ($cand in ($candidates | Sort-Object Score -Descending | Select-Object -First 8)) {
        $pnpOk = Install-DriverInfSafe -InfPath $cand.Path
        $tryNames = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($cand.BestDisplay)) { $tryNames.Add($cand.BestDisplay) }
        if (-not $AllowVendorUniversal -and -not $isWantedInboxGen -and -not [string]::IsNullOrWhiteSpace($WantedDriverName) -and -not $tryNames.Contains($WantedDriverName)) {
            $tryNames.Add($WantedDriverName)
        }

        foreach ($dn in $tryNames) {
            if ($pnpOk) {
                try {
                    Add-PrinterDriver -Name $dn -ErrorAction Stop
                } catch {
                    [void](Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/ia', '/q', '/m', $dn, '/f', $cand.Path))
                }
            } else {
                # PnP DB 손상 환경에서도 PrintUIEntry /ia /f 로 스풀러 직접 드라이버 설치 시도
                [void](Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/ia', '/q', '/m', $dn, '/f', $cand.Path))
            }
            $verify = @(Get-PrinterDriverSafe | Where-Object { $_.Name -eq $dn }) | Select-Object -First 1
            if ($verify) { return [string]$verify.Name }
        }
    }
    return $null
}

function New-ProtocolNoticeText {
    param(
        [string]$DriverName,
        [string]$OrigProto,
        [bool]$PreferPcl6
    )
    if (-not $PreferPcl6) { return $null }
    $newProto = Get-DriverProtocolTag -DriverName $DriverName
    if ($newProto -ne 'PCL6' -and $newProto -ne 'KX') {
        return "PCL6 드라이버 미발견으로 '$newProto'($DriverName) 적용됨"
    }
    if ($OrigProto -ne 'UNKNOWN' -and $OrigProto -ne 'OTHER' -and $newProto -ne $OrigProto) {
        return "프로토콜 변경됨 ($OrigProto -> $newProto)"
    }
    return $null
}

function Resolve-BestDriverForPrinter {
    param(
        [string]$PrinterName,
        [string]$WantedDriverName,
        [string]$ModelHint = $null,
        [hashtable]$DriverIndexCache,
        [bool]$ExcludeFromPcl6 = $false,
        [switch]$ForceUpgradeGeneric,
        [hashtable]$PreExistingDrivers = $null,
        [switch]$PreferExportedFirst
    )

    $preferPcl6       = (-not $ExcludeFromPcl6)
    $isWantedInboxGen = ($WantedDriverName -match $global:AsanCtx.MicrosoftInboxGenericRegex)
    $wantedOwnStems   = @(Get-ModelStems -Tokens (Get-SignificantTokens $WantedDriverName))
    $isPureGeneric    = ($WantedDriverName -match '(?i)^(Microsoft IPP Class Driver|Microsoft Point and Print|Microsoft Enhanced Point and Print|Generic\s*/\s*Text Only|Microsoft PCL6 Class Driver|Microsoft PS Class Driver)$')

    $searchTarget = $WantedDriverName
    if ([string]::IsNullOrWhiteSpace($WantedDriverName) -or ($isWantedInboxGen -and ($isPureGeneric -or $wantedOwnStems.Count -eq 0))) {
        if (-not [string]::IsNullOrWhiteSpace($ModelHint)) { $searchTarget = $ModelHint }
        else { $searchTarget = $PrinterName }
    } elseif ($isWantedInboxGen -and -not [string]::IsNullOrWhiteSpace($ModelHint)) {
        $searchTarget = "$WantedDriverName $ModelHint"
    }

    $wantedVendor = Get-DetectedVendor -Text $WantedDriverName
    if (-not $wantedVendor) { $wantedVendor = Get-DetectedVendor -Text $ModelHint }
    if (-not $wantedVendor) { $wantedVendor = Get-DetectedVendor -Text $PrinterName }
    $isSamsung       = ($wantedVendor -eq 'SAMSUNG')
    $origProto       = Get-DriverProtocolTag -DriverName $WantedDriverName
    $wantedNorm      = Format-NormalizedText $WantedDriverName
    $searchNorm      = Format-NormalizedText $searchTarget
    $tokens          = @(Get-SignificantTokens $searchTarget)
    $modelStems      = @(Get-ModelStems -Tokens $tokens)
    $wantedHasDigits = ($modelStems.Count -gt 0)

    # [1-A단계] 이미 스풀러에 정상 등록된 원본 드라이버 유지 (MS 인박스 범용 제외)
    # 단, -PreferExportedFirst(ZT411 등)이고 복원 전 골든 이미지에 선설치된 드라이버라면 Exported(기존 PC) 우선 탐색
    $installedAll = @(Get-PrinterDriverSafe)
    if (-not $ForceUpgradeGeneric -and -not $isWantedInboxGen -and -not [string]::IsNullOrWhiteSpace($WantedDriverName)) {
        $exact = $installedAll | Where-Object { ($_.Name -eq $WantedDriverName -or (Format-NormalizedText $_.Name) -eq $wantedNorm) -and $_.Name -notmatch $global:AsanCtx.MicrosoftInboxGenericRegex } | Select-Object -First 1
        if ($exact) {
            $isExactPreExisting = ($null -ne $PreExistingDrivers -and $PreExistingDrivers.ContainsKey(([string]$exact.Name).ToLowerInvariant()))
            if (-not ($PreferExportedFirst -and $isExactPreExisting)) {
                $usedSam = ($exact.Name -match '(?i)Samsung Universal Print Driver')
                $exactSrc = 'OriginalRestored'
                if ($isExactPreExisting) { $exactSrc = 'Win11GoldenSpooler' }
                return [pscustomobject]@{
                    Success         = $true
                    DriverName      = [string]$exact.Name
                    Source          = $exactSrc
                    UsedSamFallback = $usedSam
                    ProtocolNotice  = $null
                }
            }
        }
    }

    # ==================== [PASS 1: 모델 전용 드라이버 전 단계 탐색] ====================
    $expIndex = $DriverIndexCache['Exported']
    $hitExp = Find-AndInstallDriverFromIndex -InfIndex $expIndex -SearchTarget $searchTarget -WantedDriverName $WantedDriverName -WantedVendor $wantedVendor -PreferPcl6:$preferPcl6 -AllowVendorUniversal:$false
    if ($hitExp) {
        $pNotice = New-ProtocolNoticeText -DriverName $hitExp -OrigProto $origProto -PreferPcl6 $preferPcl6
        return [pscustomobject]@{ Success = $true; DriverName = $hitExp; Source = 'ExportedBackupDriver'; UsedSamFallback = $false; ProtocolNotice = $pNotice }
    }

    $bestBuiltIn    = $null
    $bestBuiltScore = -1
    foreach ($drv in $installedAll) {
        $sc = Measure-DriverDisplayName -DisplayName $drv.Name -SearchTarget $searchTarget -WantedNorm $searchNorm -WantedVendor $wantedVendor -Tokens $tokens -ModelStems $modelStems -WantedHasDigits $wantedHasDigits -PreferPcl6 $preferPcl6 -AllowVendorUniversal $false
        if ($sc -ge 160 -and $sc -gt $bestBuiltScore) {
            $bestBuiltScore = $sc
            $bestBuiltIn    = [string]$drv.Name
        }
    }
    if ($bestBuiltIn) {
        $pNotice = New-ProtocolNoticeText -DriverName $bestBuiltIn -OrigProto $origProto -PreferPcl6 $preferPcl6
        return [pscustomobject]@{ Success = $true; DriverName = $bestBuiltIn; Source = 'Win11GoldenSpooler'; UsedSamFallback = $false; ProtocolNotice = $pNotice }
    }

    if ($null -eq $DriverIndexCache['DriverStore']) {
        $DriverIndexCache['DriverStore'] = @(New-InfIndexCache -InfFiles (Get-DriverStorePrinterInfFiles))
    }
    $storeIndex = $DriverIndexCache['DriverStore']
    $hitStore   = Find-AndInstallDriverFromIndex -InfIndex $storeIndex -SearchTarget $searchTarget -WantedDriverName $WantedDriverName -WantedVendor $wantedVendor -PreferPcl6:$preferPcl6 -AllowVendorUniversal:$false
    if ($hitStore) {
        $pNotice = New-ProtocolNoticeText -DriverName $hitStore -OrigProto $origProto -PreferPcl6 $preferPcl6
        return [pscustomobject]@{ Success = $true; DriverName = $hitStore; Source = 'Win11DriverStore'; UsedSamFallback = $false; ProtocolNotice = $pNotice }
    }

    if ($null -eq $DriverIndexCache['LocalPrt']) {
        $DriverIndexCache['LocalPrt'] = @(New-InfIndexCache -InfFiles (Get-LocalPrtFolderInfFiles))
    }
    $prtIndex = $DriverIndexCache['LocalPrt']
    $hitPrt   = Find-AndInstallDriverFromIndex -InfIndex $prtIndex -SearchTarget $searchTarget -WantedDriverName $WantedDriverName -WantedVendor $wantedVendor -PreferPcl6:$preferPcl6 -AllowVendorUniversal:$false
    if ($hitPrt) {
        $pNotice = New-ProtocolNoticeText -DriverName $hitPrt -OrigProto $origProto -PreferPcl6 $preferPcl6
        return [pscustomobject]@{ Success = $true; DriverName = $hitPrt; Source = 'LocalPrtFolder'; UsedSamFallback = $false; ProtocolNotice = $pNotice }
    }

    # ==================== [PASS 2: 3.5단계 제조사 공식 통합 드라이버 폴백] ====================
    $bestUniv   = $null
    $bestUnivSc = -1
    foreach ($drv in $installedAll) {
        if ($drv.Name -notmatch $global:AsanCtx.VendorUniversalRegex) { continue }
        $sc = Measure-DriverDisplayName -DisplayName $drv.Name -SearchTarget $searchTarget -WantedNorm $searchNorm -WantedVendor $wantedVendor -Tokens $tokens -ModelStems $modelStems -WantedHasDigits $wantedHasDigits -PreferPcl6 $preferPcl6 -AllowVendorUniversal $true
        if ($sc -ge 160 -and $sc -gt $bestUnivSc) {
            $bestUnivSc = $sc
            $bestUniv   = [string]$drv.Name
        }
    }
    if ($bestUniv) {
        return [pscustomobject]@{ Success = $true; DriverName = $bestUniv; Source = 'VendorUniversalSpooler'; UsedSamFallback = $false; ProtocolNotice = "모델 전용 드라이버 미발견으로 제조사 공식 통합 드라이버($bestUniv) 적용됨" }
    }

    foreach ($tierPair in @(
        @{ Name = 'VendorUniversalDriverStore'; Index = $storeIndex },
        @{ Name = 'VendorUniversalLocalPrt';    Index = $prtIndex },
        @{ Name = 'VendorUniversalExported';    Index = $expIndex }
    )) {
        $hitUniv = Find-AndInstallDriverFromIndex -InfIndex $tierPair.Index -SearchTarget $searchTarget -WantedDriverName $WantedDriverName -WantedVendor $wantedVendor -PreferPcl6:$preferPcl6 -AllowVendorUniversal:$true
        if ($hitUniv) {
            return [pscustomobject]@{ Success = $true; DriverName = $hitUniv; Source = $tierPair.Name; UsedSamFallback = $false; ProtocolNotice = "모델 전용 드라이버 미발견으로 제조사 공식 통합 드라이버($hitUniv) 적용됨" }
        }
    }

    # ==================== [PASS 3: 4단계 삼성 최후 폴백 (UPD 3)] ====================
    if ($isSamsung) {
        $samUpd = @(Get-PrinterDriverSafe | Where-Object { $_.Name -match '(?i)Samsung Universal Print Driver 3' }) | Select-Object -First 1
        if (-not $samUpd) {
            try { Add-PrinterDriver -Name 'Samsung Universal Print Driver 3' -ErrorAction Stop } catch {}
            $samUpd = @(Get-PrinterDriverSafe | Where-Object { $_.Name -match '(?i)Samsung Universal Print Driver 3' }) | Select-Object -First 1
        }
        if (-not $samUpd -and $prtIndex) {
            $us003 = @($prtIndex | Where-Object { $_.FileName -match '(?i)^us003\.inf$' }) | Select-Object -First 1
            if ($us003) {
                [void](Install-DriverInfSafe -InfPath $us003.Path)
                try {
                    Add-PrinterDriver -Name 'Samsung Universal Print Driver 3' -ErrorAction Stop
                } catch {
                    [void](Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/ia', '/q', '/m', 'Samsung Universal Print Driver 3', '/f', $us003.Path))
                }
                $samUpd = @(Get-PrinterDriverSafe | Where-Object { $_.Name -match '(?i)Samsung Universal Print Driver 3' }) | Select-Object -First 1
            }
        }
        if ($samUpd) {
            return [pscustomobject]@{
                Success         = $true
                DriverName      = [string]$samUpd.Name
                Source          = 'SamsungUniversalFallback'
                UsedSamFallback = $true
                ProtocolNotice  = '[주의] 원본 복원 실패로 삼성 범용 드라이버(UPD 3)로 대체 설치됨 — 테스트 페이지 오류 시 모델 전용 드라이버로 교체 및 장치설정(PCL6) 필요'
            }
        }
    }

    return [pscustomobject]@{
        Success         = $false
        DriverName      = $null
        Source          = 'NotFound'
        UsedSamFallback = $false
        ProtocolNotice  = '백업 파일, Windows 기본 드라이버, 로컬 드라이버 폴더에서 일치하는 드라이버를 찾지 못했습니다.'
    }
}

# ============================================================================
# Inbox INF 제외 + 미매칭 서드파티 한정 정밀 oem*.inf 추출
# ============================================================================
function Export-DriverPackageFallback {
    param(
        [string]$SourceRepoDir,
        [string]$TargetSubDir
    )
    if ([string]::IsNullOrWhiteSpace($SourceRepoDir) -or (-not (Test-Path -LiteralPath $SourceRepoDir))) { return $false }
    try {
        if (-not (Test-Path -LiteralPath $TargetSubDir)) {
            New-Item -ItemType Directory -Path $TargetSubDir -Force | Out-Null
        }
        $rc = (Invoke-NativeCommand -FilePath 'robocopy.exe' -Arguments @($SourceRepoDir, $TargetSubDir, '/E', '/R:1', '/W:1')).ExitCode
        if ($rc -lt 8) {
            $hasInf = (@(Get-ChildItem -LiteralPath $TargetSubDir -Filter '*.inf' -File -ErrorAction SilentlyContinue)).Count -gt 0
            return $hasInf
        }
    } catch {}
    return $false
}

function Export-PreciseThirdPartyDrivers {
    param(
        [string[]]$ActiveDriverNames,
        [string[]]$ExplicitPublishedNames,
        [string[]]$ClassGuidFilters,
        [string]$DestinationDir
    )

    if (-not (Test-Path -LiteralPath $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $toExport     = [System.Collections.Generic.List[string]]::new()
    $directPkgMap = @{}
    foreach ($p in @($ExplicitPublishedNames)) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and -not $toExport.Contains($p)) { $toExport.Add($p) }
    }

    $blocks      = @(Get-PnpUtilDriverBlocks)
    $classBlocks = @($blocks | Where-Object { (-not $ClassGuidFilters) -or ($ClassGuidFilters.Count -eq 0) -or ($ClassGuidFilters -contains $_['ClassGuid']) })
    $blockByPub  = @{}
    foreach ($cb in $blocks) {
        if ($cb['PublishedName']) { $blockByPub[([string]$cb['PublishedName']).ToLowerInvariant()] = $cb }
    }

    $unmatchedThirdParty = [System.Collections.Generic.List[string]]::new()
    if ($ActiveDriverNames -and $ActiveDriverNames.Count -gt 0) {
        $drvMap = @{}
        foreach ($d in @(Get-PrinterDriverSafe)) {
            $k      = [string]$d.Name
            $isX64  = ([string]$d.PrinterEnvironment -match '(?i)x64')
            $hasInf = (-not [string]::IsNullOrWhiteSpace([string]$d.InfPath))
            if (-not $drvMap.ContainsKey($k)) {
                $drvMap[$k] = $d
            } else {
                $prev       = $drvMap[$k]
                $prevIsX64  = ([string]$prev.PrinterEnvironment -match '(?i)x64')
                $prevHasInf = (-not [string]::IsNullOrWhiteSpace([string]$prev.InfPath))
                if (($isX64 -and $hasInf -and (-not ($prevIsX64 -and $prevHasInf))) -or ($hasInf -and -not $prevHasInf)) {
                    $drvMap[$k] = $d
                }
            }
        }

        foreach ($dName in $ActiveDriverNames) {
            if ($dName -match $global:AsanCtx.MicrosoftInboxGenericRegex) { continue }
            $matchedThis = $false
            $isInboxInf  = $false

            if ($drvMap.ContainsKey($dName) -and -not [string]::IsNullOrWhiteSpace([string]$drvMap[$dName].InfPath)) {
                $fullInfPath = [string]$drvMap[$dName].InfPath
                $infFileName = [IO.Path]::GetFileName($fullInfPath)
                if ($infFileName -match $global:AsanCtx.InboxInfNameRegex) {
                    $isInboxInf = $true
                } else {
                    foreach ($b in $classBlocks) {
                        $pub  = [string]$b['PublishedName']
                        $orig = [string]$b['OriginalName']
                        if (($orig -ieq $infFileName) -or ($pub -ieq $infFileName)) {
                            if ($pub -and -not $toExport.Contains($pub)) { $toExport.Add($pub) }
                            if ($pub -and (Test-Path -LiteralPath $fullInfPath)) {
                                $directPkgMap[$pub.ToLowerInvariant()] = [IO.Path]::GetDirectoryName($fullInfPath)
                            }
                            $matchedThis = $true
                        }
                    }
                    # pnputil 매칭 실패(구형 Win10 1507/1511 또는 PnP DB 손상) 시에도 스풀러 레지스트리 InfPath 패키지 직접 보존
                    if ((-not $matchedThis) -and ($fullInfPath -match '(?i)\\DriverStore\\FileRepository\\') -and (Test-Path -LiteralPath $fullInfPath)) {
                        $pkgDir = [IO.Path]::GetDirectoryName($fullInfPath)
                        $pkgKey = 'REPO:' + ([IO.Path]::GetFileName($pkgDir))
                        if (-not $toExport.Contains($pkgKey)) {
                            $toExport.Add($pkgKey)
                            $directPkgMap[$pkgKey.ToLowerInvariant()] = $pkgDir
                        }
                        $matchedThis = $true
                    }
                }
            }
            if (-not $matchedThis -and -not $isInboxInf) {
                $unmatchedThirdParty.Add($dName)
            }
        }
    }

    if ($unmatchedThirdParty.Count -gt 0) {
        # 문자열 단순 포함 대신 표준 벤더 분류(Get-DetectedVendors)로 매칭 (ZDesigner->ZEBRA, ECOSYS->KYOCERA 등 정확 매칭, SEWOO 제외)
        $scopedVendors = [System.Collections.Generic.List[string]]::new()
        foreach ($ud in $unmatchedThirdParty) {
            foreach ($v in @(Get-DetectedVendors -Text $ud)) {
                if ($v -eq 'SEWOO') { continue }
                if (-not $scopedVendors.Contains($v)) { $scopedVendors.Add($v) }
            }
        }
        foreach ($b in $classBlocks) {
            $pub  = [string]$b['PublishedName']
            $meta = "$($b['ProviderName']) $($b['OriginalName'])"
            if ([string]::IsNullOrWhiteSpace($pub)) { continue }
            $blkVendors = @(Get-DetectedVendors -Text $meta)
            if ($blkVendors -contains 'SEWOO') { continue }
            foreach ($sv in $scopedVendors) {
                if ($blkVendors -contains $sv) {
                    if (-not $toExport.Contains($pub)) { $toExport.Add($pub) }
                    break
                }
            }
        }
    }

    $repoRoot      = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
    $exportedCount = 0
    foreach ($oemInf in $toExport) {
        if ($oemInf.StartsWith('REPO:')) {
            $pkgFolderName = $oemInf.Substring(5)
            $srcRepoDir    = $directPkgMap[$oemInf.ToLowerInvariant()]
            $subDir        = Join-Path $DestinationDir (Get-SafeFileName -Text $pkgFolderName)
            if (Export-DriverPackageFallback -SourceRepoDir $srcRepoDir -TargetSubDir $subDir) {
                $exportedCount++
            }
            continue
        }

        $subDir = Join-Path $DestinationDir ([IO.Path]::GetFileNameWithoutExtension($oemInf))
        if (-not (Test-Path -LiteralPath $subDir)) { New-Item -ItemType Directory -Path $subDir -Force | Out-Null }
        $r = Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/export-driver', $oemInf, $subDir)
        $hasExportedInf = ($r.ExitCode -eq 0) -and ((@(Get-ChildItem -LiteralPath $subDir -Filter '*.inf' -File -ErrorAction SilentlyContinue)).Count -gt 0)
        if ($hasExportedInf) {
            $exportedCount++
            continue
        }

        # pnputil /export-driver 미지원(Win10 1507/1511) 또는 서비스 손상 시 DriverStore\FileRepository 직접 복사 폴백
        $fbDir = $directPkgMap[$oemInf.ToLowerInvariant()]
        if (-not $fbDir -and (Test-Path -LiteralPath $repoRoot) -and $blockByPub.ContainsKey($oemInf.ToLowerInvariant())) {
            $origInf = [string]$blockByPub[$oemInf.ToLowerInvariant()]['OriginalName']
            if (-not [string]::IsNullOrWhiteSpace($origInf)) {
                $baseOrig = [IO.Path]::GetFileNameWithoutExtension($origInf)
                $candRepo = @(Get-ChildItem -LiteralPath $repoRoot -Directory -Filter "$baseOrig.inf_*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
                if ($candRepo) { $fbDir = $candRepo.FullName }
            }
        }
        if ($fbDir -and (Export-DriverPackageFallback -SourceRepoDir $fbDir -TargetSubDir $subDir)) {
            $exportedCount++
        }
    }
    return $exportedCount
}
