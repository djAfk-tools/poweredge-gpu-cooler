# PowerEdgeGPUCooler.ps1
# Copyright (c) 2025 djAfk
# Licensed under the MIT License with No-Sale Restriction (see LICENSE file)
# Scales fan speed based on max of GPU and CPU temps using ipmitool (remote)
# Auto-elevates to run as Administrator if not already elevated

# Function to check if running as Administrator
function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# If not running as admin, relaunch with elevation
if (-not (Test-Admin)) {
    Write-Host "Script requires Administrator privileges. Attempting to elevate..."
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-File `"$scriptPath`"" -Wait
    exit
}

# Configuration
$nvidiaSmiPath = "C:\Windows\System32\nvidia-smi.exe"
$ipmiToolPath = "C:\Program Files\Dell\SysMgt\bmc\ipmitool.exe"
# $showCommands = $true  # Uncomment for command output
$showCommands = $false  # Set to $true to show command execution

# IPMI connection options (comment out for local use)
$ipmiRemoteArgs = "-I lanplus -H 192.168.1.250"
$ipmiUsername = "-U root"
$ipmiPassword = "-P calvin"
# Combine args for ipmitool commands
$ipmiArgs = "$ipmiRemoteArgs $ipmiUsername $ipmiPassword"

# GPU Temperature thresholds
$gpuLowerLimit = 42  # Below this, no GPU-based control
$gpuUpperLimit = 85  # At or above this, 100%

# CPU Temperature thresholds
$cpuLowerLimit = 60  # Below this, no CPU-based control
$cpuUpperLimit = 80  # At or above this, 100%

# Fan speed range (same for GPU and CPU calculations)
$minFanSpeed = 40   # Starting at 40% above lower limits
$maxFanSpeed = 100  # Reaching 100% at upper limits

# Polling interval (seconds)
$interval = 30

# Track last command(s)
$lastCommand = ""

Write-Host "Starting PowerEdge GPU Cooler script (running as Administrator). Press Ctrl+C to stop."

