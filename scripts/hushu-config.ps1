# --- 1. Administrator accounts to exclude ---
# $admins = @("Administrator","Admin")  # adjust names
$admins = (Get-LocalGroupMember -Group "Administrators").Name | ForEach-Object { $_.Split("\")[-1] }

# --- 2. Get all non-admin users ---
$users = Get-LocalUser | Where-Object { $_.Enabled -eq $true -and $_.Name -notin $admins }

# --- Output results ---
Write-Host "==== Administrators detected ====" -ForegroundColor Cyan
foreach ($admin in $admins) {
    Write-Host $admin
}

Write-Host ""
Write-Host "==== Standard users (will be restricted & cleaned) ====" -ForegroundColor Yellow
foreach ($user in $users) {
    Write-Host $user.Name
}

Write-Host ""


function Ensure-RegPath {
    param ([string]$path)

    $parts = $path -split '\\'
    $current = $parts[0]

    for ($i = 1; $i -lt $parts.Length; $i++) {
        $current = "$current\$($parts[$i])"
        if (-not (Test-Path $current)) {
            New-Item -Path $current -Force | Out-Null
        }
    }
}


# --- 3. Lock down users ---
foreach ($user in $users) {


    $profilePath = "C:\Users\$($user.Name)"
    $ntuser = "$profilePath\NTUSER.DAT"
    
    if (Test-Path $ntuser) {
    
        $tempHive = "TempHive_$($user.Name)"
    
        # Load user registry hive
        reg load "HKU\$tempHive" $ntuser | Out-Null
    
        $base = "Registry::HKEY_USERS\$tempHive"
    
        # Now your paths will actually exist
        $explorerPath = "$base\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        Ensure-RegPath $explorerPath
    
        New-ItemProperty -Path $explorerPath -Name "NoControlPanel" -Value 1 -PropertyType DWord -Force
    
        $systemPath = "$base\Software\Microsoft\Windows\CurrentVersion\Policies\System"
        Ensure-RegPath $systemPath
    
        New-ItemProperty -Path $systemPath -Name "DisableRegistryTools" -Value 1 -PropertyType DWord -Force

         # Ensure CMD block path exists
        $cmdPath = "$base\Software\Policies\Microsoft\Windows\System"
        Ensure-RegPath $cmdPath    
        New-ItemProperty -Path $cmdPath -Name "DisableCMD" -PropertyType DWord -Value 1 -Force

        # Block specific apps
        $blockedApps = @("control.exe","powershell.exe","cmd.exe")
        $regPath = "$base\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun"
        Ensure-RegPath $regPath
        
        $count = 0
        foreach ($app in $blockedApps) {
            $count++
            New-ItemProperty -Path $regPath -Name $count -PropertyType String -Value $app -Force
        }
        # Enable DisallowRun
        New-ItemProperty -Path "$base\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
            -Name "DisallowRun" -PropertyType DWord -Value 1 -Force
            
        
        # Unload cleanly
        reg unload "HKU\$tempHive" | Out-Null
    }

}

# --- 4. Create temporary print folder ---
$printFolder = "C:\PublicPrint"
if (-not (Test-Path $printFolder)) { New-Item -Path $printFolder -ItemType Directory }
# Give Users full access
icacls $printFolder /grant "Users:(OI)(CI)F" /inheritance:e

# --- 5. Set DNS to Cloudflare Family (IPv4 only) ---
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($adapter in $adapters) {
    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses ("1.1.1.3","1.0.0.3")
}

# --- 6. Create cleanup script for user logoff ---
$cleanupPath = "C:\Scripts\CleanupUsers.ps1"
if (-not (Test-Path "C:\Scripts")) { New-Item -Path "C:\Scripts" -ItemType Directory }
@"
\$admins = @("Administrator","Admin", "rk")
\$users = Get-LocalUser | Where-Object { \$_.Enabled -eq \$true -and \$_.Name -notin \$admins }
foreach (\$user in \$users) {
    \$profile = "C:\Users\$($user.Name)"
    \$paths = @("Desktop","Downloads","Documents","AppData\Local\Temp")
    foreach (\$p in \$paths) {
        \$fullPath = Join-Path \$profile \$p
        if (Test-Path \$fullPath) { Remove-Item \$fullPath\* -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
"@ | Set-Content $cleanupPath

# --- 7. Register cleanup script at user logoff ---
$taskName = "RegisterLogoffScript"
$cleanupPathEscaped = $cleanupPath -replace '"','\"'
$logoffCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$cleanupPathEscaped`""

# Delete existing task if it exists
schtasks /Delete /TN $taskName /F 2>$null

# Create logoff task
schtasks /Create /TN $taskName `
  /TR "$logoffCmd" `
  /SC ONLOGOFF `
  /RL HIGHEST `
  /F

# --- 8. Schedule daily reboot ---
$rebootTask = "DailyReboot"
$rebootAction = New-ScheduledTaskAction -Execute "shutdown.exe" -Argument "/r /f /t 0"
$rebootTrigger = New-ScheduledTaskTrigger -Daily -At "23:59"

# Remove existing task if present
try { Unregister-ScheduledTask -TaskName $rebootTask -Confirm:$false -ErrorAction SilentlyContinue } catch {}

Register-ScheduledTask -TaskName $rebootTask -Action $rebootAction -Trigger $rebootTrigger -RunLevel Highest -Force

# --- 9. Optional: block USB storage ---
# Uncomment if desired
# Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\Windows\RemovableStorageDevices" -Name "Deny_All" -Value 1 -Type DWord

