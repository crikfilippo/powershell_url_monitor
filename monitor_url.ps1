param(
    [string]$ConfigFile = "$PSScriptRoot\config.psd1"
)

# ---------- load configuration ----------

if (-not (Test-Path $ConfigFile)) {
    Write-Host "ERROR: Configuration file '$ConfigFile' not found." -ForegroundColor Red
    exit 1
}

try {
    $cfg = Import-PowerShellDataFile -Path $ConfigFile
}
catch {
    Write-Host "ERROR: unable to read configuration file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- required fields ---
$requiredKeys = @("UseSSH", "SshHost", "SshPort", "SshUser", "SshPassword", "URL")
foreach ($key in $requiredKeys) {
    if (-not $cfg.ContainsKey($key)) {
        Write-Host "ERROR: required parameter missing in config: '$key'" -ForegroundColor Red
        exit 1
    }
}

# --- read with fallback to default values ---
$URL               = [string]$cfg.URL
$UseSSH            = [bool]$cfg.UseSSH
$SshHost           = [string]$cfg.SshHost
$SshPort           = [int]$cfg.SshPort
$SshUser           = [string]$cfg.SshUser
$SshPassword       = [string]$cfg.SshPassword
$ConnectionTimeout = if ($cfg.ContainsKey("ConnectionTimeout")) { [int]$cfg.ConnectionTimeout }  else { 30 }
$SnippetMaxLen     = if ($cfg.ContainsKey("SnippetMaxLen"))     { [int]$cfg.SnippetMaxLen }      else { 100 }
$IntervalSeconds   = if ($cfg.ContainsKey("IntervalSeconds"))   { [int]$cfg.IntervalSeconds }    else { 120 }
$MaxLines          = if ($cfg.ContainsKey("MaxLines"))          { [int]$cfg.MaxLines }           else { 2880 }

# --- paths: if relative, resolved against script folder ---
$rawPlink  = if ($cfg.ContainsKey("PlinkExe"))  { $cfg.PlinkExe }  else { ".\putty\App\putty\PLINK.EXE" }
$rawLog    = if ($cfg.ContainsKey("LogFolder")) { $cfg.LogFolder } else { ".\data" }

$PlinkExe  = if ([System.IO.Path]::IsPathRooted($rawPlink)) { $rawPlink } else { [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $rawPlink)) }
$LogFolder = if ([System.IO.Path]::IsPathRooted($rawLog))   { $rawLog }   else { [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $rawLog)) }

Write-Host "Configuration loaded from: $ConfigFile" -ForegroundColor Cyan

# ---------- functions ----------

