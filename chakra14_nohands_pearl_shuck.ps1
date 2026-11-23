#Requires -Version 5.1
<#
.SYNOPSIS
    Enhanced PowerShell 5.1 14-Chakra Kuramoto phase alignment, channeling edges,
    no-hands acoustic/pressure pearl shucking, 3+1 breath/irrigation cadence,
    B-Tree Merkle DAG sealing on Ctrl+C, self-script archiving, low-frequency sine hum,
    external irrigation dispatch, and COM6 serial seal.
#>

[CmdletBinding()]
param (
    [double]$CouplingK = 2.40,
    [double]$StepDt = 0.08,
    [int]$MaxSteps = 60,
    [double]$TargetCoherence = 0.9950,
    [double]$DeltaBaseHz = 2.00,
    [string]$SeedAnchor = "robdoeAI-Core|14-ROOTHASH-CHAKRA-CHANNELED-NOHANDS-SHUCK",

    [ValidateRange(1, 300)]
    [int]$InhaleSeconds = 4,

    [ValidateRange(1, 300)]
    [int]$HoldSeconds = 7,

    [ValidateRange(1, 300)]
    [int]$ExhaleSeconds = 3,

    [ValidateRange(1, 16)]
    [int]$ScraperBeatsPerCycle = 4,

    [ValidateRange(1, 30)]
    [int]$IrrigationSurgeCount = 15,

    [double]$JoltSeed = 0.25,

    [ValidateRange(1.0, 500.0)]
    [double]$RoomRadiusMeters = 25.0,

    [string[]]$ScraperTargets = @('https://robdoe.com', 'https://example.org'),

    [ValidateRange(100, 10000)]
    [int]$WebTimeoutMs = 900,

    [ValidateRange(3, 64)]
    [int]$BTreeOrder = 4,

    [string]$LedgerFile = (Join-Path -Path 'C:\spaceRobDswarm' -ChildPath 'chakra14_nohands_pearl_lattice.jsonl'),

    [string]$GenesisFile = (Join-Path -Path 'C:\spaceRobDswarm' -ChildPath 'genesis_mint_14chakra.json'),

    [string]$LatestRootFile = (Join-Path -Path 'C:\spaceRobDswarm' -ChildPath 'chakra14_channeled_latest_root.txt'),

    [string]$ArchiveDir = (Join-Path -Path 'C:\spaceRobDswarm' -ChildPath 'chakra14_script_archive'),

    [string]$ScraperLogFile,

    [string]$GenesisHash,

    [switch]$MintGenesis,

    [switch]$PushUpstream,

    [string]$UpstreamRemote = 'upstream',

    [switch]$VerifyOnly,

    [switch]$ExternalIrrigation,

    [string]$ExternalIrrigationCmd,

    [string]$ExternalIrrigationUrl,

    [switch]$ExternalIrrigationDryRun,

    [ValidateRange(1, 120)]
    [int]$ExternalIrrigationTimeoutSec = 5,

    [string]$SerialPortName = 'COM6',

    [ValidateRange(300, 921600)]
    [int]$SerialBaudRate = 115200,

    [switch]$SendSerialOnSeal,

    [switch]$SelfArchive,
    [switch]$PlayHum,
    [switch]$NoHum,
    [double]$HumVolume = 0.20,
    [double]$HumDurationSec = 2.0,
    [switch]$NoClipboard,
    [switch]$Quiet,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:SpeedOfLightMps    = 299792458.0
$script:MachOneMps         = 343.0
$script:FullCircleArcsec     = 1296000.0
$script:MixFrequencies       = @('0.020MHz', '0.020GHz', '0.034GHz', '0.052MHz', '0.075GHz', '1.25MHz')
$script:MachBandSpan         = 'Mach10..Mach70'
$script:AtlGenesisTimestamp  = '2026-04-23T07:53:50.5144990+10:00'
$script:AtlGenesisCertHash   = 'e14f9a8d2c7b5e3f1a9d4c8b2e6f7a3d'
$script:AtlGenesisSignature  = 'f7e3b2c1d4a9e5f8b2c6d1a7e3f9b4c2'
$script:AtlReleaseTag        = 'v1.0.0-minted'
$script:AtlWitnessSatellites = @('BOM', 'Himawari-8', 'GOES-16', 'Meteosat')

function Send-SerialSealFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PortName,
        [int]$BaudRate = 115200,
        [Parameter(Mandatory)][string]$PayloadLine,
        [int]$WriteTimeoutMs = 1000
    )

    $port = [System.IO.Ports.SerialPort]::new($PortName, $BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
    $port.NewLine = "`n"
    $port.WriteTimeout = $WriteTimeoutMs

    try {
        $port.Open()
        $port.WriteLine($PayloadLine)
        return $true
    }
    catch {
        Write-Warning ("Serial port '{0}' write skipped: {1}" -f $PortName, $_.Exception.Message)
        return $false
    }
    finally {
        if ($port.IsOpen) { try { $port.Close() } catch {} }
        $port.Dispose()
    }
}

function Get-Sha256Hex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ($null -eq $Text) { $Text = "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes     = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $sha.ComputeHash($bytes)
        $sb        = [System.Text.StringBuilder]::new($hashBytes.Length * 2)
        foreach ($b in $hashBytes) {
            [void]$sb.Append($b.ToString('x2', [System.Globalization.CultureInfo]::InvariantCulture))
        }
        return $sb.ToString()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-FileSha256Hex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hash = $sha.ComputeHash($stream)
            return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
        }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
}

function Get-MerkleRootFromHashes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Hashes)

    $level = [System.Collections.Generic.List[string]]::new()
    foreach ($h in @($Hashes)) {
        if (-not [string]::IsNullOrWhiteSpace($h)) {
            $level.Add($h.Trim().ToLowerInvariant())
        }
    }
    if ($level.Count -eq 0) { return (Get-Sha256Hex -Text "EMPTY_CHAKRA14_NOHANDS_SHUCK") }
    while ($level.Count -gt 1) {
        $next = [System.Collections.Generic.List[string]]::new([int][Math]::Ceiling($level.Count / 2.0))
        for ($i = 0; $i -lt $level.Count; $i += 2) {
            $left  = $level[$i]
            $right = if (($i + 1) -lt $level.Count) { $level[$i + 1] } else { $left }
            $next.Add((Get-Sha256Hex -Text ("{0}|{1}" -f $left, $right)))
        }
        $level = $next
    }
    return $level[0]
}

