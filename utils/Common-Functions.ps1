# Standard Utilities for OHR Automation Tool

$Global:Lang = "JA"
$Global:TStrings = @{}

# --- i18n Functions ---
function Load-i18n {
    $langFile = Join-Path $PSScriptRoot "..\.toolkit_lang"
    if (Test-Path $langFile) {
        $Global:Lang = (Get-Content $langFile).Trim().ToUpper()
    } else {
        $Global:Lang = "JA"
    }

    $resourceFile = Join-Path $PSScriptRoot "..\resources\strings.$($Global:Lang.ToLower()).psd1"
    if (Test-Path $resourceFile) {
        $Global:TStrings = Import-PowerShellDataFile $resourceFile
    } else {
        # Fallback to JA if missing
        $resourceFile = Join-Path $PSScriptRoot "..\resources\strings.ja.psd1"
        $Global:TStrings = Import-PowerShellDataFile $resourceFile
    }
}

function T($key) {
    if ($Global:TStrings.ContainsKey($key)) {
        return $Global:TStrings[$key]
    }
    return $key
}

function Set-Language($newLang) {
    $langFile = Join-Path $PSScriptRoot "..\.toolkit_lang"
    $newLang.ToUpper() | Out-File $langFile -Encoding UTF8
    Load-i18n
}

# --- Logging Functions ---
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INF",   # INF, WRN, ERR, SUCC
        [string]$Customer = "Common",
        [string]$Env = "Global"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logDir = Join-Path $PSScriptRoot "..\logs\$Customer\$Env"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    
    $logFile = Join-Path $logDir "$((Get-Date).ToString('yyyyMMdd')).log"
    $fullMessage = "[$timestamp][$Level] $Message"
    
    # Console Output with Color
    $color = "White"
    switch ($Level) {
        "WRN" { $color = "Yellow" }
        "ERR" { $color = "Red" }
        "SUCC" { $color = "Green" }
    }
    Write-Host $fullMessage -ForegroundColor $color
    $fullMessage | Out-File $logFile -Append -Encoding UTF8
}

# --- Directory & System Checks ---
function Initialize-FilesystemStructure {
    $dirs = @("bin", "work", "logs", "reports", "installer", "backup", "config\history")
    foreach ($dir in $dirs) {
        $absPath = Join-Path $PSScriptRoot "..\$dir"
        if (-not (Test-Path $absPath)) {
            New-Item -ItemType Directory -Path $absPath -Force | Out-Null
        }
    }
}

# --- Export (Load i18n on inclusion) ---
Load-i18n
