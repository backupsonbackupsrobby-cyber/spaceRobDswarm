# AUTOMATED NRF24L01+ TRANSCEIVER HARNESS WITH INCORPORATED PHYSICS LOGS
param (
    [string]$PortName = "COM6",
    [int]$BaudRate    = 115200
)

# Verify local JSON topology manifest
$ConfigPath = ".\telemetry_matrix_map.json"
if (-not (Test-Path $ConfigPath)) {
    Write-Host " [ERROR] Base mapping missing! Run master automation setup." -ForegroundColor Red
    return
}

$Manifest = Get-Content $ConfigPath | ConvertFrom-Json
$StreamArray = @()
foreach ($Circle in $Manifest.PSObject.Properties) { $StreamArray += $Circle.Value }

Write-Host "📡 Initializing CH340 Bridge on $PortName -> 6-inch Antenna Matrix..." -ForegroundColor Yellow
$SerialPort = New-Object System.IO.Ports.SerialPort $PortName, $BaudRate, None, 8, One
$SerialPort.WriteBufferSize = 65536

try {
    $SerialPort.Open()
    Write-Host " [ONLINE] Fast-Forward Streaming Active. Press Ctrl+C to stop.`n" -ForegroundColor Green
    
    $FrameIndex = 0
    while ($true) {
        $FrameIndex++
        $Timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $SelectedTag = $StreamArray[(Get-Random -Maximum 72)]
        
        # Rigid, compressed frame incorporating unified physics cycle flags
        $Packet = [PSCustomObject]@{
            idx  = $FrameIndex
            ts   = $Timestamp
            tag  = $SelectedTag
            wob  = 0.052                     # 0.052 week wobble token
            clk  = "1/7200"                  # 24-step clock denominator interval
            val  = [Math]::Round((Get-Random -Minimum 0.0 -Maximum 1.0), 5)
            flow = "FORWARD_ONLY"
        } | ConvertTo-Json -Compress
        
        $SerialPort.WriteLine($Packet)
        Write-Host " [TX] Frame #$FrameIndex | Tag: $SelectedTag | Payload: $Packet" -ForegroundColor Cyan
        Start-Sleep -Milliseconds 200
    }
} catch {
    Write-Host " [HARDWARE BYPASS] Port $PortName offline or busy. Maintaining linear processing flow." -ForegroundColor DarkYellow
} finally {
    if ($SerialPort -and $SerialPort.IsOpen) { $SerialPort.Close() }
}
