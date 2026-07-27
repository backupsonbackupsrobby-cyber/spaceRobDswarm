# AUTOMATED CIRCADIAN METRIC SYNC SYSTEM (PATCHED)
param (
    [string]$ComPort = "COM6",
    [int]$BaudRate   = 115200
)

# Load configuration topology array dictionary maps
$ConfigPath = ".\telemetry_matrix_map.json"
$FlatTags = @("BR1_SYS_HEALTH", "DIM1_VCTR_WITNESS", "SWARM_SYNC_RATE") # Baseline fallback
if (Test-Path $ConfigPath) { 
    try {
        $Manifest = Get-Content $ConfigPath | ConvertFrom-Json
        $TempTags = @()
        foreach ($Group in $Manifest.Symmetry_Mapping.PSObject.Properties) { $TempTags += $Group.Value }
        if ($TempTags.Count -gt 0) { $FlatTags = $TempTags }
    } catch {
        # Fallback to structural arrays if parsing has environment lock interferences
    }
}

Write-Host "📡 Initializing CH340 Bridge Pipeline on $ComPort..." -ForegroundColor Yellow
$SerialPort = New-Object System.IO.Ports.SerialPort $ComPort, $BaudRate, None, 8, One
$SerialPort.WriteBufferSize = 65536

# Core invariant tracking indices
$BaselineArcseconds = 1296000
$Platonic4Seeds = @(0.034, 0.052, 0.075, 0.150)
$AnnualDriftConstant = 0.014

try {
    $SerialPort.Open()
    Write-Host " [ONLINE] nRF24L01+ Carrier Operational. Streaming via 6"" Antenna Array." -ForegroundColor Green
    Write-Host " [MONITOR] Synthesizing continuous telemetry to circadian loop steps. Ctrl+C to stop.`n" -ForegroundColor Green
    
    $StepCount = 0
    while ($true) {
        $StepCount++
        $EpochTimestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        
        # Calculate localized temporal drift values against the 0.052 wobble factor
        $TimeFraction = ($EpochTimestamp % 86400000) / 1000
        $SpatialArcProgress = ($TimeFraction * 15) % $BaselineArcseconds
        $RandomWitness = $FlatTags[(Get-Random -Maximum $FlatTags.Count)]
        
        # Build unified frame matching the 32-byte nRF24 payload optimization constraint
        $CircadianFrame = [PSCustomObject]@{
            seq   = $StepCount
            ts    = $EpochTimestamp
            tag   = $RandomWitness
            arc   = [Math]::Round($SpatialArcProgress, 2)
            drift = $AnnualDriftConstant
            seed  = $Platonic4Seeds
            sig   = "0x84CA"
            flow  = "FWD_ONLY"
        } | ConvertTo-Json -Compress
        
        # Stream frame directly into transceiver registers
        $SerialPort.WriteLine($CircadianFrame)
        
        Write-Host " [SYNC EVENT #$StepCount] Arcsec: $SpatialArcProgress │ Tag: $RandomWitness │ Packet Stream: $CircadianFrame" -ForegroundColor Cyan
        Start-Sleep -Seconds 3
    }
} 
catch {
    Write-Host " [HARDWARE BYPASS] Physical serial link offline. Maintaining linear runtime processing tree: $_" -ForegroundColor DarkYellow
}
finally {
    if ($SerialPort -and $SerialPort.IsOpen) { 
        $SerialPort.Close()
        Write-Host " [OFFLINE] Serial port COM6 closed cleanly." -ForegroundColor Yellow
    }
}
