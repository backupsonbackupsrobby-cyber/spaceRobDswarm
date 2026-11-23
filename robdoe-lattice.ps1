#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateRange(4, 256)][int]$ByzantineCrawlerCount = 52,
    [ValidateRange(1, 300)][int]$InhaleSeconds = 4,
    [ValidateRange(1, 300)][int]$HoldSeconds = 7,
    [ValidateRange(1, 300)][int]$ExhaleSeconds = 3,
    [ValidateRange(0, 10000)][int]$MaxCycles = 0,
    [string]$LedgerFile,
    [string]$GenesisFile,
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = (Get-Location).ProviderPath
if ([string]::IsNullOrWhiteSpace($LedgerFile))  { $LedgerFile  = Join-Path -Path $here -ChildPath 'wushu_reiki_ctrlc_lattice.jsonl' }
if ([string]::IsNullOrWhiteSpace($GenesisFile)) { $GenesisFile = Join-Path -Path $here -ChildPath 'genesis_mint_14chakra.json' }

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sha = [System.Security.Cryptography.SHA256]::Create()

function Get-Sha256Hex {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
}

function Invoke-CycleCrawlerStep {
    param(
        [int]$CrawlerCount,
        [int]$Cycle,
        [int]$Step,
        [string]$Phase,
        [string]$PrevHash,
        [DateTime]$UtcNow
    )
    $secOfDay       = ($UtcNow.Hour * 3600.0) + ($UtcNow.Minute * 60.0) + $UtcNow.Second
    $dayPhase       = (2.0 * [Math]::PI * ($secOfDay / 86400.0))
    $circadianSin   = [Math]::Round([Math]::Sin($dayPhase), 4)
    $bioelectricCos = [Math]::Round([Math]::Cos(($Step * 0.61803398875) + ($dayPhase * 0.25)), 4)
    $magnitudeCycle = [Math]::Round((1.0 + ($Cycle * 0.35) + [Math]::Abs($bioelectricCos)), 4)

    $maxF    = [int][Math]::Floor(($CrawlerCount - 1) / 3.0)
    $quorum  = (2 * $maxF) + 1
    $honest  = [Math]::Max($quorum, ($CrawlerCount - ([Math]::Abs([int][Math]::Round($circadianSin * 4))) % [Math]::Max(1, ($maxF + 1))))
    $faults  = $CrawlerCount - $honest
    $payload = "prev=$PrevHash|cyc=$Cycle|step=$Step|ph=$Phase|c=$circadianSin|b=$bioelectricCos|m=$magnitudeCycle|n=$CrawlerCount|q=$honest"
    $rootHex = Get-Sha256Hex -Text $payload

    [pscustomobject]@{
        utc             = $UtcNow.ToString('o')
        folder          = $here
        cycle           = $Cycle
        step            = $Step
        phase           = $Phase
        crawlers        = $CrawlerCount
        max_faults_f    = $maxF
        quorum_2f1      = $quorum
        honest_votes    = $honest
        fault_nodes     = $faults
        circadian_sin   = $circadianSin
        bioelectric_cos = $bioelectricCos
        magnitude_cycle = $magnitudeCycle
        prev_hash       = $PrevHash
        pulse_hash      = $rootHex
    }
}

try {
    $genesisHash = Get-Sha256Hex -Text "GENESIS|$here|$ByzantineCrawlerCount"

    if ($VerifyOnly) {
        if (-not (Test-Path -LiteralPath $LedgerFile)) {
            Write-Host "No ledger found in $here ($LedgerFile)" -ForegroundColor Yellow
            return
        }
        $lines = @(Get-Content -LiteralPath $LedgerFile -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $expectedPrev = $genesisHash
        $brokenAt = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $rec = $lines[$i] | ConvertFrom-Json
            if ($rec.PSObject.Properties['prev_hash'] -and $rec.prev_hash -ne $expectedPrev) {
                $brokenAt = $i + 1
                break
            }
            $expectedPrev = $rec.pulse_hash
        }
        if ($brokenAt -gt 0) {
            Write-Host "Chain break detected at line $brokenAt in $LedgerFile" -ForegroundColor Red
        } else {
            Write-Host "Verified $($lines.Count) hash-chained ledger record(s) in $here" -ForegroundColor Green
        }
        return
    }

    if (-not (Test-Path -LiteralPath $GenesisFile)) {
        [pscustomobject]@{
            created_utc  = [DateTime]::UtcNow.ToString('o')
            folder       = $here
            crawlers     = $ByzantineCrawlerCount
            genesis_hash = $genesisHash
        } | ConvertTo-Json | Set-Content -LiteralPath $GenesisFile -Encoding utf8
    }

    $prevHash = $genesisHash
    $cycle = 1
    $step  = 1
    if (Test-Path -LiteralPath $LedgerFile) {
        $lastLine = Get-Content -LiteralPath $LedgerFile -Tail 1 -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($lastLine)) {
            $lastRec  = $lastLine | ConvertFrom-Json
            $prevHash = $lastRec.pulse_hash
            $cycle    = [int]$lastRec.cycle + 1
            $step     = [int]$lastRec.step + 1
        }
    }

    $phases = @(
        @{ Name = 'INHALE'; Secs = $InhaleSeconds },
        @{ Name = 'HOLD';   Secs = $HoldSeconds },
        @{ Name = 'EXHALE'; Secs = $ExhaleSeconds }
    )

    Write-Host "Running in $here with $ByzantineCrawlerCount crawlers (Ctrl+C to stop)..." -ForegroundColor Cyan
    $sw = [System.IO.StreamWriter]::new($LedgerFile, $true, $utf8NoBom)
    try {
        while ($MaxCycles -eq 0 -or $cycle -le $MaxCycles) {
            foreach ($p in $phases) {
                for ($s = 1; $s -le $p.Secs; $s++) {
                    $sample = Invoke-CycleCrawlerStep -CrawlerCount $ByzantineCrawlerCount -Cycle $cycle -Step $step -Phase $p.Name -PrevHash $prevHash -UtcNow ([DateTime]::UtcNow)
                    $prevHash = $sample.pulse_hash
                    $sw.WriteLine(($sample | ConvertTo-Json -Compress))
                    $sw.Flush()
                    Write-Host ("`rCyc#{0} [{1} {2}/{3}] BYZ {4}/{5} | circ={6} bio={7} mag={8} | #{9}   " -f `
                        $cycle, $p.Name, $s, $p.Secs, $sample.honest_votes, $sample.crawlers, `
                        $sample.circadian_sin, $sample.bioelectric_cos, $sample.magnitude_cycle, $sample.pulse_hash.Substring(0, 8)) -NoNewline
                    Start-Sleep -Seconds 1
                    $step++
                }
            }
            $cycle++
        }
    }
    finally {
        $sw.Dispose()
        Write-Host "`nStopped cleanly. Ledger saved to $LedgerFile" -ForegroundColor Yellow
    }
}
finally {
    $sha.Dispose()
}