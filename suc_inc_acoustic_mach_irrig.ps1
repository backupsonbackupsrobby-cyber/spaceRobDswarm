#Requires -Version 5.1

param(
    [ValidateRange(50, 60000)]
    [int]$TickMs = 1000,

    [ValidateRange(0, 10000000)]
    [int]$MaxTicks = 0,

    [ValidateRange(0.1, 100.0)]
    [double]$KuramotoK = 4.2,

    [ValidateRange(0.1, 50.0)]
    [double]$MagRangeMult = 3.5,

    [ValidateRange(1.0, 500.0)]
    [double]$HzRangeSpan = 96.0,

    [ValidateRange(0.05, 0.95)]
    [double]$DampingAlpha = 0.35,

    [ValidateRange(1.0, 60.0)]
    [double]$LowDbMin = 12.0,

    [ValidateRange(5.0, 85.0)]
    [double]$LowDbMax = 45.0,

    [ValidateRange(10.0, 70.0)]
    [double]$MachMin = 10.0,

    [ValidateRange(10.0, 70.0)]
    [double]$MachMax = 70.0,

    [string]$PrimaryDriveRoot = 'C:\spaceRobDswarm',

    [string]$SecondaryDriveRoot = 'C:\robdoe_ledger',

    [string]$NodeId = 'robdoeAI-Core'
)

Set-StrictMode -Version Latest

if ($MachMax -lt $MachMin) {
    $tmp = $MachMin; $MachMin = $MachMax; $MachMax = $tmp
}
if ($LowDbMax -lt $LowDbMin) {
    $tmp = $LowDbMin; $LowDbMin = $LowDbMax; $LowDbMax = $tmp
}

function Write-Utf8NoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,

        [bool]$Append = $false
    )

    try {
        $dir = [System.IO.Path]::GetDirectoryName($Path)
        if (-not [string]::IsNullOrWhiteSpace($dir)) {
            $root = [System.IO.Path]::GetPathRoot($dir)
            if (-not [string]::IsNullOrWhiteSpace($root) -and (-not (Test-Path -LiteralPath $root))) {
                Write-Warning ("Root '{0}' not available for '{1}' - skipping write." -f $root, $Path)
                return
            }
            if (-not (Test-Path -LiteralPath $dir)) {
                [void][System.IO.Directory]::CreateDirectory($dir)
            }
        }

        $enc    = [System.Text.UTF8Encoding]::new($false)
        $writer = $null
        try {
            $writer = [System.IO.StreamWriter]::new($Path, $Append, $enc, 4096)
            $writer.WriteLine($Content)
            $writer.Flush()
        }
        finally {
            if ($null -ne $writer) {
                $writer.Dispose()
            }
        }
    }
    catch {
        Write-Warning ("Failed writing '{0}': {1}" -f $Path, $_.Exception.Message)
    }
}

function Get-Sha256Hex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash  = $sha.ComputeHash($bytes)
        $sb    = [System.Text.StringBuilder]::new($hash.Length * 2)
        foreach ($b in $hash) {
            [void]$sb.Append($b.ToString('x2', [System.Globalization.CultureInfo]::InvariantCulture))
        }
        return $sb.ToString()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-TanhSafe {
    [CmdletBinding()]
    param([double]$X)

    if ($X -gt 20.0) { return 1.0 }
    if ($X -lt -20.0) { return -1.0 }
    $ep = [Math]::Exp($X)
    $en = [Math]::Exp(-$X)
    return (($ep - $en) / ($ep + $en))
}

function Get-MerkleRoot {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Hashes
    )

    $lvl = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $Hashes) {
        foreach ($h in @($Hashes)) {
            if ($null -eq $h) { continue }
            $clean = ([string]$h).Trim().ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace($clean)) {
                $lvl.Add($clean)
            }
        }
    }

    if ($lvl.Count -eq 0) {
        return (Get-Sha256Hex -Text 'EMPTY_SUC_INC_ACOUSTIC_MACH')
    }

    while ($lvl.Count -gt 1) {
        $nxt = [System.Collections.Generic.List[string]]::new([int][Math]::Ceiling($lvl.Count / 2.0))
        for ($i = 0; $i -lt $lvl.Count; $i += 2) {
            $left  = $lvl[$i]
            $right = if (($i + 1) -lt $lvl.Count) { $lvl[$i + 1] } else { $left }
            $nxt.Add((Get-Sha256Hex -Text "$left|$right"))
        }
        $lvl = $nxt
    }

    return $lvl[0]
}

