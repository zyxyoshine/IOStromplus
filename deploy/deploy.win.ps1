﻿#$logFile = 'C:\deploylog.txt'
#Start-Transcript $logFile -Append -Force

$Root = "C:\"
$WorkspacePath = $Root + "IOStormplus\"

#Download and unzip agent package

$PackageName = "Agent.zip"
$PackageUrl = "https://github.com/zyxyoshine/IOStormplus/raw/dev2/deploy/binary/Agent.zip"
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
Invoke-WebRequest -Uri $PackageUrl -OutFile ($Root + $PackageName)

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

Unzip ($Root + $PackageName) $Root
Remove-Item ($Root + $PackageName)

#Install fio

$FioBinaryName = "fio-3.5-x64.msi"
$DataStamp = get-date -Format yyyyMMdd
$logFile = '{0}-{1}.log' -f ($WorkspacePath + $FioBinaryName),$DataStamp
$FioMSIArguments = @(
    "/i"
    ('"{0}"' -f ($WorkspacePath + $FioBinaryName))
    "/qn"
    "/norestart"
    "/L*v"
    $logFile
)
Start-Process "msiexec.exe" -ArgumentList $FioMSIArguments -Wait -NoNewWindow
Remove-Item ($WorkspacePath + $FioBinaryName)

#Initialize data disks
$disks = Get-Disk | Where partitionstyle -eq 'raw' | sort number

$letters = 70..89 | ForEach-Object { [char]$_ }
$count = 0
$label = "data"

foreach ($disk in $disks) {
    $driveLetter = $letters[$count].ToString()
    $disk |
    Initialize-Disk -PartitionStyle MBR -PassThru |
    New-Partition -UseMaximumSize -DriveLetter $driveLetter |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel ($label + $count) -Confirm:$false -Force
    $count++
}

#Create Azure Storage configuration file
$storageConfigFileName = "AzureStorage.config"
$storageAccountBuf = 'NAME=' + $args[0]
$storageAccountKeyBuf = 'KEY=' + $args[1]
$storageEndpointSuffixBuf = 'ENDPOINTSUF=' + $args[2]
($storageAccountBuf + [Environment]::NewLine + $storageAccountKeyBuf + [Environment]::NewLine + $storageEndpointSuffixBuf) |  Out-File ($WorkspacePath + $storageConfigFileName)

#Start Agent
netsh advfirewall set privateprofile state off
netsh advfirewall set publicprofile state off

$VMSize = $args[3]
$VMPool = $args[4]
$VMSize | Out-File ($WorkspacePath + 'vmsize.txt')
$VMIp = foreach($ip in (ipconfig) -like '*IPv4*') { ($ip -split ' : ')[-1]}
$agentName = "agent.exe"
$agentPath = $WorkspacePath + $agentName
$args = ' ' + $VMIp + ' ' + $VMSize + ' ' + $VMPool
$action = New-ScheduledTaskAction -Execute $agentPath -Argument $args -WorkingDirectory $WorkspacePath
$trigger = @()
$trigger += New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
$trigger += New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
Unregister-ScheduledTask -TaskName "VMIOSTORM" -Confirm:0 -ErrorAction Ignore
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "VMIOSTORM" -Description "VM iostorm agent" -User "System" -RunLevel Highest -Settings $settings

#Stop-Transcript

#Enable PSRemoting
winrm quickconfig -q