function Get-LogFilePath {
    if (-not (Test-Path -Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder | Out-Null
    }

    $date  = Get-Date -Format "yyyyMMdd"
    $index = 1
    $path  = Join-Path $LogFolder "${date}_${index}.csv"

    while (Test-Path $path) {
        $lineCount = (Get-Content $path | Measure-Object -Line).Lines
        if ($lineCount -lt $MaxLines) {
            return $path
        }
        $index++
        $path = Join-Path $LogFolder "${date}_${index}.csv"
    }

    "Timestamp,Status,HttpCode,Connection,ContentSnippet" | Out-File -FilePath $path -Encoding utf8
    return $path
}

function Write-Log {
    param(
        [string]$Status,
        [string]$HttpCode,
        [string]$Connection,
        [string]$ContentSnippet
    )

    $script:LogFile = Get-LogFilePath
    $line = "{0},{1},{2},{3},{4}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Status, $HttpCode, $Connection, $ContentSnippet
    Add-Content -Path $script:LogFile -Value $line
    Write-Host $line
}

function Truncate-Snippet {
    param([string]$Text)
    $clean = $Text -replace ",", ""
    if ($clean.Length -le $SnippetMaxLen) { return $clean }
    return $clean.Substring(0, $SnippetMaxLen - 3) + "..."
}

function Test-SshUrl {
    # Simple curl: body + HTTP code separated by a unique marker. Works on Linux and Windows hosts.
    # -sS = silent but show errors; -L = follow redirects
    $marker = '###HTTP_CODE###'
    $remoteCmd = "curl -sSL -w '" + $marker + "%{http_code}' --max-time " + $ConnectionTimeout + " '" + $URL + "'"
    $connection = "$SshUser@$SshHost -> $URL"

    try {
        $result = & $PlinkExe -batch -ssh $SshHost -P $SshPort -l $SshUser -pw $SshPassword $remoteCmd 2>&1
        $fullOutput = ($result | ForEach-Object { $_.ToString() }) -join "`n"

        if ([string]::IsNullOrWhiteSpace($fullOutput)) {
            Write-Log "KO" "" $connection "EMPTY RESPONSE"
            return
        }

        # Split on marker: everything before = body, everything after = HTTP code
        $markerIdx = $fullOutput.LastIndexOf($marker)
        if ($markerIdx -ge 0) {
            $body     = $fullOutput.Substring(0, $markerIdx).Trim()
            $httpCode = $fullOutput.Substring($markerIdx + $marker.Length).Trim()
        } else {
            Write-Log "KO" "" $connection "CURL ERROR: $(Truncate-Snippet $fullOutput)"
            return
        }

        if ($httpCode -notmatch '^\d{3}$') {
            Write-Log "KO" "" $connection "CURL ERROR: $(Truncate-Snippet $fullOutput)"
            return
        }

        if ($httpCode -eq "200" -and $body -eq "") { $httpCode = "204" }

        Write-Log "OK" $httpCode $connection (Truncate-Snippet -Text $body)
    }
    catch {
        Write-Log "KO" "" $connection "SSH ERROR: $($_.Exception.Message)"
    }
}

function Test-DirectUrl {
    $connection = "DIRECT -> $URL"

    try {
        $response = Invoke-WebRequest -Uri $URL -UseBasicParsing -TimeoutSec $ConnectionTimeout -ErrorAction Stop
        $httpCode  = [string]$response.StatusCode
        $content   = $response.Content

        if ($httpCode -eq "200" -and $content -eq "") { $httpCode = "204" }

        Write-Log "OK" $httpCode $connection (Truncate-Snippet -Text $content)
    }
    catch {
        $httpCode = ""
        if ($_.Exception.Response) { $httpCode = [string]$_.Exception.Response.StatusCode.value__ }
        Write-Log "KO" $httpCode $connection "DIRECT ERROR: $($_.Exception.Message)"
    }
}

# ---------- startup ----------

if ($UseSSH) {
    if (-not (Test-Path $PlinkExe)) {
        Write-Host "ERROR: plink.exe not found at $PlinkExe" -ForegroundColor Red
        exit 1
    }

    # Verify SSH connectivity (also accepts fingerprint on first run)
    Write-Host "Testing SSH connection to $SshHost..." -ForegroundColor Yellow
    $testResult = echo y | & $PlinkExe -ssh $SshHost -P $SshPort -l $SshUser -pw $SshPassword "echo __SSH_OK__" 2>&1
    $testOutput = $testResult -join "`n"
    
    if ($testOutput -match "__SSH_OK__") {
        Write-Host "SSH connection verified." -ForegroundColor Green

        # Verify if the SSH fingerprint is cached
        Write-Host "Checking if SSH fingerprint is cached for $SshHost..." -ForegroundColor Yellow
        $fingerprintCached = & $PlinkExe -batch -ssh $SshHost -P $SshPort -l $SshUser -pw $SshPassword "echo __CHECK_FINGERPRINT__" 2>&1
        if ($fingerprintCached -match "The host key is not cached for this server") {
            Write-Host "ERROR: SSH fingerprint is not cached. Please accept the fingerprint to proceed." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "ERROR: SSH connection failed: $testOutput" -ForegroundColor Red
        exit 1
    }

    Write-Host "Mode: SSH tunnel ($SshUser@$SshHost -> $URL)"
} else {
    Write-Host "Mode: DIRECT connection ($URL)"
}

Write-Host "Monitoring started. Interval: $IntervalSeconds sec | Max lines: $MaxLines"
Write-Host "Timeout: $ConnectionTimeout sec | Snippet: $SnippetMaxLen chars"
Write-Host "Log folder: $LogFolder"

while ($true) {
    if ($UseSSH) { Test-SshUrl } else { Test-DirectUrl }
    Start-Sleep -Seconds $IntervalSeconds
}