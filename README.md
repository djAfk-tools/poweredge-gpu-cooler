# poweredge-gpu-cooler
Powershell script to control fans based on added GPU temperatures in a Dell PowerEdge  
Tested on R720 with a Tesla K80 using ipmitool from OpenManage 8.5.0  
Some minor modifications may be needed for other models  

## License
This project is licensed under the MIT License with a No-Sale Restriction. You can use, modify, and include it in other works (even commercial ones), but you may not sell or distribute `PowerEdgeGPUCooler.ps1` as a standalone commercial product. See the [LICENSE](LICENSE) file for details.  
Copyright (c) 2025 djAfk

[Download PowerEdgeGPUCooler.ps1](PowerEdgeGPUCooler.ps1)

**What it does**:  
This tool checks the CPU and GPU temperatures every 30 sec and sets the fan speeds as follows  
If any cpu or gpu temp is above the lower threshold, it turns off automatic fan control and applies the script fan speed  
Script fan speed is divided between the lower and upper thresholds  
Once temps are all below threshold it will turn back on automatic fan control  
NOTE - Using the LOM may not be supported, the host must be able to access this in order to work, use dedicated idrac nic  

**Configuration:**  
Verify the paths for nvidia-smi.exe and ipmitool.exe  
(nvidia-smi.exe is installed with the driver, ipmitool is installed with openmanage)  
separate download for ipmitool - https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=96ph4  
Edit the IP address, username, and password to match your iDrac  

**Thresholds:**  
GPU lower - 42c  
GPU upper - 85c  
CPU lower - 60c  
CPU upper - 80c  
Fan speed - 40%  
Interval - 30 sec  
(set these to what works for you)  

**Modification:**  
If you only have 1 cpu, you may need to modify the section "# Parse CPU temps" - just set $cpu2Temp = $cpu1Temp  

**Troubleshooting:**  
In the "# Configuration" secion, set $showCommands = $true (comment the false line, uncomment the true line).  This will show the verbatim output of commands.  
Run ipmitool manually to see if it connects properly.  If it cannot connect to the idrac, it won't work.  
When iDrac is configured for LOM, the host may not be able to access that IP address.  Ping it.  
If CPU/GPU values are not being parsed correctly, they may need adjusted in the "# GET CPU" and "#Get GPU" sections  
Check your command outputs compared to the expected outputs below  

Expected output of `nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader`:
```
25
30
```

Expected output of `ipmitool sdr type Temperature`:
```
Inlet Temp       | 04h | ok  |  7.1 | 9 degrees C
Exhaust Temp     | 01h | ok  |  7.1 | 14 degrees C
Temp             | 0Eh | ok  |  3.1 | 23 degrees C
Temp             | 0Fh | ok  |  3.2 | 25 degrees C
```

Expected output of script:
```
Starting PowerEdge GPU Cooler script (running as Administrator). Press Ctrl+C to stop.
Max GPU Temp: 25°C (green) | Max CPU Temp: 25°C (green) (All temps - GPU: 25, CPU: 23 25)
Calculated fan speeds - GPU: 0%, CPU1: 0%, CPU2: 0%. Using: 0%
All temps below lower limits. Setting fans to Automatic.
```
