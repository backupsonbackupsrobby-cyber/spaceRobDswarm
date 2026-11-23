#Requires -Version 5.1
param(
    [ValidateRange(4, 256)][int]$Crawlers = 52,
    [ValidateRange(1, 300)][int]$Inhale = 4,
    [ValidateRange(1, 300)][int]$Hold = 7,
    [ValidateRange(1, 300)][int]$Exhale = 3,
    [switch]$Verify
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here     = (Get-Location -PSProvider FileSystem).ProviderPath
$ledger   = Join-Path -Path $here -ChildPath 'wushu_reiki_ctrlc_lattice.jsonl'
$gen      = Join-Path -Path $here -ChildPath 'genesis_mint_14chakra.json'
$sealFile = Join-Path -Path $here -ChildPath 'sealed_14chakra.json'
$encNoBom = [System.Text.UTF8Encoding]::new($false)

$chakras14 = @(
    @{ Id = 'C01'; Name = 'Root' },
    @{ Id = 'C02'; Name = 'Sacral' },
    @{ Id = 'C03'; Name = 'SolarPlexus' },
    @{ Id = 'C04'; Name = 'Heart' },
    @{ Id = 'C05'; Name = 'Throat' },
    @{ Id = 'C06'; Name = 'ThirdEye' },
    @{ Id = 'C07'; Name = 'Crown' },
    @{ Id = 'C08'; Name = 'SoulStar' },
    @{ Id = 'C09'; Name = 'StellarGateway' },
    @{ Id = 'C10'; Name = 'UniversalHeart' },
    @{ Id = 'C11'; Name = 'GalacticCenter' },
    @{ Id = 'C12'; Name = 'CosmicChrist' },
    @{ Id = 'C13'; Name = 'DivineBlueprint' },
    @{ Id = 'C14'; Name = 'TranscendentCrown' }
)

function Sha256([string]$s) {
    $h = [System.Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))) -replace '-', '').ToLowerInvariant() }
    finally { $h.Dispose() }
}

function Append-Jsonl([string]$Path, [string]$JsonLine) {
    $sw = [System.IO.StreamWriter]::new($Path, $true, $encNoBom)
    try { $sw.WriteLine($JsonLine) } finally { $sw.Dispose() }
}

if ($Verify) {
    if (-not (Test-Path -LiteralPath $ledger)) {
        Write-Host "No ledger found in: $here" -ForegroundColor Yellow
        return
    }
    $lines = @([System.IO.File]::ReadAllLines($ledger, $encNoBom))
    $hasSeal = Test-Path -LiteralPath $sealFile
    Write-Host "Verified $($lines.Count) record(s) in: $here | Sealed file present: $hasSeal" -ForegroundColor Green
    if ($hasSeal) {
        Get-Content -LiteralPath $sealFile -Raw -Encoding UTF8
    }
    return
}

$genesisHash = Sha256 "14CHAKRA_GENESIS|$here|$Crawlers"
if (-not (Test-Path -LiteralPath $gen)) {
    @{
        folder         = $here
        crawlers       = $Crawlers
        chakras_active = 14
        genesis        = $genesisHash
    } | ConvertTo-Json | Set-Content -LiteralPath $gen -Encoding UTF8
}

$maxF   = [int][Math]::Floor(($Crawlers - 1) / 3.0)
$quorum = (2 * $maxF) + 1
$cycle  = 1
$step   = 1
$phases = @(
    @{ N = 'INHALE'; S = $Inhale },
    @{ N = 'HOLD';   S = $Hold },
    @{ N = 'EXHALE'; S = $Exhale }
)

$script:stopRequested = $false
$cancelHandler = [System.ConsoleCancelEventHandler]{
    param($sender, $e)
    $e.Cancel = $true
    $script:stopRequested = $true
}
[System.Console]::add_CancelKeyPress($cancelHandler)

$sessionHashes = [System.Collections.Generic.List[string]]::new()
$startedUtc    = [DateTime]::UtcNow.ToString('o')
$lastChakra    = 'C01:Root'
$lastCirc      = 0.0
$lastBio       = 0.0
$lastMag       = 1.0

Write-Host "Active Folder: $here | 14 Chakras + $Crawlers Crawlers (quorum >= $quorum) | Press Ctrl+C to SEAL" -ForegroundColor Cyan

