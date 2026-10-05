#requires -Version 5.1
# Eigenstaendige Intune-Installation fuer Abacus Archiv.
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
    $script:TestTraceFile = "$testRoot\Archiv-Install-Trace.log"
    Write-TestTrace 'T01 PowerShell hat Install.ps1 erreicht'
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

    function Assert-Basis {
        if (-not (Test-Path -LiteralPath $script:BasisStatePath)) { throw 'AbaClient Basis ist noch nicht eingerichtet.' }
        $basis = Get-ItemProperty -LiteralPath $script:BasisStatePath
        if ($null -eq $basis.PSObject.Properties['PackageRevision'] -or [string]$basis.PackageRevision -ne '1') {
            throw 'AbaClient Basis ist nicht erfolgreich konfiguriert (PackageRevision=1 fehlt).'
        }
        if ($null -eq $basis.PSObject.Properties['ProductCode']) { throw 'ProductCode der Basis fehlt.' }
        $code = [string]$basis.ProductCode
        if ($code -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { throw 'ProductCode der Basis ist ungueltig.' }
        $found = $false
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
            $baseKey = $null; $productKey = $null
            try {
                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                $productKey = $baseKey.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$code")
                if ($null -ne $productKey -and [string]$productKey.GetValue('DisplayName') -match '^AbaClient') { $found = $true }
            } finally {
                if ($null -ne $productKey) { $productKey.Dispose() }
                if ($null -ne $baseKey) { $baseKey.Dispose() }
            }
        }
        if (-not $found) { throw 'AbaClient-MSI ist trotz Basis-Marker nicht registriert.' }
        Write-Log "AbaClient Basis vorhanden: $code"
    }

    function Clear-DetectionMarker {
        if (Test-Path -LiteralPath $script:StatePath) {
            Remove-ItemProperty -LiteralPath $script:StatePath -Name 'PackageRevision' -ErrorAction SilentlyContinue
            $state = Get-ItemProperty -LiteralPath $script:StatePath
            if ($null -ne $state.PSObject.Properties['PackageRevision']) { throw 'Erkennungsmarker konnte nicht entfernt werden.' }
        }
    }

    function Copy-ConnectionFile {
        New-Item -ItemType Directory -Path $script:TargetFolder -Force | Out-Null
        $tempFile = Join-Path $script:TargetFolder ('Archiv-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            Copy-Item -LiteralPath $script:SourceFile -Destination $tempFile -Force
            $sourceHash = (Get-FileHash -LiteralPath $script:SourceFile -Algorithm SHA256).Hash
            $tempHash = (Get-FileHash -LiteralPath $tempFile -Algorithm SHA256).Hash
            if ($sourceHash -ne $tempHash) { throw 'Kopierte Abalink-Datei weicht von der Quelldatei ab.' }
            Move-Item -LiteralPath $tempFile -Destination $script:TargetFile -Force
        } finally {
            if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force }
        }
        Write-Log "Abalink kopiert: $script:TargetFile"
    }

    function Set-Shortcut([string]$Path) {
        $folder = Split-Path -Path $Path -Parent
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $tempLink = Join-Path $folder ('Archiv-' + [guid]::NewGuid().ToString('N') + '.lnk')
        $shell = $null; $link = $null
        try {
            Write-TestTrace 'VOR WScript.Shell COM-Erstellung'
            $shell = New-Object -ComObject WScript.Shell
            Write-TestTrace 'NACH WScript.Shell COM-Erstellung'
            $link = $shell.CreateShortcut($tempLink)
            $link.TargetPath = $script:TargetFile
            $link.Arguments = ''
            $link.WorkingDirectory = $script:TargetFolder
            $link.Description = 'Abacus Archiv - DCHABACARCHIV01'
            $link.WindowStyle = 1
            $link.Save()
            Release-Com $link
            $link = $null
            if (-not (Test-Path -LiteralPath $tempLink -PathType Leaf)) { throw "Verknuepfung wurde nicht erstellt: $Path" }
            Move-Item -LiteralPath $tempLink -Destination $Path -Force
        } finally {
            Release-Com $link
            Release-Com $shell
            if (Test-Path -LiteralPath $tempLink) { Remove-Item -LiteralPath $tempLink -Force }
        }
        Write-Log "Verknuepfung erstellt: $Path"
    }

    function Assert-InstalledFiles {
        if (-not (Test-Path -LiteralPath $script:TargetFile -PathType Leaf)) { throw 'Installierte Abalink-Datei fehlt.' }
        $sourceHash = (Get-FileHash -LiteralPath $script:SourceFile -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $script:TargetFile -Algorithm SHA256).Hash
        if ($sourceHash -ne $targetHash) { throw 'Installierte Abalink-Datei entspricht nicht der Quelle.' }
        $shell = $null
        try {
            Write-TestTrace 'VOR WScript.Shell COM-Erstellung'
            $shell = New-Object -ComObject WScript.Shell
            Write-TestTrace 'NACH WScript.Shell COM-Erstellung'
            foreach ($path in @($script:StartMenuLink, $script:DesktopLink)) {
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Verknuepfung fehlt: $path" }
                $link = $null
                try {
                    $link = $shell.CreateShortcut($path)
                    if ([string]$link.TargetPath -ne $script:TargetFile -or -not [string]::IsNullOrEmpty([string]$link.Arguments)) {
                        throw "Verknuepfung zeigt nicht korrekt auf Archiv: $path"
                    }
                } finally { Release-Com $link }
            }
        } finally { Release-Com $shell }
        return $targetHash
    }
    Write-TestTrace 'T03 NACH Initialisierung der eingebauten Funktionen'
    $script:LogFile = Join-Path $script:LogRoot 'Archiv-Install.log'
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
    Write-Log '=== Abacus Archiv Installation Start ==='
    $stage = 'Quelldatei pruefen'
    Write-TestTrace ('VOR: ' + $stage)
    if (-not (Test-Path -LiteralPath $script:SourceFile -PathType Leaf)) {
        throw "Die echte Archiv-Abalink fehlt im Paket: $script:SourceFile"
    }
    if ((Get-Item -LiteralPath $script:SourceFile).Length -eq 0) { throw 'Die Archiv-Abalink-Datei ist leer.' }
    $stage = 'Basis pruefen'
    Write-TestTrace ('VOR: ' + $stage)
    try { Assert-Basis } catch { $exitCode = 60002; throw }
    $stage = 'Erkennungsmarker entfernen'
    Write-TestTrace ('VOR: ' + $stage)
    Clear-DetectionMarker
    $stage = 'Abalink kopieren'
    Write-TestTrace ('VOR: ' + $stage)
    Copy-ConnectionFile
    $stage = 'Startmenue-Verknuepfung erstellen'
    Write-TestTrace ('VOR: ' + $stage)
    Set-Shortcut $script:StartMenuLink
    $stage = 'Desktop-Verknuepfung erstellen'
    Write-TestTrace ('VOR: ' + $stage)
    Set-Shortcut $script:DesktopLink
    $stage = 'Dateien und Verknuepfungen pruefen'
    Write-TestTrace ('VOR: ' + $stage)
    $hash = Assert-InstalledFiles
    $stage = 'Erkennungsmarker schreiben'
    Write-TestTrace ('VOR: ' + $stage)
    New-Item -Path $script:StatePath -Force | Out-Null
    New-ItemProperty -Path $script:StatePath -Name 'ExpectedServer' -Value 'DCHABACARCHIV01' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:StatePath -Name 'AbalinkSHA256' -Value $hash -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:StatePath -Name 'ConfiguredAt' -Value (Get-Date -Format 'o') -PropertyType String -Force | Out-Null
    # The server configuration inside the provided Abalink must be verified by the administrator.
    # Write the completion marker only after file and shortcut verification.
    New-ItemProperty -Path $script:StatePath -Name 'PackageRevision' -Value '1' -PropertyType String -Force | Out-Null
    $exitCode = 0
    $stage = 'Vorgang abschliessen'
    Write-TestTrace ('VOR: ' + $stage)
    Write-Log '=== Abacus Archiv erfolgreich eingerichtet ==='
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