while ($true) {
    # Get GPU temperatures
    $tempOutput = & $nvidiaSmiPath --query-gpu=temperature.gpu --format=csv,noheader
    $gpuTemps = $tempOutput | ForEach-Object { [int]$_.Trim() }
    $gpuTemp = ($gpuTemps | Measure-Object -Maximum).Maximum

    # Get CPU temperatures via ipmitool
    $cpuTempOutput = Start-Process -FilePath $ipmiToolPath -ArgumentList "$ipmiArgs sdr type Temperature" -NoNewWindow -Wait -RedirectStandardOutput "cpu_temp.txt" -PassThru
    $cpuTempsRaw = Get-Content "cpu_temp.txt" -ErrorAction SilentlyContinue
    Remove-Item "cpu_temp.txt" -ErrorAction SilentlyContinue

    # Parse CPU temps (assuming "Temp" lines are CPU1 and CPU2)
    $tempLines = $cpuTempsRaw | Where-Object { $_ -match "^Temp\s" }
    $cpu1Temp = if ($tempLines.Count -ge 1) { [int]($tempLines[0] -split "\|")[4].Trim().Split(" ")[0] } else { 0 }
    $cpu2Temp = if ($tempLines.Count -ge 2) { [int]($tempLines[1] -split "\|")[4].Trim().Split(" ")[0] } else { 0 }
    $maxCpuTemp = [math]::Max($cpu1Temp, $cpu2Temp)

    # Combined output with colored temperature values
    Write-Host "Max GPU Temp: " -NoNewline
    if ($gpuTemp -le $gpuLowerLimit) { Write-Host "$gpuTemp°C" -ForegroundColor Green -NoNewline }
    elseif ($gpuTemp -ge $gpuUpperLimit) { Write-Host "$gpuTemp°C" -ForegroundColor Red -NoNewline }
    else { Write-Host "$gpuTemp°C" -ForegroundColor Yellow -NoNewline }
    
    Write-Host " | Max CPU Temp: " -NoNewline
    if ($maxCpuTemp -le $cpuLowerLimit) { Write-Host "$maxCpuTemp°C" -ForegroundColor Green -NoNewline }
    elseif ($maxCpuTemp -ge $cpuUpperLimit) { Write-Host "$maxCpuTemp°C" -ForegroundColor Red -NoNewline }
    else { Write-Host "$maxCpuTemp°C" -ForegroundColor Yellow -NoNewline }
    
    Write-Host " (All temps - GPU: $gpuTemps, CPU: $cpu1Temp $cpu2Temp)"

    # Calculate fan speeds based on thresholds
    $gpuFanSpeed = if ($gpuTemp -le $gpuLowerLimit) { 0 } 
                   elseif ($gpuTemp -ge $gpuUpperLimit) { $maxFanSpeed } 
                   else { [math]::Round($minFanSpeed + (($gpuTemp - $gpuLowerLimit) * ($maxFanSpeed - $minFanSpeed) / ($gpuUpperLimit - $gpuLowerLimit))) }

    $cpu1FanSpeed = if ($cpu1Temp -le $cpuLowerLimit) { 0 } 
                    elseif ($cpu1Temp -ge $cpuUpperLimit) { $maxFanSpeed } 
                    else { [math]::Round($minFanSpeed + (($cpu1Temp - $cpuLowerLimit) * ($maxFanSpeed - $minFanSpeed) / ($cpuUpperLimit - $cpuLowerLimit))) }

    $cpu2FanSpeed = if ($cpu2Temp -le $cpuLowerLimit) { 0 } 
                    elseif ($cpu2Temp -ge $cpuUpperLimit) { $maxFanSpeed } 
                    else { [math]::Round($minFanSpeed + (($cpu2Temp - $cpuLowerLimit) * ($maxFanSpeed - $minFanSpeed) / ($cpuUpperLimit - $cpuLowerLimit))) }

    # Determine the highest fan speed needed
    $fanSpeedPercent = [math]::Max([math]::Max($gpuFanSpeed, $cpu1FanSpeed), $cpu2FanSpeed)
    Write-Host "Calculated fan speeds - GPU: $gpuFanSpeed%, CPU1: $cpu1FanSpeed%, CPU2: $cpu2FanSpeed%. Using: $fanSpeedPercent%"

    $currentCommand = ""
    if ($fanSpeedPercent -eq 0) {
        # All below lower limits: Automatic mode
        Write-Host "All temps below lower limits. Setting fans to Automatic."
        $currentCommand = "$ipmiArgs raw 0x30 0x30 0x01 0x01"
        if ($currentCommand -ne $lastCommand) {
            if ($showCommands) { Write-Host "Executing: $ipmiToolPath $currentCommand" }
            Start-Process -FilePath $ipmiToolPath -ArgumentList $currentCommand -NoNewWindow -Wait
            $lastCommand = $currentCommand
        }
        else {
            Write-Host "No change needed; last command still applies."
        }
    }
    else {
        # At least one above lower limit: Set manual fan speed
        $fanSpeedHex = [int][math]::Round($fanSpeedPercent * 0x64 / 100)
        Write-Host "Debug: fanSpeedHex = $fanSpeedHex"
        $fanSpeedHexString = "0x" + ([Convert]::ToString($fanSpeedHex, 16)).PadLeft(2, '0')

        Write-Host "Setting fans to $fanSpeedPercent% (Hex: $fanSpeedHexString)."
        $disableAutoCommand = "$ipmiArgs raw 0x30 0x30 0x01 0x00"
        $setSpeedCommand = "$ipmiArgs raw 0x30 0x30 0x02 0xff $fanSpeedHexString"
        $currentCommand = "$disableAutoCommand && $setSpeedCommand"

        if ($currentCommand -ne $lastCommand) {
            if ($showCommands) { Write-Host "Executing: $ipmiToolPath $disableAutoCommand" }
            Start-Process -FilePath $ipmiToolPath -ArgumentList $disableAutoCommand -NoNewWindow -Wait

            if ($showCommands) { Write-Host "Executing: $ipmiToolPath $setSpeedCommand" }
            Start-Process -FilePath $ipmiToolPath -ArgumentList $setSpeedCommand -NoNewWindow -Wait

            $lastCommand = $currentCommand
        }
        else {
            Write-Host "No change needed; last command still applies."
        }
    }

    Start-Sleep -Seconds $interval
}