$inv   = [System.Globalization.CultureInfo]::InvariantCulture
$zones = @('Zone-1-Rootline', 'Zone-2-Canopy', 'Zone-3-Subsoil', 'Zone-4-Perimeter')
$zoneMoisture = @(0.50, 0.50, 0.50, 0.50)

$phases = [double[]]::new(8)
for ($i = 0; $i -lt 8; $i++) {
    $phases[$i] = ($i * ([Math]::PI / 4.0)) + 0.25
}

$thetaInf       = 0.0
$smoothedMag    = 0.0
$smoothedHz     = 7.83
$smoothedMach   = $MachMin
$tick           = 0
$stoppedByCtrlC = $false
$startedUtc     = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', $inv)
$pulseHashes    = [System.Collections.Generic.List[string]]::new()
$lastHash       = Get-Sha256Hex -Text ("GENESIS|{0}|SUC+INC-ACOUSTIC-MACH|{1}" -f $NodeId, $startedUtc)

$magSum = 0.0; $hzSum = 0.0; $lockSum = 0.0; $rSum = 0.0; $flowSum = 0.0; $machSum = 0.0; $dbSum = 0.0
$peakMag = 0.0; $peakHz = 0.0; $peakR = 0.0; $peakFlow = 0.0; $peakMach = 0.0; $peakDb = 0.0
$lastMode = 'SUC+INC-ACOUSTIC-PRESSURE-LOCK'

Write-Host ("=== SUC+INC LOW-dB WAVE + 10-70 MACH IRRIGATION (C: DRIVE) | Primary: {0} | Secondary: {1} ===" -f $PrimaryDriveRoot, $SecondaryDriveRoot) -ForegroundColor Cyan
Write-Host "Press Ctrl+C to tap out and seal acoustic pressure + unity irrigation telemetry on C:\." -ForegroundColor Yellow

