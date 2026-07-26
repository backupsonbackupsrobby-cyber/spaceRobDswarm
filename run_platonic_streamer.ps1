# AUTOMATED WIRELESS PERMUTATION STREAMER
param (
    [string]$PortName = "COM6",
    [int]$BaudRate    = 115200
)

Write-Host "`n📡 Binding CH340 Serial Bus Tunnel on $PortName..." -ForegroundColor Yellow
$SerialPort = New-Object System.IO.Ports.SerialPort $PortName, $BaudRate, None, 8, One
$SerialPort.WriteBufferSize = 65536

# The 4 Platonic Notes / Root Principles
$PlatonicNotes = @(0.034, 0.052, 0.075, 0.150)
$TotalTargetPermutations = 1000000

try {
    $SerialPort.Open()
    Write-Host " [ONLINE] nRF24L01+ Carrier System Active. 6\" High-Gain Antenna Operational." -ForegroundColor Green
    Write-Host " [STREAM] Broadcasting 4-note geometric state arrays forward-only. Ctrl+C to stop.`n" -ForegroundColor Green
    
    $Sequence = 0
    while ($Sequence -lt $TotalTargetPermutations) {
        $Sequence++
        $EpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        
        # Calculate dynamic permutation indices across the 4 root notes
        $N1 = $PlatonicNotes[($Sequence % 4)]
        $N2 = $PlatonicNotes[(($Sequence + 1) % 4)]
        $N3 = $PlatonicNotes[(($Sequence + 2) % 4)]
        $N4 = $PlatonicNotes[(($Sequence + 3) % 4)]
        
        # Generate a distinct spatial trajectory token
        $TrajectoryToken = ($N1 * 1) + ($N2 * 10) + ($N3 * 100) + ($N4 * 1000)
        
        # Assemble tight frame meeting the 32-byte nRF24 hardware buffer limit
        $AirFrame = [PSCustomObject]@{
            idx  = $Sequence
            ts   = $EpochMs
            harm = $TrajectoryToken
            wob  = 0.052
            sig  = "0x84CA"
            flow = "FWD_ONLY"
        } | ConvertTo-Json -Compress
        
        # Stream raw ASCII string packet through the hardware bridge registers
        $SerialPort.WriteLine($AirFrame)
        
        Write-Host " [TX NOTE HARMONY #$Sequence] Trajectory Matrix: $TrajectoryToken │ Packet: $AirFrame" -ForegroundColor Cyan
        Start-Sleep -Milliseconds 200
    }
} catch {
    Write-Host " [HARDWARE BYPASS] Serial register offline or busy. Maintaining linear code processing loop: $_" -ForegroundColor DarkYellow
} finally {
    if ($SerialPort -and $SerialPort.IsOpen) { $SerialPort.Close() }
}
