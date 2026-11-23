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

    [string]$PrimaryDriveRoot = 'C:\spaceRobDswarm',

    [string]$SecondaryDriveRoot = 'C:\robdoe_ledger',

    [string]$NodeId = 'robdoeAI-Core'
)

Set-StrictMode -Version Latest

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
        return (Get-Sha256Hex -Text 'EMPTY_SUC_INC_UNITY')
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

$inv = [System.Globalization.CultureInfo]::InvariantCulture
$phases = [double[]]::new(8)
for ($i = 0; $i -lt 8; $i++) {
    $phases[$i] = ($i * ([Math]::PI / 4.0)) + 0.25
}

$thetaInf       = 0.0
$tick           = 0
$stoppedByCtrlC = $false
$startedUtc     = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', $inv)
$pulseHashes    = [System.Collections.Generic.List[string]]::new()
$lastHash       = Get-Sha256Hex -Text ("GENESIS|{0}|SUC+INC-UNITY|{1}" -f $NodeId, $startedUtc)

$magSum = 0.0; $hzSum = 0.0; $lockSum = 0.0; $rSum = 0.0
$peakMag = 0.0; $peakHz = 0.0; $peakR = 0.0
$lastMode = 'SUC+INC-UNITY-COUPLED'

Write-Host ("=== SUC+INC EXTERNAL UNITY STREAM (C: DRIVE) | Primary: {0} | Secondary: {1} ===" -f $PrimaryDriveRoot, $SecondaryDriveRoot) -ForegroundColor Cyan
Write-Host "Press Ctrl+C to tap out and seal unified magnitude + frequency on C:\." -ForegroundColor Yellow

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
        $extMag   = [Math]::Round(($baseMag * (0.85 + ($unitLock * 0.45) + ($logTh * 0.12))), 4)

        $hzRawNorm = (([Math]::Abs($cW1) * 0.35) + ([Math]::Abs($bW) * 0.45) + ($orderR * 0.35) + (0.25 * (Get-TanhSafe -X ($logTh * 0.7)))) / 1.40
        $hzNorm    = [Math]::Min(1.0, [Math]::Max(0.0, $hzRawNorm))
        $extHz     = [Math]::Round((7.83 + ($HzRangeSpan * $hzNorm * (0.80 + ($unitLock * 0.35))) + ($meanOmega * 2.25)), 3)

        if ($extMag -ge 2.60 -and $unitLock -ge 0.75) {
            $lastMode = 'SUC+INC-UNITY-LOCKED'
        }
        elseif ($unitLock -ge 0.55) {
            $lastMode = 'SUC+INC-UNITY-COUPLED'
        }
        else {
            $lastMode = 'SUC+INC-UNITY-SYNCING'
        }

        $pulseRaw = [string]::Format(
            $inv,
            'SUC+INC-UNITY|tick={0}|ts={1}|mode={2}|mag={3}|hz={4}|lock={5}|r={6}|th={7}|prev={8}',
            $tick, $tsIso, $lastMode, $extMag, $extHz, $unitLock, $orderR, $thetaInf, $lastHash
        )
        $lastHash = Get-Sha256Hex -Text $pulseRaw
        $pulseHashes.Add($lastHash)

        $magSum += $extMag; $hzSum += $extHz; $lockSum += $unitLock; $rSum += $orderR
        if ($extMag -gt $peakMag) { $peakMag = $extMag }
        if ($extHz -gt $peakHz) { $peakHz = $extHz }
        if ($orderR -gt $peakR) { $peakR = $orderR }

        Write-Host ("`r[tick {0}] {1} | S+I UNIT[MAG:{2:0.0000} | HZ:{3:0.000}Hz | LOCK:{4:0.0000}] | #{5}   " -f `
            $tick, $lastMode, $extMag, $extHz, $unitLock, $lastHash.Substring(0, 10)) -NoNewline -ForegroundColor Green

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

    $payload = [ordered]@{
        node                                = $NodeId
        platform                            = 'powershell-5.1'
        drive_anchor                        = 'C:'
        external_unit                       = 'SUC+INC-UNITY'
        external_unit_mode                  = $lastMode
        stop_trigger                        = $stopTag
        started_utc                         = $startedUtc
        stopped_utc                         = $endedUtc
        ticks                               = $tick
        unit_phase_lock_mean                = $meanLock
        external_spirit_magnitude_mean      = $meanMag
        external_spirit_magnitude_peak      = $peakMag
        external_spirit_frequency_hz_mean   = $meanHz
        external_spirit_frequency_hz_peak   = $peakHz
        kuramoto_order_r_mean               = $meanR
        kuramoto_order_r_peak               = $peakR
        kuramoto_theta_inf                  = $thetaInf
        unit_merkle_root                    = $merkleRoot
        last_pulse_hash                     = $lastHash
    }

    $compactPayload = $payload | ConvertTo-Json -Compress -Depth 6
    $payloadSha     = Get-Sha256Hex -Text $compactPayload

    $envelope = [ordered]@{
        schema                = 'suc-inc-unity-v1'
        immutable_append_only = $true
        payload_sha256        = $payloadSha
        payload               = $payload
    }

    $compactEnv = $envelope | ConvertTo-Json -Compress -Depth 8
    $prettyEnv  = $envelope | ConvertTo-Json -Depth 8

    foreach ($root in @($PrimaryDriveRoot, $SecondaryDriveRoot)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        Write-Utf8NoBom -Path (Join-Path -Path $root -ChildPath 'suc_inc_unity_ledger.jsonl') -Content $compactEnv -Append $true
        Write-Utf8NoBom -Path (Join-Path -Path $root -ChildPath 'suc_inc_unity_sealed.json') -Content $prettyEnv -Append $false
    }

    $receipt = [string]::Format(
        $inv,
        'C-SUC+INC-UNITY | ticks={0} | MAG:{1:0.00} HZ:{2:0.0} | THETA_INF:{3:0.00} | Root:{4}',
        $tick, $peakMag, $peakHz, $thetaInf, $merkleRoot.Substring(0, 12)
    )

    try {
        Set-Clipboard -Value $receipt -ErrorAction Stop
    }
    catch {
        Write-Warning ("Clipboard update skipped: {0}" -f $_.Exception.Message)
    }

    Write-Host "`n`n=== SEALED [$stopTag] (SUC+INC EXTERNAL UNIT :: C: DRIVE) ===" -ForegroundColor Green
    Write-Host ("Unified S+I Unit : mode={0} | lock_mean={1:0.0000}" -f $lastMode, $meanLock) -ForegroundColor Magenta
    Write-Host ("Spirit Mag & Freq: mag_mean={0:0.0000} mag_peak={1:0.0000} | hz_mean={2:0.000}Hz hz_peak={3:0.000}Hz" -f $meanMag, $peakMag, $meanHz, $peakHz) -ForegroundColor Cyan
    Write-Host ("Kuramoto Inf     : r_peak={0:0.0000} | theta_inf={1:0.0000}" -f $peakR, $thetaInf) -ForegroundColor Yellow
    Write-Host ("Unit Merkle Root : {0}" -f $merkleRoot) -ForegroundColor Green
    Write-Host ("Clipboard Receipt: {0}" -f $receipt) -ForegroundColor Yellow
}