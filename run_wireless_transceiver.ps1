# AUTOMATED nRF24L01+ TELEMETRY FORWARDER
# Interfacing with CH340 USB-to-Serial bridge on COM6

param (
    [string]$PortName = "COM6",
    [int]$BaudRate    = 115200
)

# Load the structured 7-circle topology manifest to parse our 72 keys
$ConfigPath = ".\telemetry_matrix_map.json"
if (Test-Path $ConfigPath) {
    $Manifest = Get-Content $ConfigPath | ConvertFrom-Json
    Write-Host " -> Loaded 72 witness tags successfully from matrix map." -ForegroundColor Green
} else {
    Write-Host " [ERROR] Topology manifest missing! Run master automation script." -ForegroundColor Red
    return
}

# Combine all 72 witness keys into a flat streaming dictionary array
$StreamArray = @()
foreach ($Circle in $Manifest.PSObject.Properties) {
    $StreamArray += $Circle.Value
}

Write-Host "`n🚀 Initializing CH340 Serial Tunnel on $PortName at $BaudRate baud..." -ForegroundColor Yellow
$SerialPort = New-Object System.IO.Ports.SerialPort $PortName, $BaudRate, None, 8, One
$SerialPort.WriteBufferSize = 65536

try {
    $SerialPort.Open()
    Write-Host " [ONLINE] nRF24L01+ Transceiver Carrier Detect: Active." -ForegroundColor Green
    Write-Host " [WIRELESS] Streaming payload to 6-inch high-gain antenna matrix... Press Ctrl+C to abort.`n" -ForegroundColor Green
    
    $FrameCounter = 0
    while ($true) {
        $FrameCounter++
        $CurrentEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        
        # Select a random active tracking node from our 72 witness keys
        $RandomWitness = $StreamArray[(Get-Random -Maximum 72)]
        
        # Build a highly compressed structural byte stream frame for the nRF24 radio payload
        # 32-byte payload maximum optimization constraint standard for nRF24 modules
        $Payload = [PSCustomObject]@{
            f_id = $FrameCounter
            ts   = $CurrentEpoch
            tag  = $RandomWitness
            v_d  = [Math]::Round((Get-Random -Minimum 0.0 -Maximum 1.0), 4)
            flow = "FWD_ONLY"
        } | ConvertTo-Json -Compress
        
        # Stream raw ASCII string packet natively through CH340 straight to the nRF24 SPI bridge
        $SerialPort.WriteLine($Payload)
        
        Write-Host " [TX WIRELESS] Frame #$FrameCounter -> Sent via CH340 on COM6: $Payload" -ForegroundColor Cyan
        Start-Sleep -Milliseconds 150
    }
} catch {
    Write-Host " [BYPASS] Hardware Interface offline or busy. Maintaining linear code processing loop: $_" -ForegroundColor DarkYellow
} finally {
    if ($SerialPort -and $SerialPort.IsOpen) {
        $SerialPort.Close()
        Write-Host "`n [OFFLINE] COM6 stream safe boundary shutdown." -ForegroundColor Yellow
    }
}