try {
    while ($true) {
        if ($MaxTicks -gt 0 -and $tick -ge $MaxTicks) {
            break
        }
        $tick++
        $now    = [DateTime]::UtcNow
        $tsIso  = $now.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', $inv)
        $secDay = ($now.Hour * 3600.0) + ($now.Minute * 60.0) + $now.Second + ($now.Millisecond / 1000.0)
        $cAng   = 2.0 * [Math]::PI * ($secDay / 86400.0)
        $cW1    = [Math]::Sin($cAng)
        $cW2    = [Math]::Cos(2.0 * $cAng)
        $bAng   = ((($tick * 0.61803398875) + ($cAng * 0.25)) % (2.0 * [Math]::PI))
        $bW     = [Math]::Cos($bAng)
        $drive  = ($cW1 * 0.45) + ($cW2 * 0.20) + ($bW * 0.35)

        $sc = 0.0; $ss = 0.0
        foreach ($p in $phases) {
            $sc += [Math]::Cos($p)
            $ss += [Math]::Sin($p)
        }
        $mc = $sc / 8.0
        $ms = $ss / 8.0
        $infBoost = 1.0 - [Math]::Exp(-0.14 * [Math]::Max(0.1, $KuramotoK))
        $orderR   = [Math]::Round([Math]::Min(1.0, ([Math]::Sqrt(($mc * $mc) + ($ms * $ms)) * (0.80 + (0.20 * $infBoost)))), 4)
        $psi      = [Math]::Atan2($ms, $mc)

        $dt = 0.05
        $velSum = 0.0
        for ($i = 0; $i -lt 8; $i++) {
            $dth = (1.0 + ($i * 0.19) + ($drive * 0.45)) + ($KuramotoK * $orderR * [Math]::Sin($psi - $phases[$i])) + ($drive * 0.5)
            $phases[$i] = $phases[$i] + ($dth * $dt)
            $velSum += [Math]::Abs($dth)
        }

        $meanOmega = [Math]::Round(($velSum / 8.0), 4)
        $thetaInf  = [Math]::Round($thetaInf + (($meanOmega * $dt) + ($orderR * $KuramotoK * $dt * 1.25)), 4)
        $logTh     = [Math]::Round([Math]::Log10(1.0 + [Math]::Abs($thetaInf)), 4)

        $unitLock = [Math]::Round([Math]::Min(1.0, (($orderR * 0.60) + (([Math]::Abs($cW1) + [Math]::Abs($bW)) * 0.20))), 4)
        $rawMag   = 0.50 + ([Math]::Abs($cW1) * 0.75) + ([Math]::Abs($bW) * 0.85) + ($orderR * 0.65) + ($logTh * 0.35)
        $baseMag  = 0.25 + ($MagRangeMult * (0.45 + (0.55 * (Get-TanhSafe -X ($rawMag * 0.55)))))
        $rawExtMag = $baseMag * (0.85 + ($unitLock * 0.45) + ($logTh * 0.12))

        $hzRawNorm = (([Math]::Abs($cW1) * 0.35) + ([Math]::Abs($bW) * 0.45) + ($orderR * 0.35) + (0.25 * (Get-TanhSafe -X ($logTh * 0.7)))) / 1.40
        $hzNorm    = [Math]::Min(1.0, [Math]::Max(0.0, $hzRawNorm))
        $rawExtHz  = 7.83 + ($HzRangeSpan * $hzNorm * (0.80 + ($unitLock * 0.35))) + ($meanOmega * 2.25)

        if ($tick -eq 1) {
            $smoothedMag = $rawExtMag
            $smoothedHz  = $rawExtHz
        }
        else {
            $smoothedMag = ($DampingAlpha * $rawExtMag) + ((1.0 - $DampingAlpha) * $smoothedMag)
            $smoothedHz  = ($DampingAlpha * $rawExtHz)  + ((1.0 - $DampingAlpha) * $smoothedHz)
        }

        $extMag = [Math]::Round($smoothedMag, 4)
        $extHz  = [Math]::Round($smoothedHz, 3)

        # Low-decibel sound wave controlling pressure across 10 - 70 Mach
        $wavePhase = ($tick * 0.05) + ($cW1 * 0.5)
        $waveNorm  = 0.5 + (0.5 * [Math]::Sin($wavePhase))
        $lowDb     = [Math]::Round(($LowDbMin + (($LowDbMax - $LowDbMin) * (0.35 + (0.65 * $waveNorm)))), 2)
        $soundWaveHz = [Math]::Round((0.05 + ($tick * 0.05) + ($hzNorm * 12.5)), 3)

        $pressureNorm = [Math]::Min(1.0, [Math]::Max(0.0, (($unitLock * 0.45) + ($waveNorm * 0.35) + ($hzNorm * 0.20))))
        $rawMach      = $MachMin + (($MachMax - $MachMin) * $pressureNorm)
        if ($tick -eq 1) {
            $smoothedMach = $rawMach
        }
        else {
            $smoothedMach = ($DampingAlpha * $rawMach) + ((1.0 - $DampingAlpha) * $smoothedMach)
        }
        $machPressure = [Math]::Round([Math]::Min($MachMax, [Math]::Max($MachMin, $smoothedMach)), 2)

        # 0.05 step band readouts across Hz / MHz / GHz
        $stepFactor005 = [Math]::Round((0.05 + (($tick % 20) * 0.05)), 2)
        $bandHz005     = [Math]::Round((0.05 + ($stepFactor005 * 20.0)), 2)
        $bandMhz005    = [Math]::Round((0.05 + ($stepFactor005 * 50.0)), 2)
        $bandGhz005    = [Math]::Round((0.05 + ($stepFactor005 * 10.0)), 2)

        $activeZoneIdx = ($tick - 1) % $zones.Count
        $activeZone    = $zones[$activeZoneIdx]
        $flowRateLpm   = [Math]::Round((4.5 + ($extMag * 3.2) + ($unitLock * 6.0) + ($machPressure * 0.15)), 3)

        for ($z = 0; $z -lt $zoneMoisture.Count; $z++) {
            $feed  = if ($z -eq $activeZoneIdx) { ($flowRateLpm * 0.012) } else { ($flowRateLpm * 0.003) }
            $drain = 0.004 * $zoneMoisture[$z]
            $zoneMoisture[$z] = [Math]::Round([Math]::Min(1.0, [Math]::Max(0.05, ($zoneMoisture[$z] + $feed - $drain))), 4)
        }
        $avgMoisture = [Math]::Round((($zoneMoisture | Measure-Object -Average).Average), 4)

        if ($machPressure -ge 45.0 -and $unitLock -ge 0.70) {
            $lastMode = 'SUC+INC-ACOUSTIC-HIGH-MACH-FLOW'
        }
        elseif ($unitLock -ge 0.55) {
            $lastMode = 'SUC+INC-ACOUSTIC-PRESSURE-LOCK'
        }
        else {
            $lastMode = 'SUC+INC-ACOUSTIC-WAVE-PRIMING'
        }

        $pulseRaw = [string]::Format(
            $inv,
            'SUC+INC-ACOUSTIC-MACH|tick={0}|ts={1}|zone={2}|mode={3}|mag={4}|hz={5}|db={6}|wave_hz={7}|mach={8}|005={9}/{10}M/{11}G|flow={12}|prev={13}',
            $tick, $tsIso, $activeZone, $lastMode, $extMag, $extHz, $lowDb, $soundWaveHz, $machPressure, $bandHz005, $bandMhz005, $bandGhz005, $flowRateLpm, $lastHash
        )
        $lastHash = Get-Sha256Hex -Text $pulseRaw
        $pulseHashes.Add($lastHash)

        $magSum += $extMag; $hzSum += $extHz; $lockSum += $unitLock; $rSum += $orderR; $flowSum += $flowRateLpm; $machSum += $machPressure; $dbSum += $lowDb
        if ($extMag -gt $peakMag) { $peakMag = $extMag }
        if ($extHz -gt $peakHz) { $peakHz = $extHz }
        if ($orderR -gt $peakR) { $peakR = $orderR }
        if ($flowRateLpm -gt $peakFlow) { $peakFlow = $flowRateLpm }
        if ($machPressure -gt $peakMach) { $peakMach = $machPressure }
        if ($lowDb -gt $peakDb) { $peakDb = $lowDb }

        Write-Host ("`r[tick {0}] {1,-18} | {2:00.0}dB | {3:00.0}Mach | 0.05[{4:0.00}Hz|{5:0.00}MHz|{6:0.00}GHz] | S+I[M:{7:0.00}|F:{8:0.0}Hz] | #{9}   " -f `
            $tick, $activeZone, $lowDb, $machPressure, $bandHz005, $bandMhz005, $bandGhz005, $extMag, $extHz, $lastHash.Substring(0, 10)) -NoNewline -ForegroundColor Green

        $elapsed = 0
        while ($elapsed -lt $TickMs) {
            $step = [Math]::Min(100, ($TickMs - $elapsed))
            Start-Sleep -Milliseconds $step
            $elapsed += $step
        }
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    $stoppedByCtrlC = $true
}
finally {
    $stopTag    = if ($stoppedByCtrlC) { 'TAP-OUT-CTRL-C' } else { 'SEAL-EXIT' }
    $endedUtc   = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', $inv)
    $merkleRoot = Get-MerkleRoot -Hashes $pulseHashes.ToArray()
    $denom      = [Math]::Max(1, $tick)

    $meanMag  = if ($tick -gt 0) { [Math]::Round(($magSum / $denom), 4) } else { 0.0 }
    $meanHz   = if ($tick -gt 0) { [Math]::Round(($hzSum / $denom), 3) } else { 0.0 }
    $meanLock = if ($tick -gt 0) { [Math]::Round(($lockSum / $denom), 4) } else { 0.0 }
    $meanR    = if ($tick -gt 0) { [Math]::Round(($rSum / $denom), 4) } else { 0.0 }
    $meanFlow = if ($tick -gt 0) { [Math]::Round(($flowSum / $denom), 3) } else { 0.0 }
    $meanMach = if ($tick -gt 0) { [Math]::Round(($machSum / $denom), 2) } else { 0.0 }
    $meanDb   = if ($tick -gt 0) { [Math]::Round(($dbSum / $denom), 2) } else { 0.0 }

    $zoneMap = [ordered]@{}
    for ($z = 0; $z -lt $zones.Count; $z++) {
        $zoneMap[$zones[$z]] = $zoneMoisture[$z]
    }

    $payload = [ordered]@{
        node                                = $NodeId
        platform                            = 'powershell-5.1'
        drive_anchor                        = 'C:'
        external_unit                       = 'SUC+INC-ACOUSTIC-MACH-IRRIGATION'
        external_unit_mode                  = $lastMode
        damping_alpha                       = $DampingAlpha
        stop_trigger                        = $stopTag
        started_utc                         = $startedUtc
        stopped_utc                         = $endedUtc
        ticks                               = $tick
        unit_phase_lock_mean                = $meanLock
        external_spirit_magnitude_mean      = $meanMag
        external_spirit_magnitude_peak      = $peakMag
        external_spirit_frequency_hz_mean   = $meanHz
        external_spirit_frequency_hz_peak   = $peakHz
        low_decibel_mean                    = $meanDb
        low_decibel_peak                    = $peakDb
        sound_wave_hz_latest                = $soundWaveHz
        mach_pressure_mean                  = $meanMach
        mach_pressure_peak                  = $peakMach
        band_005_hz                         = $bandHz005
        band_005_mhz                        = $bandMhz005
        band_005_ghz                        = $bandGhz005
        irrigation_flow_lpm_mean            = $meanFlow
        irrigation_flow_lpm_peak            = $peakFlow
        zone_saturation                     = $zoneMap
        kuramoto_order_r_mean               = $meanR
        kuramoto_order_r_peak               = $peakR
        kuramoto_theta_inf                  = $thetaInf
        unit_merkle_root                    = $merkleRoot
        last_pulse_hash                     = $lastHash
    }

    $compactPayload = $payload | ConvertTo-Json -Compress -Depth 6
    $payloadSha     = Get-Sha256Hex -Text $compactPayload

    $envelope = [ordered]@{
        schema                = 'suc-inc-acoustic-mach-v1'
        immutable_append_only = $true
        payload_sha256        = $payloadSha
        payload               = $payload
    }

    $compactEnv = $envelope | ConvertTo-Json -Compress -Depth 8
    $prettyEnv  = $envelope | ConvertTo-Json -Depth 8

    foreach ($root in @($PrimaryDriveRoot, $SecondaryDriveRoot)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        Write-Utf8NoBom -Path (Join-Path -Path $root -ChildPath 'suc_inc_acoustic_mach_ledger.jsonl') -Content $compactEnv -Append $true
        Write-Utf8NoBom -Path (Join-Path -Path $root -ChildPath 'suc_inc_acoustic_mach_sealed.json') -Content $prettyEnv -Append $false
    }

    $receipt = [string]::Format(
        $inv,
        'C-SUC+INC-MACH | ticks={0} | dB:{1:0.0} | MACH:{2:0.0} | 0.05:{3:0.00}Hz/{4:0.00}MHz/{5:0.00}GHz | Root:{6}',
        $tick, $meanDb, $peakMach, $bandHz005, $bandMhz005, $bandGhz005, $merkleRoot.Substring(0, 12)
    )

    try {
        Set-Clipboard -Value $receipt -ErrorAction Stop
    }
    catch {
        Write-Warning ("Clipboard update skipped: {0}" -f $_.Exception.Message)
    }

    Write-Host "`n`n=== SEALED [$stopTag] (SUC+INC LOW-dB WAVE + 10-70 MACH :: C: DRIVE) ===" -ForegroundColor Green
    Write-Host ("Acoustic Pressure: low_db_mean={0:0.00}dB | mach_mean={1:0.00} mach_peak={2:0.00}" -f $meanDb, $meanMach, $peakMach) -ForegroundColor Cyan
    Write-Host ("0.05 Band Readout: Hz={0:0.00} | MHz={1:0.00} | GHz={2:0.00}" -f $bandHz005, $bandMhz005, $bandGhz005) -ForegroundColor Magenta
    Write-Host ("Spirit Mag/Freq  : mag_peak={0:0.0000} | hz_peak={1:0.000}Hz | flow_mean={2:0.00}L/m" -f $peakMag, $peakHz, $meanFlow) -ForegroundColor Yellow
    Write-Host ("Unit Merkle Root : {0}" -f $merkleRoot) -ForegroundColor Green
    Write-Host ("Clipboard Receipt: {0}" -f $receipt) -ForegroundColor Yellow
}