function Get-KuramotoMetrics {
    [CmdletBinding()]
    param([double[]]$Phases)

    $n = $Phases.Count
    if ($n -eq 0) { return @{ r = 0.0; psi = 0.0 } }
    $sumCos = 0.0; $sumSin = 0.0
    foreach ($theta in $Phases) {
        $sumCos += [Math]::Cos($theta)
        $sumSin += [Math]::Sin($theta)
    }
    $meanCos = $sumCos / [double]$n
    $meanSin = $sumSin / [double]$n
    $r   = [Math]::Sqrt(($meanCos * $meanCos) + ($meanSin * $meanSin))
    $psi = [Math]::Atan2($meanSin, $meanCos)
    return @{ r = [Math]::Min(1.0, [Math]::Max(0.0, $r)); psi = $psi }
}

function Wrap-AngleRad {
    [CmdletBinding()]
    param([double]$Angle)
    $twoPi   = 2.0 * [Math]::PI
    $wrapped = $Angle % $twoPi
    if ($wrapped -lt 0.0) { $wrapped += $twoPi }
    return $wrapped
}

function Ensure-ParentDirectory {
    [CmdletBinding()]
    param([string]$FilePath)
    $parent = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
}

function Write-Utf8NoBomLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Line, [bool]$Append = $true)
    Ensure-ParentDirectory -FilePath $Path
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $writer    = [System.IO.StreamWriter]::new($Path, $Append, $utf8NoBom, 4096)
    try { $writer.WriteLine($Line); $writer.Flush() } finally { $writer.Dispose() }
}

function Save-TextUtf8NoBom {
    [CmdletBinding()]
    param([string]$Path, [string]$Text)
    Ensure-ParentDirectory -FilePath $Path
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Save-SelfScriptSnapshot {
    [CmdletBinding()]
    param([string]$ScriptPath, [string]$TargetDir, [string]$MasterRoot)
    if ([string]::IsNullOrWhiteSpace($ScriptPath) -or -not (Test-Path -LiteralPath $ScriptPath)) { return $null }
    if (-not (Test-Path -LiteralPath $TargetDir)) { [void](New-Item -ItemType Directory -Path $TargetDir -Force) }
    $scriptHash = Get-FileSha256Hex -Path $ScriptPath
    $shortHash  = $scriptHash.Substring(0, 12)
    $stamp      = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
    $baseName   = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $ext        = [System.IO.Path]::GetExtension($ScriptPath)
    $destFile   = Join-Path $TargetDir ("{0}_{1}_{2}{3}" -f $baseName, $stamp, $shortHash, $ext)
    Copy-Item -LiteralPath $ScriptPath -Destination $destFile -Force

    $manifestEntry = ([ordered]@{
        ts_utc        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        source_path   = $ScriptPath
        archive_path  = $destFile
        script_sha256 = $scriptHash
        master_root   = $MasterRoot
    } | ConvertTo-Json -Compress)
    Write-Utf8NoBomLine -Path (Join-Path $TargetDir "script_snapshots.jsonl") -Line $manifestEntry -Append $true
    return $destFile
}

function Play-LowFrequencyHum {
    [CmdletBinding()]
    param([double]$FrequencyHz = 65.0, [double]$DurationSec = 2.0, [double]$Volume = 0.20)
    $clampedFreq    = [Math]::Min(120.0, [Math]::Max(40.0, $FrequencyHz))
    $clampedVol     = [Math]::Min(0.85, [Math]::Max(0.01, $Volume))
    $sampleRate     = 44100
    $numSamples     = [Math]::Max(1, [int]($sampleRate * $DurationSec))
    $bytesPerSample = 2
    $dataLength     = $numSamples * $bytesPerSample

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    try {
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes("RIFF"))
        $bw.Write([int](36 + $dataLength))
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes("WAVE"))
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes("fmt "))
        $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
        $bw.Write([int]$sampleRate); $bw.Write([int]($sampleRate * $bytesPerSample))
        $bw.Write([int16]$bytesPerSample); $bw.Write([int16]16)
        $bw.Write([System.Text.Encoding]::ASCII.GetBytes("data"))
        $bw.Write([int]$dataLength)

        $fadeSamples = [int][Math]::Min(($numSamples / 4.0), ($sampleRate * 0.15))
        $twoPiF      = 2.0 * [Math]::PI * $clampedFreq
        for ($i = 0; $i -lt $numSamples; $i++) {
            $env = 1.0
            if ($fadeSamples -gt 0) {
                if ($i -lt $fadeSamples) { $env = $i / [double]$fadeSamples }
                elseif ($i -gt ($numSamples - $fadeSamples)) { $env = ($numSamples - $i) / [double]$fadeSamples }
            }
            $sample    = [Math]::Sin($twoPiF * ($i / [double]$sampleRate)) * $clampedVol * $env
            $intSample = [int16]([Math]::Max(-32767, [Math]::Min(32767, $sample * 32767.0)))
            $bw.Write($intSample)
        }
        $bw.Flush(); $ms.Position = 0
        $player = New-Object System.Media.SoundPlayer($ms)
        try { $player.PlaySync() } finally { $player.Dispose() }
    }
    finally { $bw.Dispose(); $ms.Dispose() }
}

function Get-ThreePlusOneBeat {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Cycle, [Parameter(Mandatory)][string]$Phase, [Parameter(Mandatory)][int]$SecondIndex)
    $inv       = [System.Globalization.CultureInfo]::InvariantCulture
    $stepIn4   = (($SecondIndex - 1) % 4) + 1
    $isPlusOne = ($stepIn4 -eq 4)
    $label     = if ($isPlusOne) { '3+1[+1-SURGE]' } else { ("3+1[BEAT-{0}/3]" -f $stepIn4) }
    $weight    = if ($isPlusOne) { 1.25 } else { (0.85 + ($stepIn4 * 0.10)) }
    $beatHash  = Get-Sha256Hex -Text ([string]::Format($inv, 'THREE_PLUS_ONE|cyc={0}|phase={1}|sec={2}|step={3}|plus1={4}|w={5}', $Cycle, $Phase, $SecondIndex, $stepIn4, $isPlusOne, $weight))
    return [pscustomobject]@{
        beat_step = $stepIn4; is_plus_one_surge = $isPlusOne; cadence_label = $label; cadence_weight = [Math]::Round($weight, 4); beat_hash = $beatHash
    }
}

