# OHR Automation Installer - Main Entry
# Requires: PowerShell 7.0+
# Reference: PROD-01 (Requirement Definition)

# 1. Environment Setup
$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot

# Import Utilities
. "$ScriptDir\utils\Common-Functions.ps1"
. "$ScriptDir\utils\Menu-Handler.ps1"
. "$ScriptDir\utils\PhaseA-Logic.ps1"
. "$ScriptDir\utils\PhaseB-Logic.ps1"

# 2. Main Entry Point
function Start-Installer {
    param(
        [string]$CustomerName,
        [string]$EnvName,
        [string]$Action # A, B
    )

    # Initialize Essential Filesystem
    Initialize-FilesystemStructure
    
    # Check for admin
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log -Message "Administrator rights required." -Level "ERR"
        # exit 1
    }

    # Decide if we go CLI or Menu
    if ($CustomerName -and $Action) {
        # Silent / CLI Mode
        switch ($Action.ToUpper()) {
            "A" { Invoke-PhaseA -Customer $CustomerName -Env $EnvName }
            "B" { Invoke-PhaseB -Customer $CustomerName -Env $EnvName }
        }
    } else {
        # Interactive Menu Mode
        Show-MainMenu
    }
}

# Execute
Start-Installer @PSBoundParameters
