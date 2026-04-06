# Menu Handler for OHR Tool

. "$PSScriptRoot\Common-Functions.ps1"

function Show-LanguageMenu {
    Clear-Host
    Write-Host "================================"
    Write-Host "  SELECT LANGUAGE / 语言选择     "
    Write-Host "================================"
    Write-Host "1. 日本語 (JA)"
    Write-Host "2. 简体中文 (ZH)"
    Write-Host "3. English (EN)"
    Write-Host "--------------------------------"
    $selection = Read-Host "Choice [1-3]"
    switch ($selection) {
        "1" { Set-Language "JA" }
        "2" { Set-Language "ZH" }
        "3" { Set-Language "EN" }
        default { Set-Language "JA" }
    }
}

function Get-CustomerEnvSelection {
    param(
        [ref]$Customer,
        [ref]$Env
    )

    # 1. Select Customer
    $histDir = Join-Path $PSScriptRoot "..\config\history"
    $customers = Get-ChildItem $histDir -Filter "*.json" | Select-Object -ExpandProperty BaseName
    
    Write-Host "`n$(T 'ChooseCustomer')" -ForegroundColor Cyan
    if ($customers) {
        for ($i=0; $i -lt $customers.Count; $i++) {
            Write-Host "$($i+1). $($customers[$i])"
        }
    }
    
    $cInput = Read-Host "$(T 'InputCustomerName')"
    if ([int]::TryParse($cInput, [ref]$idx) -and $idx -le $customers.Count -and $idx -gt 0) {
        $Customer.Value = $customers[$idx-1]
    } else {
        $Customer.Value = $cInput
    }

    # 2. Select Env (Mocking for now, will read from Customer JSON later)
    $Env.Value = Read-Host "$(T 'InputEnvName')"
}

function Show-MainMenu {
    $currentCustomer = "None"
    $currentEnv = "None"

    while ($true) {
        Clear-Host
        Write-Host "$(T 'MenuTitle')" -ForegroundColor Magenta
        Write-Host "--------------------------------"
        Write-Host "Customer: $currentCustomer | Env: $currentEnv | Lang: $Global:Lang" -ForegroundColor Gray
        Write-Host "--------------------------------"
        Write-Host "$(T 'ChooseCustomer')"
        Write-Host "$(T 'OperationPhaseA')"
        Write-Host "$(T 'OperationPhaseB')"
        Write-Host "$(T 'ChangeLanguage')"
        Write-Host "$(T 'Exit')"
        Write-Host "--------------------------------"
        
        $choice = Read-Host "Selection"
        switch ($choice.ToUpper()) {
            "1" { Get-CustomerEnvSelection -Customer ([ref]$currentCustomer) -Env ([ref]$currentEnv) }
            "A" { 
                if ($currentCustomer -eq "None") { 
                    Write-Log -Level "WRN" -Message "Please select customer first."
                    Start-Sleep -Seconds 2
                } else {
                    Invoke-PhaseA -Customer $currentCustomer -Env $currentEnv
                    Pause
                }
            }
            "B" {
                 if ($currentCustomer -eq "None") {
                    Write-Log -Level "WRN" -Message "Please select customer first."
                    Start-Sleep -Seconds 2
                } else {
                    Invoke-PhaseB -Customer $currentCustomer -Env $currentEnv
                    Pause
                }
            }
            "L" { Show-LanguageMenu }
            "Q" { exit }
        }
    }
}