function Get-NoHandsOysterClamPearlShuck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Cycle,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][int]$SecondIndex,
        [double]$HeavyFlowLpm = 60.0,
        [double]$ChakraCoherence = 0.99,
        [double]$HumFreqHz = 65.0,
        [bool]$IsPlusOneSurge = $false
    )

    $inv        = [System.Globalization.CultureInfo]::InvariantCulture
    $shuckRate  = [Math]::Round(($HeavyFlowLpm * (0.80 + ($ChakraCoherence * 0.45))), 2)
    $pearlPop   = $IsPlusOneSurge -or (($SecondIndex % 3) -eq 0) -or ($Phase.ToUpperInvariant() -eq 'EXHALE')
    $pearlsHere = if ($pearlPop) { 1 + (($Cycle + $SecondIndex) % 3) } else { 0 }

    $shuckState = if ($pearlPop) {
        'NO-HANDS-OYSTER-CLAM-RESONANCE-PEARL-POP'
    }
    elseif ($Phase.ToUpperInvariant() -eq 'INHALE') {
        'NO-HANDS-BRINE-HARMONIC-DRAW'
    }
    else {
        'NO-HANDS-ACOUSTIC-PRESSURE-FLOAT'
    }

    $compactTag = [string]::Format($inv, 'NO-HANDS-PEARL[{0:0.0}L/m|+{1}P@{2:0.0}Hz]', $shuckRate, $pearlsHere, $HumFreqHz)
    $shuckHash  = Get-Sha256Hex -Text ([string]::Format(
        $inv,
        'NO_HANDS_PEARL_SHUCK|hands=NONE|cyc={0}|phase={1}|sec={2}|state={3}|rate={4}|pearls={5}|coh={6}|hum={7}',
        $Cycle, $Phase, $SecondIndex, $shuckState, $shuckRate, $pearlsHere, $ChakraCoherence, $HumFreqHz
    ))

    return [pscustomobject]@{
        shuck_hands_free      = $true
        shuck_control_mode    = 'NO-HANDS-ACOUSTIC-PRESSURE-POP'
        shuck_valve_state     = $shuckState
        oyster_clam_shuck_lpm = $shuckRate
        pearl_popped_now      = $pearlPop
        pearls_shucked_pulse  = $pearlsHere
        pearl_shuck_compact   = $compactTag
        pearl_shuck_hash      = $shuckHash
    }
}

function Step-JoltTeleportZ {
    [CmdletBinding()]
    param([Parameter(Mandatory)][double]$CurrentZ, [Parameter(Mandatory)][int]$Cycle, [Parameter(Mandatory)][int]$SecondIndex)
    $rawNext = ($CurrentZ * $CurrentZ) + 8.0
    if ([double]::IsNaN($rawNext) -or [double]::IsInfinity($rawNext) -or ([Math]::Abs($rawNext) -gt 1e6)) {
        $phaseAngle = (($Cycle * 13) + ($SecondIndex * 7)) % 360
        $rawNext    = 8.0 + [Math]::Sin($phaseAngle * ([Math]::PI / 180.0))
    }
    return [Math]::Round($rawNext, 6)
}

