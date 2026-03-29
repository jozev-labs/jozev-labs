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

# --- 3. Lock down users ---
foreach ($user in $users) {
    $sid = (Get-LocalUser $user.Name).SID

    # Ensure Explorer policy path exists
    $explorerPath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    if (-not (Test-Path $explorerPath)) {
        New-Item -Path $explorerPath -Force | Out-Null
    }
    
    New-ItemProperty -Path $explorerPath -Name "NoControlPanel" -PropertyType DWord -Value 1 -Force
    
    
    # Ensure System policy path exists
    $systemPath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $systemPath)) {
        New-Item -Path $systemPath -Force | Out-Null
    }
    
    New-ItemProperty -Path $systemPath -Name "DisableRegistryTools" -PropertyType DWord -Value 1 -Force
    
    
    # Ensure CMD block path exists
    $cmdPath = "Registry::HKEY_USERS\$sid\Software\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $cmdPath)) {
        New-Item -Path $cmdPath -Force | Out-Null
    }
    
    New-ItemProperty -Path $cmdPath -Name "DisableCMD" -PropertyType DWord -Value 1 -Force
    

    

    # Block specific apps
    $blockedApps = @("control.exe","powershell.exe","cmd.exe")
    $regPath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force }
    $count = 0
    foreach ($app in $blockedApps) {
        $count++
        New-ItemProperty -Path $regPath -Name $count -PropertyType String -Value $app -Force
    }
    # Enable DisallowRun
    New-ItemProperty -Path "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
        -Name "DisallowRun" -PropertyType DWord -Value 1 -Force
}

# --- 4. Create temporary print folder ---
$printFolder = "C:\PublicPrint"
if (-not (Test-Path $printFolder)) { New-Item -Path $printFolder -ItemType Directory }
# Give Users full access
icacls $printFolder /grant Users:(OI)(CI)F /inheritance:e

# --- 5. Set DNS to Cloudflare Family (IPv4 only) ---
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
foreach ($adapter in $adapters) {
    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses ("1.1.1.3","1.0.0.3")
}

# --- 6. Create cleanup script for user logoff ---
$cleanupPath = "C:\Scripts\CleanupUsers.ps1"
if (-not (Test-Path "C:\Scripts")) { New-Item -Path "C:\Scripts" -ItemType Directory }
@"
\$admins = @("Administrator","Admin")
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
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$cleanupPath`""
$trigger = New-ScheduledTaskTrigger -AtLogoff
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -RunLevel Highest -Force

# --- 8. Schedule daily reboot ---
$rebootTask = "DailyReboot"
$rebootAction = New-ScheduledTaskAction -Execute "shutdown.exe" -Argument "/r /f /t 0"
$rebootTrigger = New-ScheduledTaskTrigger -Daily -At "23:59"
Register-ScheduledTask -TaskName $rebootTask -Action $rebootAction -Trigger $rebootTrigger -RunLevel Highest -Force

# --- 9. Optional: block USB storage ---
# Uncomment if desired
# Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\Windows\RemovableStorageDevices" -Name "Deny_All" -Value 1 -Type DWord

