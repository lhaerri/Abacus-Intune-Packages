#requires -Version 5.1
# Eigenstaendige Intune-Deinstallation fuer Abacus Archiv.
# Alle Funktionen sind eingebaut. Die Installation benoetigt Files\AbacusArchiv.abalink.
$ErrorActionPreference = 'Stop'
$exitCode = 1
$lock = $null
$script:LogFile = $null
$script:TestTraceFile = $null
$stage = 'PowerShell Einstieg'

function Write-TestTrace([string]$Message) {
    $line = '{0} {1}' -f [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff'), $Message
    [IO.File]::AppendAllText($script:TestTraceFile, $line + [Environment]::NewLine)
    Write-Host $line
}

try {
    $testRoot = "$env:ProgramData\AbacusDeployment\Logs"
    [void][IO.Directory]::CreateDirectory($testRoot)
    $script:TestTraceFile = "$testRoot\Archiv-Uninstall-Trace.log"
    Write-TestTrace 'T01 PowerShell hat Uninstall.ps1 erreicht'
    Write-TestTrace "PowerShell=$($PSVersionTable.PSVersion); Is64Bit=$([Environment]::Is64BitProcess); PID=$PID; LanguageMode=$($ExecutionContext.SessionState.LanguageMode)"
    $stage = 'Eingebaute Funktionen initialisieren'
    Write-TestTrace 'T02 VOR Initialisierung der eingebauten Funktionen'
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $script:LogFile = $null
    $script:StatePath = 'HKLM:\SOFTWARE\AbacusDeployment\Archiv'
    $script:BasisStatePath = 'HKLM:\SOFTWARE\AbacusDeployment\Basis'
    $script:LogRoot = Join-Path $env:ProgramData 'AbacusDeployment\Logs'
    $script:TargetFolder = Join-Path $env:ProgramData 'AbaClient'
    $script:TargetFile = Join-Path $script:TargetFolder 'AbacusArchiv.abalink'
    $script:StartMenuLink = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\AbaClient\Abacus Archiv.lnk'
    $script:DesktopLink = Join-Path $env:PUBLIC 'Desktop\Abacus Archiv.lnk'
    $script:SourceFile = Join-Path $PSScriptRoot 'Files\AbacusArchiv.abalink'

    function Assert-Environment {
        if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich. In Intune den Sysnative-PowerShell-Pfad verwenden.' }
        Write-TestTrace 'A01 VOR WindowsIdentity.GetCurrent'
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        Write-TestTrace 'A02 NACH WindowsIdentity.GetCurrent'
        try {
            Write-TestTrace 'A03 VOR WindowsPrincipal'
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            Write-TestTrace 'A04 NACH WindowsPrincipal; VOR IsInRole'
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                throw 'Administratorrechte oder SYSTEM-Kontext erforderlich.'
            }
            Write-TestTrace 'A05 NACH IsInRole'
        } finally {
            Write-TestTrace 'A06 VOR WindowsIdentity.Dispose'
            $identity.Dispose()
            Write-TestTrace 'A07 NACH WindowsIdentity.Dispose'
        }
    }

    function Write-Log([string]$Message) {
        $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
        Write-Host $line
    }

    function Release-Com($Object) {
        if ($null -ne $Object -and [Runtime.InteropServices.Marshal]::IsComObject($Object)) {
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Object)
        }
    }

    function Clear-DetectionMarker {
        if (Test-Path -LiteralPath $script:StatePath) {
            Remove-ItemProperty -LiteralPath $script:StatePath -Name 'PackageRevision' -ErrorAction SilentlyContinue
            $state = Get-ItemProperty -LiteralPath $script:StatePath
            if ($null -ne $state.PSObject.Properties['PackageRevision']) { throw 'Erkennungsmarker konnte nicht entfernt werden.' }
        }
    }
    Write-TestTrace 'T03 NACH Initialisierung der eingebauten Funktionen'
    $script:LogFile = Join-Path $script:LogRoot 'Archiv-Uninstall.log'
    Write-Log 'Start: vor Assert-Environment'
    $stage = 'Assert-Environment'
    Write-TestTrace 'T04 VOR Assert-Environment'
    Assert-Environment
    Write-TestTrace 'T05 NACH Assert-Environment'
    Write-Log 'Umgebungspruefung erfolgreich'
    $stage = 'Vorgangssperre setzen'
    Write-TestTrace ('VOR: ' + $stage)
    try {
        $lock = [IO.File]::Open((Join-Path $script:LogRoot 'Archiv.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] { $exitCode = 1618; throw 'Ein anderer Archiv-Vorgang laeuft bereits.' }
    $stage = 'Vorgang starten'
    Write-TestTrace ('VOR: ' + $stage)
    Write-Log '=== Abacus Archiv Deinstallation Start ==='
    $stage = 'Erkennungsmarker entfernen'
    Write-TestTrace ('VOR: ' + $stage)
    Clear-DetectionMarker
    $stage = 'Eigene Dateien entfernen'
    Write-TestTrace ('VOR: ' + $stage)
    foreach ($path in @($script:StartMenuLink, $script:DesktopLink, $script:TargetFile)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
            if (Test-Path -LiteralPath $path) { throw "Datei konnte nicht entfernt werden: $path" }
            Write-Log "Entfernt: $path"
        } else { Write-Log "Bereits entfernt: $path" }
    }
    $stage = 'Eigenen Registry-Schluessel entfernen'
    Write-TestTrace ('VOR: ' + $stage)
    if (Test-Path -LiteralPath $script:StatePath) { Remove-Item -LiteralPath $script:StatePath -Recurse -Force }
    # Shared folders, the AbaClient MSI, Basis settings, and Productiv are retained.
    $exitCode = 0
    $stage = 'Vorgang abschliessen'
    Write-TestTrace ('VOR: ' + $stage)
    Write-Log '=== Abacus Archiv deinstalliert ==='
} catch {
    if ($exitCode -eq 0) { $exitCode = 1 }
    $failure = $_
    $detail = "FEHLER bei '$stage': $($failure.Exception.ToString())`r`nPosition: $($failure.InvocationInfo.PositionMessage)`r`nScriptStack: $($failure.ScriptStackTrace)`r`nErrorId: $($failure.FullyQualifiedErrorId)"
    if ($null -ne $script:TestTraceFile) {
        try { Write-TestTrace $detail } catch { Write-Warning 'Test-Trace konnte nicht geschrieben werden.' }
    }
    if ($null -ne $script:LogFile) {
        try { Write-Log $detail } catch { Write-Warning 'Installationslog konnte nicht geschrieben werden.' }
    }
    Write-Warning $detail
} finally { if ($null -ne $lock) { $lock.Dispose() } }
exit $exitCode