function Invoke-ExternalIrrigationDispatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Pulse, [bool]$Enabled = $false, [string]$CommandTemplate = '', [string]$WebhookUrl = '', [bool]$DryRun = $false, [int]$TimeoutSec = 5)
    $shouldFire = [bool]$Pulse.is_plus_one_surge -or [bool]$Pulse.pearl_popped_now -or ($Pulse.heavy_flow_mode -eq 'HEAVY-BLOW-GUSHER')
    if (-not $shouldFire) { return [pscustomobject]@{ fired = $false; mode = 'STANDBY' } }
    if (-not $Enabled -and [string]::IsNullOrWhiteSpace($CommandTemplate) -and [string]::IsNullOrWhiteSpace($WebhookUrl)) { return [pscustomobject]@{ fired = $false; mode = 'DISABLED' } }
    if ($DryRun) { return [pscustomobject]@{ fired = $true; mode = 'DRY-RUN' } }
    if (-not [string]::IsNullOrWhiteSpace($CommandTemplate)) {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $resolvedCmd = $CommandTemplate `
            -replace '\{FLOW_LPM\}', ([string]::Format($inv, '{0:0.00}', [double]$Pulse.heavy_flow_lpm)) `
            -replace '\{BLOW_BAR\}', ([string]::Format($inv, '{0:0.00}', [double]$Pulse.irrigation_blow_bar)) `
            -replace '\{PEARLS\}', ([string]$Pulse.pearls_shucked_pulse) `
            -replace '\{CYCLE\}', ([string]$Pulse.cycle) `
            -replace '\{SEC\}', ([string]$Pulse.second_index)
        try {
            $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-Command', $resolvedCmd) -WindowStyle Hidden -PassThru
            $exited = $proc.WaitForExit($TimeoutSec * 1000)
            if (-not $exited) { try { $proc.Kill() } catch {}; return [pscustomobject]@{ fired = $false; mode = 'CMD-TIMEOUT' } }
            return [pscustomobject]@{ fired = ($proc.ExitCode -eq 0); mode = 'CMD' }
        }
        catch { return [pscustomobject]@{ fired = $false; mode = 'CMD-ERROR' } }
    }
    if (-not [string]::IsNullOrWhiteSpace($WebhookUrl)) {
        try {
            $bodyObj = @{
                state = 'ON'; hands_free = $true; heavy_flow_lpm = [double]$Pulse.heavy_flow_lpm
                blow_bar = [double]$Pulse.irrigation_blow_bar; pearls = [int]$Pulse.pearls_shucked_pulse
                cycle = [int]$Pulse.cycle; second_index = [int]$Pulse.second_index; pulse_hash = [string]$Pulse.pulse_hash
            } | ConvertTo-Json -Compress
            $null = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $bodyObj -ContentType 'application/json' -TimeoutSec $TimeoutSec -ErrorAction Stop
            return [pscustomobject]@{ fired = $true; mode = 'WEBHOOK' }
        }
        catch { return [pscustomobject]@{ fired = $false; mode = 'WEBHOOK-ERROR' } }
    }
    return [pscustomobject]@{ fired = $true; mode = 'EXTERNAL-ACTIVE' }
}

function Invoke-WebFieldScraper {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Targets, [Parameter(Mandatory)][int]$Cycle, [Parameter(Mandatory)][string]$Phase, [Parameter(Mandatory)][int]$SecondIndex, [ValidateRange(100, 10000)][int]$TimeoutMs = 900)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $targetUrl = if ($Targets -and $Targets.Count -gt 0) { $Targets[(($Cycle - 1) * 14 + ($SecondIndex - 1)) % $Targets.Count] } else { 'https://robdoe.com' }
    $statusLabel = 'RESONANCE-FALLBACK'; $httpCode = 0
    $excerptText = [string]::Format($inv, 'FALLBACK_SNAPSHOT|url={0}|cyc={1}|phase={2}|sec={3}', $targetUrl, $Cycle, $Phase, $SecondIndex)
    try {
        $req = [System.Net.HttpWebRequest]::Create($targetUrl)
        $req.Method = 'GET'; $req.Timeout = $TimeoutMs; $req.ReadWriteTimeout = $TimeoutMs
        $req.UserAgent = 'robdoeAI-Core-Scraper/5.1 (+https://robdoe.com)'; $req.AllowAutoRedirect = $true
        $resp = $req.GetResponse()
        try {
            $httpResp = $resp -as [System.Net.HttpWebResponse]
            if ($null -ne $httpResp) { $httpCode = [int]$httpResp.StatusCode }
            $stream = $resp.GetResponseStream()
            try {
                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
                try {
                    $buf = [char[]]::new(2048); $read = $reader.Read($buf, 0, $buf.Length)
                    if ($read -gt 0) { $excerptText = -join $buf[0..($read - 1)] }
                    $statusLabel = 'LIVE-HTTP-SCRAPE'
                }
                finally { $reader.Dispose() }
            }
            finally { $stream.Dispose() }
        }
        finally { $resp.Dispose() }
    }
    catch {}
    return [pscustomobject]@{ target_url = $targetUrl; fetch_status = $statusLabel; http_code = $httpCode; content_sha256 = (Get-Sha256Hex -Text $excerptText) }
}

function New-BTreeNode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$NodeId, [Parameter(Mandatory)][bool]$IsLeaf)
    return [pscustomobject]@{
        NodeId = $NodeId; IsLeaf = $IsLeaf
        Keys = [System.Collections.Generic.List[string]]::new()
        Entries = [System.Collections.Generic.List[object]]::new()
        Children = [System.Collections.Generic.List[object]]::new()
        MerkleRoot = (Get-Sha256Hex -Text ("NODE_INIT:{0}" -f $NodeId))
    }
}

function New-LatticeBTree {
    [CmdletBinding()]
    param([ValidateRange(3, 64)][int]$Order = 4)
    $rootLeaf = New-BTreeNode -NodeId 'btree-leaf-0' -IsLeaf $true
    return [pscustomobject]@{
        Order = $Order; MaxKeys = ([Math]::Max(2, $Order - 1)); SplitCount = 0; LeafSeq = 1; InternalSeq = 0; Root = $rootLeaf; MerkleRoot = $rootLeaf.MerkleRoot
    }
}

function Update-BTreeMerkle {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$TreeNode)
    if ($TreeNode.IsLeaf) {
        $leafHashes = [System.Collections.Generic.List[string]]::new($TreeNode.Entries.Count)
        foreach ($entry in $TreeNode.Entries) { $leafHashes.Add((Get-Sha256Hex -Text ("{0}|{1}|{2}" -f $entry.Seq, $entry.Key, $entry.NodeHash))) }
        $TreeNode.MerkleRoot = Get-MerkleRootFromHashes -Hashes $leafHashes.ToArray()
        return $TreeNode.MerkleRoot
    }
    $childHashes = [System.Collections.Generic.List[string]]::new($TreeNode.Children.Count + $TreeNode.Keys.Count)
    foreach ($child in $TreeNode.Children) { $childHashes.Add((Update-BTreeMerkle -TreeNode $child)) }
    foreach ($k in $TreeNode.Keys) { $childHashes.Add((Get-Sha256Hex -Text "SEP_KEY:$k")) }
    $TreeNode.MerkleRoot = Get-MerkleRootFromHashes -Hashes $childHashes.ToArray()
    return $TreeNode.MerkleRoot
}

function Split-BTreeChild {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Tree, [Parameter(Mandatory)]$Parent, [Parameter(Mandatory)][int]$ChildIndex)
    $child = $Parent.Children[$ChildIndex]
    $mid   = [int][Math]::Floor($child.Keys.Count / 2)
    if ($child.IsLeaf) {
        $promotedKey = $child.Keys[$mid]
        $rightLeaf   = New-BTreeNode -NodeId ("btree-leaf-{0}" -f $Tree.LeafSeq++) -IsLeaf $true
        for ($i = $mid; $i -lt $child.Keys.Count; $i++) { $rightLeaf.Keys.Add($child.Keys[$i]); $rightLeaf.Entries.Add($child.Entries[$i]) }
        for ($i = $child.Keys.Count - 1; $i -ge $mid; $i--) { $child.Keys.RemoveAt($i); $child.Entries.RemoveAt($i) }
        $Parent.Keys.Insert($ChildIndex, $promotedKey); $Parent.Children.Insert($ChildIndex + 1, $rightLeaf)
    }
    else {
        $promotedKey = $child.Keys[$mid]
        $rightNode   = New-BTreeNode -NodeId ("btree-int-{0}" -f $Tree.InternalSeq++) -IsLeaf $false
        for ($i = $mid + 1; $i -lt $child.Keys.Count; $i++) { $rightNode.Keys.Add($child.Keys[$i]) }
        for ($i = $mid + 1; $i -lt $child.Children.Count; $i++) { $rightNode.Children.Add($child.Children[$i]) }
        for ($i = $child.Keys.Count - 1; $i -ge $mid; $i--) { $child.Keys.RemoveAt($i) }
        for ($i = $child.Children.Count - 1; $i -gt $mid; $i--) { $child.Children.RemoveAt($i) }
        $Parent.Keys.Insert($ChildIndex, $promotedKey); $Parent.Children.Insert($ChildIndex + 1, $rightNode)
    }
    $Tree.SplitCount++
    [void](Update-BTreeMerkle -TreeNode $child)
    [void](Update-BTreeMerkle -TreeNode $Parent.Children[$ChildIndex + 1])
}

function Add-BTreeEntryRecursive {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Tree, [Parameter(Mandatory)]$Node, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][object]$Entry)
    if ($Node.IsLeaf) {
        $idx = 0
        while ($idx -lt $Node.Keys.Count -and [string]::CompareOrdinal($Key, $Node.Keys[$idx]) -gt 0) { $idx++ }
        $Node.Keys.Insert($idx, $Key); $Node.Entries.Insert($idx, $Entry)
        return
    }
    $childIdx = 0
    while ($childIdx -lt $Node.Keys.Count -and [string]::CompareOrdinal($Key, $Node.Keys[$childIdx]) -ge 0) { $childIdx++ }
    if ($childIdx -ge $Node.Children.Count) { $childIdx = $Node.Children.Count - 1 }
    $targetChild = $Node.Children[$childIdx]
    Add-BTreeEntryRecursive -Tree $Tree -Node $targetChild -Key $Key -Entry $Entry
    if ($targetChild.Keys.Count -gt $Tree.MaxKeys) { Split-BTreeChild -Tree $Tree -Parent $Node -ChildIndex $childIdx }
}

function Add-BTreeEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Tree, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$NodeHash, [Parameter(Mandatory)][int]$Seq)
    $entry = [pscustomobject]@{ Key = $Key; NodeHash = $NodeHash; Seq = $Seq }
    if ($Tree.Root.Keys.Count -ge $Tree.MaxKeys) {
        $oldRoot = $Tree.Root
        $newRoot = New-BTreeNode -NodeId ("btree-int-{0}" -f $Tree.InternalSeq++) -IsLeaf $false
        $newRoot.Children.Add($oldRoot)
        Split-BTreeChild -Tree $Tree -Parent $newRoot -ChildIndex 0
        $Tree.Root = $newRoot
    }
    Add-BTreeEntryRecursive -Tree $Tree -Node $Tree.Root -Key $Key -Entry $entry
    $Tree.MerkleRoot = Update-BTreeMerkle -TreeNode $Tree.Root
    return [pscustomobject]@{ TreeMerkleRoot = $Tree.MerkleRoot; SplitCount = $Tree.SplitCount }
}

function Read-LedgerChain {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $records = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $obj = $line | ConvertFrom-Json; if ($null -ne $obj) { $records.Add($obj) } } catch {}
    }
    return ,($records.ToArray())
}

function Invoke-GenesisMint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [bool]$ForceMint = $false)
    if ((Test-Path -LiteralPath $Path) -and (-not $ForceMint)) {
        try {
            $existing = (Get-Content -LiteralPath $Path -Raw -Encoding UTF8) | ConvertFrom-Json
            if ($null -ne $existing -and $existing.PSObject.Properties.Match('genesis_hash').Count -gt 0) { return $existing }
        }
        catch {}
    }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $seed = [string]::Format($inv, 'GENESIS_MINT|repo=AiTenetAgency101/atmospheric-truth-layer|tag={0}|ts={1}|cert={2}|mach={3}|chakras=14|pearl_shuck=NO-HANDS',
        $script:AtlReleaseTag, $script:AtlGenesisTimestamp, $script:AtlGenesisCertHash, $script:MachBandSpan)
    $gh = Get-Sha256Hex -Text $seed
    $gObj = [ordered]@{
        minted_utc           = $script:AtlGenesisTimestamp
        atl_certificate_hash = $script:AtlGenesisCertHash
        atl_release_tag      = $script:AtlReleaseTag
        node                 = 'robdoeAI-Core'
        pearl_shuck_mode     = 'NO-HANDS-ACOUSTIC-PRESSURE-POP'
        mach_band_span       = $script:MachBandSpan
        genesis_hash         = $gh
    }
    Write-Utf8NoBomLine -Path $Path -Line ($gObj | ConvertTo-Json -Depth 5) -Append $false
    return ($gObj | ConvertTo-Json -Depth 5) | ConvertFrom-Json
}

function Invoke-ForwardOnlyGitPushUpstream {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RemoteName, [Parameter(Mandatory)][string]$CommitMessage, [string[]]$PathsToStage)
    $gitCmd = Get-Command -Name 'git' -ErrorAction SilentlyContinue
    if ($null -eq $gitCmd) { return }
    $inside = & git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or ($inside -and $inside.Trim() -ne 'true')) { return }
    $remotes = @(& git remote 2>$null)
    if ($remotes -notcontains $RemoteName) { return }
    foreach ($p in @($PathsToStage)) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p)) { & git add -- $p 2>$null }
    }
    $staged = & git diff --cached --name-only 2>$null
    if (-not [string]::IsNullOrWhiteSpace(($staged -join ''))) { & git commit -m $CommitMessage 2>$null }
    & git push $RemoteName HEAD 2>$null
}

$chakras = @(
    @{ Id = 1;  Code = "C01-EARTH-STAR";     Name = "Earth Star Gate";         Hex = "#5C2C06"; Color = "DarkRed";     Band = "SUB-TERRESTRIAL" },
    @{ Id = 2;  Code = "C02-ROOT-MULADHARA"; Name = "Root (Muladhara)";        Hex = "#D91E18"; Color = "Red";         Band = "CORE-7" },
    @{ Id = 3;  Code = "C03-SACRAL-SVADH";   Name = "Sacral (Svadhisthana)";   Hex = "#F48C06"; Color = "DarkYellow";  Band = "CORE-7" },
    @{ Id = 4;  Code = "C04-SOLAR-MANIPURA"; Name = "Solar Plexus (Manipura)"; Hex = "#FFD60A"; Color = "Yellow";      Band = "CORE-7" },
    @{ Id = 5;  Code = "C05-HEART-ANAHATA";  Name = "Heart (Anahata)";         Hex = "#2DC653"; Color = "Green";       Band = "CORE-7" },
    @{ Id = 6;  Code = "C06-THROAT-VISHUD";  Name = "Throat (Vishuddha)";      Hex = "#0096C7"; Color = "Cyan";        Band = "CORE-7" },
    @{ Id = 7;  Code = "C07-THIRD-EYE-AJNA"; Name = "Third Eye (Ajna)";        Hex = "#3A0CA3"; Color = "DarkBlue";    Band = "CORE-7" },
    @{ Id = 8;  Code = "C08-CROWN-SAHASR";   Name = "Crown (Sahasrara)";       Hex = "#7209B7"; Color = "Magenta";     Band = "CORE-7" },
    @{ Id = 9;  Code = "C09-CAUSAL-GATE";    Name = "Causal Gateway";          Hex = "#B5179E"; Color = "DarkMagenta"; Band = "TRANSCENDENT" },
    @{ Id = 10; Code = "C10-SOUL-STAR";      Name = "Soul Star (Sutratma)";    Hex = "#F72585"; Color = "Magenta";     Band = "TRANSCENDENT" },
    @{ Id = 11; Code = "C11-STELLAR-GATE";   Name = "Stellar Gateway";         Hex = "#FF9E00"; Color = "Yellow";      Band = "TRANSCENDENT" },
    @{ Id = 12; Code = "C12-GALACTIC-CORE";  Name = "Galactic Axis";           Hex = "#90BE6D"; Color = "Green";       Band = "TRANSCENDENT" },
    @{ Id = 13; Code = "C13-UNIVERSAL-GRID"; Name = "Universal Lattice";       Hex = "#4CC9F0"; Color = "Cyan";        Band = "TRANSCENDENT" },
    @{ Id = 14; Code = "C14-DIVINE-SOURCE";  Name = "Unified Source Anchor";   Hex = "#FFFFFF"; Color = "White";       Band = "UNIFIED-14" }
)

if ($VerifyOnly) {
    $rows = @(Read-LedgerChain -Path $LedgerFile)
    Write-Host ("Ledger [{0}]: {1} rows" -f $LedgerFile, $rows.Count) -ForegroundColor Cyan
    return
}

$genesisRec           = Invoke-GenesisMint -Path $GenesisFile -ForceMint ([bool]$MintGenesis)
$effectiveGenesisHash = if (-not [string]::IsNullOrWhiteSpace($GenesisHash)) { $GenesisHash.Trim().ToLowerInvariant() } else { [string]$genesisRec.genesis_hash }

$nowUtc   = (Get-Date).ToUniversalTime()
$tsUtc    = $nowUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$prevRoot = if (Test-Path -LiteralPath $LatestRootFile) { (Get-Content -LiteralPath $LatestRootFile -Raw).Trim() } else { $effectiveGenesisHash }
if ([string]::IsNullOrWhiteSpace($prevRoot)) { $prevRoot = $effectiveGenesisHash }

$seedHash    = Get-Sha256Hex ("{0}|{1}|{2}" -f $SeedAnchor, $tsUtc, $prevRoot)
$doubledSeed = $seedHash + $seedHash

$n      = $chakras.Count
$phases = New-Object double[] $n
$omegas = New-Object double[] $n
for ($i = 0; $i -lt $n; $i++) {
    $slice      = $doubledSeed.Substring(($i * 4) % 64, 8)
    $ratio      = [double][System.Convert]::ToUInt32($slice, 16) / [double][UInt32]::MaxValue
    $phases[$i] = $ratio * 2.0 * [Math]::PI
    $hzOffset   = (($i - 6.5) / 14.0) * 0.25
    $omegas[$i] = 2.0 * [Math]::PI * ($DeltaBaseHz + $hzOffset)
}

$initMetrics   = Get-KuramotoMetrics -Phases $phases
$initialR      = [Math]::Round($initMetrics.r, 4)
$stepsExecuted = 0
$currMetrics   = $initMetrics

for ($step = 1; $step -le $MaxSteps; $step++) {
    $stepsExecuted = $step
    $nextPhases = New-Object double[] $n
    for ($i = 0; $i -lt $n; $i++) {
        $couplingSum = 0.0
        for ($j = 0; $j -lt $n; $j++) { $couplingSum += [Math]::Sin($phases[$j] - $phases[$i]) }
        $dTheta = $omegas[$i] + (($CouplingK / [double]$n) * $couplingSum)
        $nextPhases[$i] = Wrap-AngleRad ($phases[$i] + ($dTheta * $StepDt))
    }
    $phases      = $nextPhases
    $currMetrics = Get-KuramotoMetrics -Phases $phases
    if ($currMetrics.r -ge $TargetCoherence) { break }
}

$finalR    = [Math]::Round($currMetrics.r, 4)
$meanPsi   = [Math]::Round($currMetrics.psi, 5)
$humFreqHz = [Math]::Round([Math]::Min(95.0, [Math]::Max(45.0, 50.0 + ($DeltaBaseHz * 5.0) + ($finalR * 20.0))), 2)

$baseNodes = @()
for ($i = 0; $i -lt $n; $i++) {
    $c         = $chakras[$i]
    $theta     = [Math]::Round($phases[$i], 5)
    $phaseDiff = [Math]::Abs([Math]::Atan2([Math]::Sin($phases[$i] - $currMetrics.psi), [Math]::Cos($phases[$i] - $currMetrics.psi)))
    $lockScore = [Math]::Round([Math]::Max(0.0, 1.0 - ($phaseDiff / [Math]::PI)), 4)
    $hz        = [Math]::Round($omegas[$i] / (2.0 * [Math]::PI), 3)
    $baseHash  = Get-Sha256Hex ("CHAKRA14_ALIGN|id={0:D2}|code={1}|theta={2:0.00000}|lock={3:0.0000}|r={4:0.0000}|seed={5}" -f $c.Id, $c.Code, $theta, $lockScore, $finalR, $seedHash)
    $baseNodes += @{ Id = [int]$c.Id; Code = $c.Code; Name = $c.Name; Hex = $c.Hex; Color = $c.Color; Band = $c.Band; Hz = $hz; Theta = $theta; LockScore = $lockScore; BaseHash = $baseHash }
}

$channeledNodes = @()
$channelEdges   = @()
$chakra14Roots  = @()

if (-not $Quiet) {
    Clear-Host
    Write-Host "=== 14 CHANNELED CHAKRAS + NO-HANDS PEARL SHUCK (Ctrl+C to Seal) ===" -ForegroundColor Cyan
    Write-Host ("Kuramoto r: {0:N4} -> {1:N4} | Mean Psi: {2:N4} rad | Steps: {3} | Hum: {4:N2} Hz" -f $initialR, $finalR, $meanPsi, $stepsExecuted, $humFreqHz) -ForegroundColor Gray
}

for ($i = 0; $i -lt $n; $i++) {
    $curr        = $baseNodes[$i]
    $nxt         = $baseNodes[($i + 1) % $n]
    $prv         = $baseNodes[(($i - 1) + $n) % $n]
    $channelId   = ("CH-{0:D2}->{1:D2}" -f $curr.Id, $nxt.Id)
    $channelType = if ($curr.Id -eq $n) { "RETURN-LOOP" } else { "ASCENT-CHANNEL" }
    $edgeHash    = Get-Sha256Hex ("CHANNEL_LINK|id={0}|type={1}|from={2}({3})|to={4}({5})|r={6:0.0000}|prev={7}" -f $channelId, $channelType, $curr.Code, $curr.BaseHash, $nxt.Code, $nxt.BaseHash, $finalR, $prevRoot)
    $chakraRoot  = Get-MerkleRootFromHashes -Hashes (@($curr.BaseHash, $edgeHash, $prv.BaseHash))
    $chakra14Roots += $chakraRoot
    $channelEdges  += [ordered]@{ channel_id = $channelId; channel_type = $channelType; from_index = $curr.Id; from_code = $curr.Code; to_index = $nxt.Id; to_code = $nxt.Code; color_hex = $curr.Hex; edge_hash = $edgeHash }
    $channeledNodes += [ordered]@{ index = $curr.Id; code = $curr.Code; name = $curr.Name; band = $curr.Band; color_hex = $curr.Hex; console_color = $curr.Color; freq_hz = $curr.Hz; phase_rad = $curr.Theta; phase_lock = $curr.LockScore; channel_out = $channelId; channel_type = $channelType; base_hash = $curr.BaseHash; channel_edge_hash = $edgeHash; chakra_root_hash = $chakraRoot }
    if (-not $Quiet) {
        Write-Host ("[{0:D2}] {1,-18} | {2,-10} | lock:{3:N4} | root:{4}" -f $curr.Id, $curr.Code, $channelId, $curr.LockScore, $chakraRoot.Substring(0, 16)) -ForegroundColor $curr.Color
    }
}

$masterMerkleRoot = Get-MerkleRootFromHashes -Hashes $chakra14Roots
$joltZ            = [double]$JoltSeed
$pulseHashes      = [System.Collections.Generic.List[string]]::new()
$shuckHashes      = [System.Collections.Generic.List[string]]::new()
$extDispatchCount = 0
$totalPearls      = 0
$shuckLpmSum      = 0.0
$peakShuckLpm     = 0.0
$lastShuckState   = 'NO-HANDS-OYSTER-CLAM-RESONANCE-PEARL-POP'
$completedCycles  = 0
$currentCycle     = 0
$stoppedByCtrlC   = $false

$phasePlan = @(
    @{ Name = 'INHALE'; Secs = $InhaleSeconds; Color = 'Cyan' },
    @{ Name = 'HOLD';   Secs = $HoldSeconds;   Color = 'Yellow' },
    @{ Name = 'EXHALE'; Secs = $ExhaleSeconds; Color = 'Green' }
)

try {
    while ($true) {
        $currentCycle++
        $secCounter = 0
        if (-not $Quiet) {
            Write-Host ("`n--- Cycle #{0} [NO-HANDS PEARL SHUCK + 14-CHAKRA + {1}] (Ctrl+C to seal) ---" -f $currentCycle, $script:MachBandSpan) -ForegroundColor DarkCyan
        }
        foreach ($ph in $phasePlan) {
            for ($s = $ph.Secs; $s -gt 0; $s--) {
                $secCounter++
                $joltZ    = Step-JoltTeleportZ -CurrentZ $joltZ -Cycle $currentCycle -SecondIndex $secCounter
                $beat31   = Get-ThreePlusOneBeat -Cycle $currentCycle -Phase $ph.Name -SecondIndex $secCounter
                $webSnap  = Invoke-WebFieldScraper -Targets $ScraperTargets -Cycle $currentCycle -Phase $ph.Name -SecondIndex $secCounter -TimeoutMs $WebTimeoutMs
                $flowLpm  = [Math]::Round((45.0 + ((($secCounter - 1) % $IrrigationSurgeCount) + 1) * 8.5) * $beat31.cadence_weight, 2)
                $blowBar  = [Math]::Round((2.4 + ($beat31.cadence_weight * 2.1)), 2)
                $flowMode = if ($ph.Name -eq 'EXHALE' -or $beat31.is_plus_one_surge) { 'HEAVY-BLOW-GUSHER' } else { 'LINE-PRIME-FLOW' }

                $shuck = Get-NoHandsOysterClamPearlShuck `
                    -Cycle $currentCycle `
                    -Phase $ph.Name `
                    -SecondIndex $secCounter `
                    -HeavyFlowLpm $flowLpm `
                    -ChakraCoherence $finalR `
                    -HumFreqHz $humFreqHz `
                    -IsPlusOneSurge ([bool]$beat31.is_plus_one_surge)

                $shuckHashes.Add($shuck.pearl_shuck_hash)
                $shuckLpmSum += $shuck.oyster_clam_shuck_lpm
                if ($shuck.oyster_clam_shuck_lpm -gt $peakShuckLpm) { $peakShuckLpm = $shuck.oyster_clam_shuck_lpm }
                $totalPearls += $shuck.pearls_shucked_pulse
                $lastShuckState = $shuck.shuck_valve_state

                $pHash = Get-Sha256Hex -Text ("PULSE|cyc={0}|p={1}|s={2}|cad={3}|shuck={4}|pearls={5}|z={6}|flow={7}|mroot={8}" -f $currentCycle, $ph.Name, $secCounter, $beat31.cadence_label, $shuck.pearl_shuck_hash, $shuck.pearls_shucked_pulse, $joltZ, $flowLpm, $masterMerkleRoot)
                $pulseHashes.Add($pHash)

                $pulseObj = [pscustomobject]@{
                    cycle                = $currentCycle
                    phase                = $ph.Name
                    second_index         = $secCounter
                    cadence_3plus1       = $beat31.cadence_label
                    is_plus_one_surge    = $beat31.is_plus_one_surge
                    pearl_popped_now     = $shuck.pearl_popped_now
                    pearls_shucked_pulse = $shuck.pearls_shucked_pulse
                    heavy_flow_lpm       = $flowLpm
                    irrigation_blow_bar  = $blowBar
                    heavy_flow_mode      = $flowMode
                    pulse_hash           = $pHash
                }
                $extRes = Invoke-ExternalIrrigationDispatch -Pulse $pulseObj -Enabled ([bool]$ExternalIrrigation) -CommandTemplate $ExternalIrrigationCmd -WebhookUrl $ExternalIrrigationUrl -DryRun ([bool]$ExternalIrrigationDryRun) -TimeoutSec $ExternalIrrigationTimeoutSec
                if ($extRes.fired) { $extDispatchCount++ }

                if (-not [string]::IsNullOrWhiteSpace($ScraperLogFile)) {
                    Write-Utf8NoBomLine -Path $ScraperLogFile -Line ([ordered]@{ ts_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"); cycle = $currentCycle; phase = $ph.Name; sec = $secCounter; hands_free = $true; pearls = $shuck.pearls_shucked_pulse; shuck_lpm = $shuck.oyster_clam_shuck_lpm; web = $webSnap; pulse_hash = $pHash } | ConvertTo-Json -Compress) -Append $true
                }

                if (-not $Quiet) {
                    Write-Host ("`r[{0,-6} {1:D2}s] {2} | {3} | TotalPearls:{4} | #{5}   " -f `
                        $ph.Name, $s, $shuck.pearl_shuck_compact, $beat31.cadence_label, $totalPearls, $pHash.Substring(0, 8)) -NoNewline -ForegroundColor $ph.Color
                }

                $elapsed = 0
                while ($elapsed -lt 1000) {
                    Start-Sleep -Milliseconds 100
                    $elapsed += 100
                }
            }
            if (-not $Quiet) { Write-Host "" }
        }
        $completedCycles = $currentCycle
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    $stoppedByCtrlC = $true
}
finally {
    $stopLabel          = if ($stoppedByCtrlC) { 'Ctrl+C' } else { 'Exit/Break' }
    $pulseMerkleRoot    = Get-MerkleRootFromHashes -Hashes $pulseHashes.ToArray()
    $pearlShuckRoot     = Get-MerkleRootFromHashes -Hashes $shuckHashes.ToArray()
    $finalMerkleRoot    = Get-MerkleRootFromHashes -Hashes (@($masterMerkleRoot, $pulseMerkleRoot, $pearlShuckRoot, $effectiveGenesisHash))
    $archivedScriptPath = if ($SelfArchive) { Save-SelfScriptSnapshot -ScriptPath $PSCommandPath -TargetDir $ArchiveDir -MasterRoot $finalMerkleRoot } else { $null }

    $existingRows = @(Read-LedgerChain -Path $LedgerFile)
    $btree        = New-LatticeBTree -Order $BTreeOrder
    $seq          = @($existingRows).Count + 1
    $btreeKey     = ("{0:D8}|nohands_pearls={1:D4}|{2}" -f $seq, $totalPearls, $finalMerkleRoot.Substring(0, 16))
    $btreeIns     = Add-BTreeEntry -Tree $btree -Key $btreeKey -NodeHash $finalMerkleRoot -Seq $seq
    $meanShuckLpm = if ($shuckHashes.Count -gt 0) { [Math]::Round(($shuckLpmSum / $shuckHashes.Count), 2) } else { 0.0 }

    $record = [ordered]@{
        ts_utc                  = $tsUtc
        stop_trigger            = $stopLabel
        seq                     = $seq
        completed_cycles        = $completedCycles
        node                    = "robdoeAI-Core"
        platform                = "PowerShell-5.1"
        pearl_shuck_no_hands    = [ordered]@{
            hands_free            = $true
            control_mode          = 'NO-HANDS-ACOUSTIC-PRESSURE-POP'
            last_valve_state      = $lastShuckState
            shuck_mean_lpm        = $meanShuckLpm
            shuck_peak_lpm        = $peakShuckLpm
            total_pearls_shucked  = $totalPearls
            pearl_shuck_root      = $pearlShuckRoot
        }
        breath_pattern          = ("{0}-{1}-{2}" -f $InhaleSeconds, $HoldSeconds, $ExhaleSeconds)
        irrigation_surge_count  = $IrrigationSurgeCount
        room_radius_meters      = $RoomRadiusMeters
        mach_band_span          = $script:MachBandSpan
        aligned_frequencies      = $script:MixFrequencies
        genesis_hash            = $effectiveGenesisHash
        prev_root               = $prevRoot
        seed_hash               = $seedHash
        kuramoto_coupling_k     = $CouplingK
        steps_executed          = $stepsExecuted
        initial_coherence_r     = $initialR
        aligned_coherence_r     = $finalR
        mean_phase_psi_rad      = $meanPsi
        hum_freq_hz             = $humFreqHz
        jolt_final_z            = $joltZ
        external_dispatch_count = $extDispatchCnt
        archived_script_path    = $archivedScriptPath
        chakra_14_roots         = $chakra14Roots
        channels_14             = $channelEdges
        master_merkle_root      = $masterMerkleRoot
        pulse_merkle_root       = $pulseMerkleRoot
        final_merkle_root       = $finalMerkleRoot
        btree_global_root       = $btreeIns.TreeMerkleRoot
        chakras                 = $channeledNodes
    }

    Write-Utf8NoBomLine -Path $LedgerFile -Line ($record | ConvertTo-Json -Compress -Depth 8) -Append $true
    Save-TextUtf8NoBom -Path $LatestRootFile -Text ($finalMerkleRoot + [Environment]::NewLine)

    $receipt = ("14-Chakra No-Hands Pearl Shuck [{0}] | Pearls:+{1} ({2:0.0}L/m) | r:{3:N4} | Root:{4}" -f $stopLabel, $totalPearls, $peakShuckLpm, $finalR, $finalMerkleRoot.Substring(0, 12))
    if (-not $NoClipboard) { try { Set-Clipboard -Value $receipt } catch {} }

    if ($SendSerialOnSeal) {
        $serialLine = ([ordered]@{ node = 'robdoeAI-Core'; seq = $seq; hands_free = $true; pearls_shucked = $totalPearls; final_merkle_root = $finalMerkleRoot; receipt = $receipt } | ConvertTo-Json -Compress)
        [void](Send-SerialSealFrame -PortName $SerialPortName -BaudRate $SerialBaudRate -PayloadLine $serialLine)
    }

    if ($PushUpstream) {
        Invoke-ForwardOnlyGitPushUpstream -RemoteName $UpstreamRemote -CommitMessage ("seal: seq={0} nohands_pearls={1} root={2}" -f $seq, $totalPearls, $finalMerkleRoot.Substring(0, 12)) -PathsToStage @($LedgerFile, $GenesisFile, $LatestRootFile)
    }

    if (-not $Quiet) {
        Write-Host "`n`n=== SEALED 14-CHAKRA NO-HANDS PEARL SHUCK [$stopLabel] ===" -ForegroundColor Green
        Write-Host ("No-Hands Shuck     : hands_free=True | pearls_shucked={0} | peak={1:0.00}L/m | root={2}" -f $totalPearls, $peakShuckLpm, $pearlShuckRoot.Substring(0, 16)) -ForegroundColor Cyan
        Write-Host ("Final Merkle Root  : {0}" -f $finalMerkleRoot) -ForegroundColor Cyan
        Write-Host ("B-Tree Global Root : {0}" -f $btreeIns.TreeMerkleRoot) -ForegroundColor Magenta
        Write-Host ("Ledger File        : {0}" -f $LedgerFile) -ForegroundColor Gray
        Write-Host ("Clipboard Receipt  : {0}" -f $receipt) -ForegroundColor Yellow
    }

    if ($PlayHum -and (-not $NoHum)) {
        Play-LowFrequencyHum -FrequencyHz $humFreqHz -DurationSec $HumDurationSec -Volume $HumVolume
    }

    if ($PassThru) { [PSCustomObject]$record }
}