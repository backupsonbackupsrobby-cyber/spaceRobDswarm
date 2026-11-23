#Requires -Version 5.1
<#
.SYNOPSIS
    PowerShell 5.1 forward-only SHA-256 Merkle witness lattice, B-Tree key indexer,
    and COM6 serial seal for robdoeAI-Core.
#>

[CmdletBinding()]
param (
    [string]$NodeName = 'robdoeAI-Core',
    [string]$SeedAnchor = 'robdoeAI-Core|PS51-FORWARD-LATTICE',
    [string]$LedgerFile = 'C:\spaceRobDswarm\robdoe_witness_ledger.jsonl',
    [string]$LatestRootFile = 'C:\spaceRobDswarm\robdoe_latest_root.txt',
    [string]$SerialPortName = 'COM6',
    [ValidateRange(300, 921600)]
    [int]$SerialBaudRate = 115200,
    [switch]$SendSerial,
    [switch]$NoClipboard,
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

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

function Get-MerkleRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Hashes)

    $level = [System.Collections.Generic.List[string]]::new()
    foreach ($h in @($Hashes)) {
        if (-not [string]::IsNullOrWhiteSpace($h)) {
            $level.Add($h.Trim().ToLowerInvariant())
        }
    }
    if ($level.Count -eq 0) {
        return (Get-Sha256Hex -Text 'EMPTY_MERKLE_LEVEL')
    }
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

function Write-Utf8NoBomLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Line,
        [bool]$Append = $true
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $writer    = [System.IO.StreamWriter]::new($Path, $Append, $utf8NoBom, 4096)
    try {
        $writer.WriteLine($Line)
        $writer.Flush()
    }
    finally {
        $writer.Dispose()
    }
}

function Send-SerialFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PortName,
        [int]$BaudRate = 115200,
        [Parameter(Mandatory)][string]$PayloadLine
    )

    $port = [System.IO.Ports.SerialPort]::new(
        $PortName,
        $BaudRate,
        [System.IO.Ports.Parity]::None,
        8,
        [System.IO.Ports.StopBits]::One
    )
    $port.NewLine = "`n"
    $port.WriteTimeout = 1000

    try {
        $port.Open()
        $port.WriteLine($PayloadLine)
        return $true
    }
    catch {
        Write-Warning ("Serial port '{0}' skipped: {1}" -f $PortName, $_.Exception.Message)
        return $false
    }
    finally {
        if ($port.IsOpen) {
            try { $port.Close() } catch {}
        }
        $port.Dispose()
    }
}

function Show-NodeWitness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Node,
        [Parameter(Mandatory)][int]$Seq,
        [Parameter(Mandatory)][string]$RootHex,
        [Parameter(Mandatory)][string]$TsUtc
    )

    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host (" NODE WITNESS : {0} | SEQ #{1}" -f $Node, $Seq) -ForegroundColor Cyan
    Write-Host (" TIMESTAMP    : {0}" -f $TsUtc) -ForegroundColor Gray
    Write-Host (" MERKLE ROOT  : {0}" -f $RootHex) -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor DarkCyan
}

function Read-LedgerRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $rows = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            if ($null -ne $obj) { $rows.Add($obj) }
        }
        catch {}
    }
    return ,($rows.ToArray())
}

$existing = @(Read-LedgerRows -Path $LedgerFile)
if ($VerifyOnly) {
    Write-Host ("Ledger [{0}] has {1} sealed entries." -f $LedgerFile, $existing.Count) -ForegroundColor Cyan
    if ($existing.Count -gt 0) {
        $last = $existing[$existing.Count - 1]
        Write-Host ("Latest root: {0}" -f $last.merkle_root) -ForegroundColor Green
    }
    return
}

$tsUtc    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$seq      = $existing.Count + 1
$prevRoot = if (Test-Path -LiteralPath $LatestRootFile) {
    (Get-Content -LiteralPath $LatestRootFile -Raw).Trim()
}
else {
    Get-Sha256Hex -Text ("GENESIS|{0}|{1}" -f $NodeName, $SeedAnchor)
}
if ([string]::IsNullOrWhiteSpace($prevRoot)) {
    $prevRoot = Get-Sha256Hex -Text ("GENESIS|{0}|{1}" -f $NodeName, $SeedAnchor)
}

$lanes = 1..8 | ForEach-Object {
    Get-Sha256Hex -Text ("{0}|seq={1}|lane={2}|prev={3}|ts={4}" -f $SeedAnchor, $seq, $_, $prevRoot, $tsUtc)
}
$merkleRoot = Get-MerkleRoot -Hashes (@($prevRoot) + @($lanes))

$entry = [ordered]@{
    seq         = $seq
    ts_utc      = $tsUtc
    node        = $NodeName
    ps_version  = $PSVersionTable.PSVersion.ToString()
    prev_root   = $prevRoot
    merkle_root = $merkleRoot
    lane_count  = @($lanes).Count
}

Write-Utf8NoBomLine -Path $LedgerFile -Line ($entry | ConvertTo-Json -Compress) -Append $true
Write-Utf8NoBomLine -Path $LatestRootFile -Line $merkleRoot -Append $false

$receipt = ("{0} | SEQ #{1} | ROOT {2}" -f $NodeName, $seq, $merkleRoot.Substring(0, 16))
if (-not $NoClipboard) {
    try { Set-Clipboard -Value $receipt } catch {}
}

if ($SendSerial) {
    $serialPayload = ([ordered]@{
        node        = $NodeName
        seq         = $seq
        merkle_root = $merkleRoot
        ts_utc      = $tsUtc
    } | ConvertTo-Json -Compress)
    [void](Send-SerialFrame -PortName $SerialPortName -BaudRate $SerialBaudRate -PayloadLine $serialPayload)
}

Show-NodeWitness -Node $NodeName -Seq $seq -RootHex $merkleRoot -TsUtc $tsUtc
Write-Host ("Ledger   : {0}" -f $LedgerFile) -ForegroundColor Gray
Write-Host ("Receipt  : {0}" -f $receipt) -ForegroundColor Yellow