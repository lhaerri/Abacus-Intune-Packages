#requires -Version 5.1
# Eigenstaendige Intune-Deinstallation mit eingebauten Basisfunktionen.
$ErrorActionPreference = 'Stop'
$script:LogFile = $null
$script:TestTraceFile = $null
$stage = 'PowerShell Einstieg'
function Write-TestTrace([string]$Message) {
    $line = '{0} {1}' -f [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff'), $Message
    [IO.File]::AppendAllText($script:TestTraceFile, $line + [Environment]::NewLine)
    Write-Host $line
}
$exitCode = 1
$lock = $null
try {
    $testRoot = "$env:ProgramData\AbacusDeployment\Logs"
    $env:BASIS_TEST_LOGROOT = $testRoot
    [void][IO.Directory]::CreateDirectory($testRoot)
    $script:TestTraceFile = "$testRoot\Basis-Uninstall-Trace.log"
    Write-TestTrace 'T01 PowerShell hat Uninstall.ps1 erreicht'
    Write-TestTrace "PowerShell=$($PSVersionTable.PSVersion); Is64Bit=$([Environment]::Is64BitProcess); PID=$PID; LanguageMode=$($ExecutionContext.SessionState.LanguageMode)"
    $stage = 'Eingebaute Basisfunktionen initialisieren'
    Write-TestTrace 'T02 VOR Initialisierung der eingebauten Basisfunktionen'
    # Testinstrumentierung: keine eigene DLL und kein Add-Type.
    # Diese Funktion bleibt bei normaler Nutzung ohne Test-Logpfad inaktiv.
    function Write-CommonTestTrace([string]$Message) {
        if (-not [string]::IsNullOrWhiteSpace($env:BASIS_TEST_LOGROOT)) {
            $path = "$env:BASIS_TEST_LOGROOT\Basis-Uninstall-Trace.log"
            $line = '{0} COMMON {1}' -f [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff'), $Message
            [IO.File]::AppendAllText($path, $line + [Environment]::NewLine)
            Write-Host $line
        }
    }
    Write-CommonTestTrace 'C01 Eingebaute Basisfunktionen: Initialisierung'
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $script:LogFile = $null
    $script:StatePath = 'HKLM:\SOFTWARE\AbacusDeployment\Basis'
    $script:LogRoot = Join-Path $env:ProgramData 'AbacusDeployment\Logs'
    $script:ClientRoot = Join-Path $env:ProgramFiles 'Abacus\AbaClient'
    $script:RuleGroup = 'AbacusDeployment - Basis'
    $script:PrefsKey = 'Software\JavaSoft\Prefs\abaclientsetting'
    $script:PrefsValue = 'm/Auto/Update'
    $script:MsiName = 'abaclient-4.3.1194-de.msi'

    function Assert-Environment {
        if (-not [Environment]::Is64BitProcess) { throw '64-Bit-PowerShell erforderlich. In Intune den Sysnative-PowerShell-Pfad verwenden.' }
        Write-CommonTestTrace 'A01 VOR WindowsIdentity.GetCurrent'
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        Write-CommonTestTrace 'A02 NACH WindowsIdentity.GetCurrent'
        try {
            Write-CommonTestTrace 'A03 VOR WindowsPrincipal'
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            Write-CommonTestTrace 'A04 NACH WindowsPrincipal; VOR IsInRole'
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                throw 'Administratorrechte oder SYSTEM-Kontext erforderlich.'
            }
            Write-CommonTestTrace 'A05 NACH IsInRole'
        } finally {
            Write-CommonTestTrace 'A06 VOR WindowsIdentity.Dispose'
            $identity.Dispose()
            Write-CommonTestTrace 'A07 NACH WindowsIdentity.Dispose'
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

    function Get-MsiMetadata([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "MSI fehlt: $Path" }
        $installer = $null; $database = $null
        try {
            Write-CommonTestTrace 'M01 VOR WindowsInstaller COM-Erstellung'
            $installer = New-Object -ComObject WindowsInstaller.Installer
            Write-CommonTestTrace 'M02 NACH WindowsInstaller COM-Erstellung'
            $database = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($Path, 0))
            $values = @{}
            foreach ($property in @('ProductCode', 'ProductVersion', 'ProductName')) {
                $view = $null; $record = $null
                try {
                    $query = "SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = '$property'"
                    $view = $database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $database, @($query))
                    [void]$view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
                    $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
                    if ($null -eq $record) { throw "MSI-Eigenschaft fehlt: $property" }
                    $values[$property] = [string]$record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @(1))
                } finally {
                    Release-Com $record
                    if ($null -ne $view) {
                        try { [void]$view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null) }
                        finally { Release-Com $view }
                    }
                }
            }
            if ($values.ProductName -notmatch '^AbaClient') { throw 'Die MSI ist kein AbaClient-Paket.' }
            if ($values.ProductCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { throw 'Ungueltiger MSI-ProductCode.' }
            [void][version]$values.ProductVersion
            return [pscustomobject]$values
        } finally { Release-Com $database; Release-Com $installer }
    }

    function Get-InstalledProduct([string]$ProductCode) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
            $base = $null; $key = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                $key = $base.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode")
                if ($null -ne $key) {
                    return [pscustomobject]@{ Name = [string]$key.GetValue('DisplayName'); Version = [string]$key.GetValue('DisplayVersion') }
                }
            } finally {
                if ($null -ne $key) { $key.Dispose() }
                if ($null -ne $base) { $base.Dispose() }
            }
        }
        return $null
    }

    function Invoke-Msi([string]$Arguments) {
        Write-CommonTestTrace 'M03 VOR Start-Process msiexec -Wait'
        $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList $Arguments -Wait -PassThru
        Write-CommonTestTrace 'M04 NACH Start-Process msiexec -Wait'
        Write-Log "MSI Exit Code: $($process.ExitCode)"
        return [int]$process.ExitCode
    }

    function Clear-DetectionMarker {
        if (Test-Path -LiteralPath $script:StatePath) {
            Remove-ItemProperty -LiteralPath $script:StatePath -Name 'PackageRevision' -ErrorAction SilentlyContinue
            $state = Get-ItemProperty -LiteralPath $script:StatePath
            if ($null -ne $state.PSObject.Properties['PackageRevision']) { throw 'Erkennungsmarker konnte nicht entfernt werden.' }
        }
    }

    function Set-UserPreference([string]$HiveName) {
        $key = $null
        try {
            $key = [Microsoft.Win32.Registry]::Users.CreateSubKey("$HiveName\$script:PrefsKey")
            if ($null -eq $key) { throw "Registry konnte nicht geoeffnet werden: $HiveName" }
            $key.SetValue($script:PrefsValue, 'false', [Microsoft.Win32.RegistryValueKind]::String)
            $key.Flush()
        } finally { if ($null -ne $key) { $key.Dispose() } }
        Write-Log "AutoUpdate=false gesetzt: $HiveName"
    }

    function Set-OfflinePreference([string]$HiveFile) {
        $mount = 'AbacusBasis_' + [guid]::NewGuid().ToString('N')
        $reg = Join-Path $env:SystemRoot 'System32\reg.exe'
        $result = & $reg load "HKU\$mount" $HiveFile 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Profil-Hive konnte nicht geladen werden: $HiveFile. $result" }
        try { Set-UserPreference $mount }
        finally {
            $unloaded = $false
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $result = & $reg unload "HKU\$mount" 2>&1
                if ($LASTEXITCODE -eq 0) { $unloaded = $true; break }
                Start-Sleep -Seconds 1
            }
            if (-not $unloaded) { throw "Profil-Hive konnte nicht entladen werden: HKU\$mount. $result" }
        }
    }

    function Set-AllUserPreferences {
        $sidPattern = '^S-1-(5-21|12-1)-[0-9-]+$'
        $loaded = @([Microsoft.Win32.Registry]::Users.GetSubKeyNames() | Where-Object { $_ -match $sidPattern })
        foreach ($sid in $loaded) { Set-UserPreference $sid }
        $profileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        foreach ($profile in Get-ChildItem -LiteralPath $profileList) {
            $sid = $profile.PSChildName
            if ($sid -notmatch $sidPattern -or $sid -in $loaded) { continue }
            $details = Get-ItemProperty -LiteralPath $profile.PSPath
            $folder = [Environment]::ExpandEnvironmentVariables([string]$details.ProfileImagePath)
            $hiveFile = Join-Path $folder 'NTUSER.DAT'
            if (-not (Test-Path -LiteralPath $hiveFile -PathType Leaf)) {
                Write-Log "Profil ohne NTUSER.DAT uebersprungen: $folder"
                continue
            }
            # A user may have signed in since the initial snapshot.
            if ($sid -in [Microsoft.Win32.Registry]::Users.GetSubKeyNames()) { Set-UserPreference $sid }
            else { Set-OfflinePreference $hiveFile }
        }
        $profileSettings = Get-ItemProperty -LiteralPath $profileList
        $defaultFolder = [Environment]::ExpandEnvironmentVariables([string]$profileSettings.Default)
        $defaultHive = Join-Path $defaultFolder 'NTUSER.DAT'
        if (-not (Test-Path -LiteralPath $defaultHive -PathType Leaf)) { throw "Default-Profil fehlt: $defaultHive" }
        Set-OfflinePreference $defaultHive
    }

    function Set-BasisFirewall {
        Write-CommonTestTrace 'F01 VOR Import-Module NetSecurity'
        Import-Module NetSecurity -ErrorAction Stop
        Write-CommonTestTrace 'F02 NACH Import-Module NetSecurity'
        # Only replace rules belonging to this package. Existing SCCM rules are retained.
        $old = @(Get-NetFirewallRule -PolicyStore PersistentStore | Where-Object { $_.Group -eq $script:RuleGroup })
        foreach ($rule in $old) { Remove-NetFirewallRule -InputObject $rule }
        $count = 0
        foreach ($runtime in @('jre', 'jre11', 'jre17', 'jre17-x64', 'jre21')) {
            foreach ($exe in @('java.exe', 'javaw.exe')) {
                $program = Join-Path $script:ClientRoot "$runtime\bin\$exe"
                if (Test-Path -LiteralPath $program -PathType Leaf) {
                    $name = 'AbacusDeployment.Basis.{0}.{1}' -f $runtime, $exe
                    New-NetFirewallRule -PolicyStore PersistentStore -Name $name -DisplayName "AbaClient Basis $runtime $exe" -Group $script:RuleGroup -Direction Inbound -Action Allow -Program $program -Enabled True -Profile Any | Out-Null
                    $count++
                    Write-Log "Firewall-Regel erstellt: $program"
                }
            }
        }
        if ($count -eq 0) { throw "Keine bekannte Java-Runtime unter $script:ClientRoot gefunden. Installationspfad pruefen." }
    }

    Write-CommonTestTrace 'C02 Eingebaute Basisfunktionen geladen'
    Write-TestTrace 'T03 NACH Initialisierung der eingebauten Basisfunktionen'
    New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
    $script:LogFile = Join-Path $script:LogRoot 'Basis-Uninstall.log'
    $stage = 'Assert-Environment'
    Write-TestTrace 'T04 VOR Assert-Environment'
    Assert-Environment
    Write-TestTrace 'T05 NACH Assert-Environment'
    try {
        $lock = [IO.File]::Open((Join-Path $script:LogRoot 'Basis.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] { $exitCode = 1618; throw 'Ein anderer Basis-Vorgang laeuft bereits.' }
    Write-Log '=== AbaClient Basis Deinstallation Start ==='
    $stage = 'Productiv-Archiv-Schutzpruefung'
    Write-TestTrace ('VOR: ' + $stage)
    $protectedFiles = @(
        (Join-Path $env:ProgramData 'AbaClient\AbacusProductiv.abalink'),
        (Join-Path $env:ProgramData 'AbaClient\AbacusArchiv.abalink'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\AbaClient\Abacus Productiv.lnk'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\AbaClient\Abacus Archiv.lnk'),
        (Join-Path $env:PUBLIC 'Desktop\Abacus Productiv.lnk'),
        (Join-Path $env:PUBLIC 'Desktop\Abacus Archiv.lnk')
    )
    $present = @($protectedFiles | Where-Object { Test-Path -LiteralPath $_ })
    if ($present.Count -gt 0) {
        $exitCode = 60001
        throw ('Productiv/Archiv zuerst deinstallieren. Noch vorhanden: ' + ($present -join '; '))
    }
    $productCode = $null
    if (Test-Path -LiteralPath $script:StatePath) {
        $state = Get-ItemProperty -LiteralPath $script:StatePath
        if ($null -ne $state.PSObject.Properties['ProductCode']) { $productCode = [string]$state.ProductCode }
    }
    if ([string]::IsNullOrWhiteSpace($productCode)) {
        $stage = 'MSI-Metadaten lesen'
        Write-TestTrace ('VOR: ' + $stage)
        $metadata = Get-MsiMetadata (Join-Path $PSScriptRoot $script:MsiName)
        $productCode = $metadata.ProductCode
    }
    if ($productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { throw 'Ungueltiger gespeicherter ProductCode.' }
    $stage = 'Installierten MSI-Stand lesen'
    Write-TestTrace ('VOR: ' + $stage)
    $installed = Get-InstalledProduct $productCode
    $msiExit = 0
    if ($null -ne $installed) {
        if ($installed.Name -notmatch '^AbaClient') { throw 'ProductCode gehoert nicht zu AbaClient. Abbruch.' }
        $msiLog = Join-Path $script:LogRoot ('Basis-MSI-Uninstall-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $arguments = '/x "{0}" /qn /norestart /L*v "{1}"' -f $productCode, $msiLog
        $stage = 'MSI deinstallieren und warten'
        Write-TestTrace ('VOR: ' + $stage)
        $msiExit = Invoke-Msi $arguments
        if ($msiExit -notin @(0, 1707, 1605, 3010)) { $exitCode = $msiExit; throw "MSI-Deinstallation fehlgeschlagen: $msiExit" }
        if ($null -ne (Get-InstalledProduct $productCode)) { throw 'MSI ist nach Deinstallation weiterhin registriert.' }
    } else { Write-Log 'MSI bereits deinstalliert.' }
    $stage = 'Erkennungsmarker entfernen'
    Write-TestTrace ('VOR: ' + $stage)
    Clear-DetectionMarker
    $stage = 'Firewallregeln entfernen'
    Write-TestTrace ('VOR: ' + $stage)
    Write-CommonTestTrace 'F01 VOR Import-Module NetSecurity'
    Import-Module NetSecurity -ErrorAction Stop
    Write-CommonTestTrace 'F02 NACH Import-Module NetSecurity'
    $ownedRules = @(Get-NetFirewallRule -PolicyStore PersistentStore | Where-Object { $_.Group -eq $script:RuleGroup })
    foreach ($rule in $ownedRules) { Remove-NetFirewallRule -InputObject $rule }
    if (Test-Path -LiteralPath $script:StatePath) { Remove-Item -LiteralPath $script:StatePath -Recurse -Force }
    # Keep user preferences: never turn automatic updates back on without knowing the previous state.
    # Do not delete user data, server links, MSI-owned folders, or legacy firewall rules.
    $exitCode = if ($msiExit -eq 3010) { 3010 } else { 0 }
    Write-Log "=== Basis deinstalliert. Exit Code: $exitCode ==="
} catch {
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