try {
    while (-not $script:stopRequested) {
        foreach ($p in $phases) {
            if ($script:stopRequested) { break }
            for ($i = 1; $i -le $p.S; $i++) {
                if ($script:stopRequested) { break }

                $now    = [DateTime]::UtcNow
                $dayP   = (2.0 * [Math]::PI * ((($now.Hour * 3600) + ($now.Minute * 60) + $now.Second) / 86400.0))
                $circ   = [Math]::Round([Math]::Sin($dayP), 4)
                $bio    = [Math]::Round([Math]::Cos(($step * 0.61803398875) + ($dayP * 0.25)), 4)
                $mag    = [Math]::Round((1.0 + ($cycle * 0.35) + [Math]::Abs($bio)), 4)
                $honest = [Math]::Max($quorum, ($Crawlers - ([Math]::Abs([int][Math]::Round($circ * 4))) % [Math]::Max(1, ($maxF + 1))))

                $chIdx  = (($step - 1) + ($cycle - 1)) % 14
                $chakra = $chakras14[$chIdx]
                $align  = [Math]::Round([Math]::Min(1.0, [Math]::Max(0.0, (((($circ + 1.0) * 0.5) * 0.35) + ([Math]::Abs($bio) * 0.35) + ([Math]::Min(1.0, ($mag / 5.0)) * 0.30)))), 4)
                $cHash  = Sha256 "14CHAKRA|$here|c=$cycle|s=$step|$($chakra.Id):$($chakra.Name)|align=$align|$circ|$bio|$mag|$honest/$Crawlers"

                $lastChakra = "$($chakra.Id):$($chakra.Name)"
                $lastCirc   = $circ
                $lastBio    = $bio
                $lastMag    = $mag
                $sessionHashes.Add($cHash)

                $row = [pscustomobject]@{
                    record_type = 'PULSE'
                    utc         = $now.ToString('o')
                    folder      = $here
                    cycle       = $cycle
                    step        = $step
                    chakra_id   = $chakra.Id
                    chakra_name = $chakra.Name
                    chakra_align= $align
                    crawlers    = $Crawlers
                    honest      = $honest
                    quorum      = $quorum
                    circadian   = $circ
                    bioelectric = $bio
                    magnitude   = $mag
                    chakra_hash = $cHash
                } | ConvertTo-Json -Compress

                Append-Jsonl -Path $ledger -JsonLine $row

                Write-Host ("`rCyc#{0} [{1} {2}/{3}] {4}:{5}({6:0.00}) BFT {7}/{8} circ={9} bio={10} mag={11} #{12}   " -f `
                    $cycle, $p.N, $i, $p.S, $chakra.Id, $chakra.Name, $align, $honest, $Crawlers, $circ, $bio, $mag, $cHash.Substring(0, 8)) -NoNewline

                for ($ms = 0; $ms -lt 1000 -and (-not $script:stopRequested); $ms += 100) {
                    Start-Sleep -Milliseconds 100
                }
                $step++
            }
        }
        $cycle++
    }
}
finally {
    try { [System.Console]::remove_CancelKeyPress($cancelHandler) } catch {}

    $stoppedUtc   = [DateTime]::UtcNow.ToString('o')
    $trigger      = if ($script:stopRequested) { 'CTRL+C' } else { 'COMPLETED' }
    $chainBlob    = ($sessionHashes.ToArray() -join '|')
    $sessionRoot  = Sha256 "SESSION_ROOT|$genesisHash|$here|$trigger|$startedUtc|$stoppedUtc|$chainBlob"
    $chakra14Seal = Sha256 "14CHAKRA_FINAL_SEAL|$sessionRoot|$lastChakra|$lastCirc|$lastBio|$lastMag|$($sessionHashes.Count)"

    $sealObj = [ordered]@{
        record_type       = 'SEAL'
        stop_trigger      = $trigger
        folder            = $here
        started_utc       = $startedUtc
        stopped_utc       = $stoppedUtc
        genesis_hash      = $genesisHash
        session_pulses    = $sessionHashes.Count
        last_cycle        = $cycle
        last_step         = ([Math]::Max(0, $step - 1))
        last_chakra       = $lastChakra
        last_circadian    = $lastCirc
        last_bioelectric  = $lastBio
        last_magnitude    = $lastMag
        crawlers          = $Crawlers
        quorum_2f1        = $quorum
        session_root_hash = $sessionRoot
        final_seal_hash   = $chakra14Seal
    }

    $sealJsonCompact = $sealObj | ConvertTo-Json -Compress
    $sealJsonPretty  = $sealObj | ConvertTo-Json -Depth 4

    Append-Jsonl -Path $ledger -JsonLine $sealJsonCompact
    [System.IO.File]::WriteAllText($sealFile, $sealJsonPretty, $encNoBom)

    Write-Host "`n`n=== SEALED ($trigger) ===" -ForegroundColor Green
    Write-Host "Folder          : $here"
    Write-Host "Session Pulses  : $($sessionHashes.Count)"
    Write-Host "Last Chakra     : $lastChakra | circ=$lastCirc bio=$lastBio mag=$lastMag"
    Write-Host "Session Root    : $sessionRoot" -ForegroundColor Cyan
    Write-Host "Final 14C Seal  : $chakra14Seal" -ForegroundColor Magenta
    Write-Host "Ledger & Seal   : $ledger | $sealFile"
}