$ErrorActionPreference = 'Stop'
$svcPath = "C:\Program Files\Docker\Docker\com.docker.service"

# Check if service already exists
$existing = Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Service already exists, starting..."
    Start-Service com.docker.service
} else {
    Write-Host "Creating service..."
    sc.exe create com.docker.service binPath= "`"$svcPath`"" DisplayName= "Docker Desktop Service" start= demand
    sc.exe config com.docker.service obj= "NT AUTHORITY\NetworkService"
    Start-Service com.docker.service
}

# Wait for service to stabilize
Start-Sleep 3
Get-Service com.docker.service
