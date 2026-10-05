# AbaClient Basis

## 1. Kurze Übersicht

Die Basis-App installiert den gemeinsamen AbaClient und konfiguriert Benutzerprofile sowie die Java-Firewallregeln. Die Verbindungen und Verknüpfungen für Productiv und Archiv werden durch die beiden separaten Link-Apps eingerichtet.

Installation und Deinstallation erfolgen jeweils durch genau eine eigenständige PowerShell-Datei. Eine CMD-Datei und eine separate Basis.Common.ps1 sind nicht mehr Bestandteil des Pakets.

| Merkmal | Wert |
| --- | --- |
| Intune-App | AbaClient Basis 4.3 |
| MSI-Datei | abaclient-4.3.1194-de.msi |
| MSI-Version | 4.3.1194 |
| MSI-ProductCode | {D1BEBC97-E763-418E-B999-BD5FD75A9BA5} |
| Ausführung | 64-Bit Windows PowerShell 5.1, SYSTEM-Kontext |
| Erkennungsmarker | HKLM\SOFTWARE\AbacusDeployment\Basis, PackageRevision = 1 (REG_SZ) |

## 2. Was wird genau installiert und eingerichtet?

### Dateien im Paket

Im Ordner `Abacus-Basis\Source` liegen diese drei Dateien:

| Datei | Aufgabe |
| --- | --- |
| Install.ps1 | Installiert oder prüft die MSI und konfiguriert die Basis. Alle benötigten Funktionen sind in dieser Datei eingebaut. |
| Uninstall.ps1 | Prüft zuerst auf vorhandene Productiv-/Archiv-Dateien, deinstalliert danach die MSI und entfernt die eigenen Firewallregeln sowie den Basis-Marker. Alle benötigten Funktionen sind eingebaut. |
| abaclient-4.3.1194-de.msi | Originalinstallation des AbaClient inklusive der vom MSI gelieferten Dateien und Komponenten. Muss neben den Scripts liegen. |

Die angehängten Dateien `Install (2).ps1` und `Uninstall(2).ps1` vor dem Verpacken in `Install.ps1` und `Uninstall.ps1` umbenennen. Diese README ausserhalb von `Source` ablegen. Tools und bisherige CMD-/Common-Dateien nicht mitverpacken.

### Installation durch Install.ps1

1. Erstellt den Logordner und beginnt mit der Trace-Protokollierung bereits vor der Umgebungsprüfung.
2. Prüft, dass PowerShell als 64-Bit-Prozess mit Administratorrechten beziehungsweise als SYSTEM läuft.
3. Setzt eine Dateisperre gegen gleichzeitige Basis-Vorgänge.
4. Liest ProductCode, Produktname und Version aus der mitgelieferten MSI. Die Datei muss als AbaClient erkannt werden.
5. Entfernt einen vorhandenen PackageRevision-Marker vor der eigentlichen Konfiguration.
6. Prüft in beiden Registry-Ansichten, ob dieselbe MSI bereits in gleicher oder höherer Version installiert ist. In diesem Fall wird die MSI übersprungen; die Basiskonfiguration wird trotzdem angewendet.
7. Installiert die MSI andernfalls mit `/qn /norestart` und einem separaten MSI-Log. Prüft danach erneut MSI-Registrierung und Version.
8. Setzt die Benutzerpräferenz `m/Auto/Update` als REG_SZ auf `false` unter `Software\JavaSoft\Prefs\abaclientsetting`:
   - in bereits geladenen Benutzer-Hives;
   - in bestehenden, nicht geladenen Benutzerprofilen über deren NTUSER.DAT;
   - im Default-Benutzerprofil für künftig neu angelegte Profile.
9. Ersetzt ausschliesslich die Firewallregeln aus der eigenen Gruppe `AbacusDeployment - Basis`. Für vorhandene `java.exe` und `javaw.exe` unter `C:\Program Files\Abacus\AbaClient` werden eingehende Zulassungsregeln für alle Firewallprofile eingerichtet. Geprüfte Runtime-Ordner: `jre`, `jre11`, `jre17`, `jre17-x64`, `jre21`. Ohne eine gefundene Runtime schlägt die Konfiguration fehl.
10. Schreibt ProductCode, MsiVersion und ConfiguredAt nach `HKLM\SOFTWARE\AbacusDeployment\Basis`. Der Abschlussmarker `PackageRevision=1` wird zuletzt geschrieben.

Die Registry-Einstellung steuert das automatische AbaClient-Update. Sie verhindert nicht unabhängig davon manuelle Updates oder andere Updatewege.

Das Basis-Script kopiert keine Productiv-/Archiv-Abalink und erstellt keine eigenen Server-Verknüpfungen. Es konfiguriert auch keine Edge-AutoOpenFileTypes-Richtlinie aus dem alten SCCM-Script. Vom MSI selbst eingerichtete Komponenten bleiben Sache des MSI.

### Deinstallation durch Uninstall.ps1

- Prüft auf die beiden Abalink-Dateien unter `C:\ProgramData\AbaClient` und die Productiv-/Archiv-Verknüpfungen im gemeinsamen Startmenü sowie auf dem öffentlichen Desktop.
- Sobald eine dieser Dateien noch vorhanden ist, bricht es mit **60001** ab. Zuerst Productiv und Archiv deinstallieren.
- Ermittelt den MSI-ProductCode aus dem Basis-Marker. Fehlt er dort, wird er aus der mitgelieferten MSI gelesen; deshalb die MSI auch im Deinstallationspaket behalten.
- Deinstalliert die registrierte AbaClient-MSI still mit `/qn /norestart` und prüft anschliessend deren Entfernung.
- Entfernt die eigenen Firewallregeln aus `AbacusDeployment - Basis` und den Basis-Registry-Schlüssel.
- Die Scripts löschen keine persönlichen Daten oder fremden Firewallregeln und setzen die Benutzerpräferenz für AutoUpdate nicht zurück. Welche MSI-eigenen Dateien entfernt werden, bestimmt das MSI.
- Logdateien bleiben erhalten.

### Logs und Fehleranalyse

Alle Logs liegen unter `C:\ProgramData\AbacusDeployment\Logs`.

| Datei | Inhalt |
| --- | --- |
| Basis-Install.log | Installations- und Konfigurationsschritte, MSI-Rückgabecode und Fehlerdetails |
| Basis-Install-Trace.log | Frühe Script-Ausführung, PowerShell-Version, Prozessarchitektur, PID, LanguageMode und markierte Einzelschritte |
| Basis-MSI-Install-YYYYMMDD-HHMMSS.log | Ausführliches MSI-Installationsprotokoll, wenn die MSI tatsächlich gestartet wird |
| Basis-Uninstall.log | Deinstallationsschritte und Fehlerdetails |
| Basis-Uninstall-Trace.log | Frühe Ausführung und markierte Schritte der Deinstallation |
| Basis-MSI-Uninstall-YYYYMMDD-HHMMSS.log | Ausführliches MSI-Deinstallationsprotokoll, wenn die MSI tatsächlich gestartet wird |

Die Script-Logs werden bei wiederholter Ausführung ergänzt. Die Sperrdatei `Basis.lock` wird im gleichen Ordner verwendet; entscheidend ist die aktive Dateisperre, nicht die blosse Existenz dieser Datei.

Wird PowerShell oder die PS1 bereits vor ihrer Ausführung blockiert, kann das Script noch kein Log schreiben. Dann die Intune-Logs unter `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs` und die zeitlich passenden Seculution-Ereignisse prüfen.

Die Scripts verwenden kein `-Command`, `-EncodedCommand`, `Add-Type` oder `DllImport`. Sie verwenden unter anderem WindowsInstaller-COM, `msiexec.exe`, `reg.exe`, Windows-/NET-Identitätsprüfungen und das Windows-Modul NetSecurity. Eigenständige Dateien erklären die von euch gefundene funktionierende Paketstruktur; sie beweisen allein nicht die technische Herkunft der früheren DllImport-Meldung.

## 3. Alle Intune-Einstellungen und Verpackung

### Intunewin erstellen

1. Die beiden eigenständigen Scripts korrekt umbenennen und zusammen mit der originalen MSI in `Abacus-Basis\Source` ablegen.
2. Im Ordner `Abacus-Basis` den folgenden Befehl ausführen. IntuneWinAppUtil.exe muss über den angegebenen Aufruf erreichbar sein:

```bat
IntuneWinAppUtil.exe -c ".\Source" -s "Install.ps1" -o ".\Output" -q
```

3. Die erzeugte `Output\Install.intunewin` als Paket der Basis-App hochladen. Output liegt ausserhalb von Source.
4. Bei der bestehenden App zusätzlich die Installations- und Deinstallationsbefehle ersetzen. Nur den Paketinhalt zu aktualisieren entfernt den alten CMD-Aufruf nicht.

Die Scripts haben neue beziehungsweise geänderte Hashes. Beide eigenständigen Dateien nach eurem bestehenden Seculution-Verfahren freigeben. Anschliessend auf einem sauberen Testgerät direkt über Intune prüfen.

### App-Informationen

| Einstellung | Wert |
| --- | --- |
| App-Typ | Windows-App (Win32) |
| Name | AbaClient Basis 4.3 |
| Beschreibung | Gemeinsamer AbaClient 4.3.1194 mit Benutzerpräferenzen und Java-Firewallregeln; Voraussetzung für Abacus Productiv und Abacus Archiv |
| Herausgeber | Abacus Research AG |
| App-Version | 4.3.1194 |
| Kategorie | keine |
| Als hervorgehobene App anzeigen | Nein |
| Informations-URL / Datenschutz-URL | [https://support.dannemann.com/#knowledge_base/1/locale/de-de/answer/389](https://support.dannemann.com/#knowledge_base/1/locale/de-de/answer/389) |
| Entwickler | Abacus Research AG |
| Besitzer | IT CH |
| Logo | optional |


### Programm

**Installer-Typ: Befehlszeile.** Je Vorgang wird PowerShell direkt aufgerufen; keine CMD und keine zweite PS1 laden.

Installationsbefehl:

```text
C:\Windows\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ".\Install.ps1"
```

Deinstallationsbefehl:

```text
C:\Windows\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ".\Uninstall.ps1"
```

Diese Befehle setzen Windows unter `C:\Windows` voraus. `Sysnative` ermöglicht dem 32-Bit-Intune-Aufruf den Start von 64-Bit-PowerShell. Für einen manuellen Test aus einem 64-Bit-Prozess stattdessen `System32` verwenden. Im Deinstallationsbefehl keine Umgebungsvariable einsetzen, da Intune dort keine Variablenexpansion unterstützt.

| Einstellung | Wert |
| --- | --- |
| Installationsverhalten | System |
| Installationszeit | 30 Minuten |
| Neustartverhalten | Verhalten anhand der Rückgabecodes bestimmen |
| Verfügbare Deinstallation zulassen | Nein für die gemeinsam benötigte Basis-App; bei Abhängigkeiten wird der Portal-Button ohnehin nicht angezeigt |

Rückgabecodes:

| Code | Intune-Typ | Bedeutung |
| --- | --- | --- |
| 0 | Erfolg | Basis erfolgreich eingerichtet beziehungsweise entfernt |
| 1707 | Erfolg | Standard-MSI-Erfolg; vom Script normalerweise auf 0 normalisiert |
| 3010 | Weicher Neustart | MSI erfolgreich, Neustart erforderlich |
| 1641 | Harter Neustart | Standard-MSI-Code; das vorliegende Script akzeptiert ihn nicht als erfolgreichen Abschluss, da `/norestart` verwendet wird. Als Standardzuordnung belassen. |
| 1618 | Wiederholen | MSI oder anderer Basis-Vorgang läuft bereits |
| 1 | Fehler | Script-/Konfigurationsfehler |
| 60001 | Fehler | Deinstallation blockiert: Productiv-/Archiv-Dateien noch vorhanden |

Andere nicht zugeordnete Rückgabecodes gelten als Fehler. `1605` bei einer MSI-Deinstallation wird intern als bereits entfernt akzeptiert und nicht als eigener erfolgreicher Script-Code ausgegeben. Ein Security-Fehler wie Exitcode 5 darf nicht als Erfolg zugeordnet werden.

### Anforderungen

| Einstellung | Wert |
| --- | --- |
| Betriebssystemarchitektur | x64 |
| Mindestbetriebssystem | Windows 11 21H2 |
| Mindestfreier Speicher / RAM / Prozessoranzahl / CPU-Takt | Keine zusätzlichen Regeln |
| Zusätzliche Anforderungsregeln | Keine |

Die Mindestversion ist die technische Paketanforderung. Für den produktiven Betrieb eine von euch unterstützte Windows-Version verwenden.

### Erkennungsregeln

**Regelformat: Erkennungsregeln manuell konfigurieren. Beide Regeln müssen erfüllt sein.** Keine PowerShell-Erkennungsdatei notwendig.

**Regel 1 – MSI:**

| Einstellung | Wert |
| --- | --- |
| Regeltyp | MSI |
| MSI-Produktcode | `{D1BEBC97-E763-418E-B999-BD5FD75A9BA5}` – aus der bestehenden SCCM-Konfiguration mitgeteilt; muss zur paketierten MSI gehören |
| MSI-Produktversionsprüfung | Nein |

Der tatsächliche ProductCode und die ProductVersion stehen beim Installationsstart in `Basis-Install.log`. `MsiVersion` im Basis-Registry-Schlüssel zeigt die erkannte installierte Version, die bei einer bereits neueren Installation abweichen kann. Die ProductVersion der paketierten MSI wurde nicht als separate Ausgabe mitgeteilt.

**Regel 2 – Basiskonfiguration:**

| Einstellung | Wert |
| --- | --- |
| Regeltyp | Registrierung |
| Schlüsselpfad | `HKEY_LOCAL_MACHINE\SOFTWARE\AbacusDeployment\Basis` |
| Wertname | `PackageRevision` |
| Erkennungsmethode | Zeichenfolgenvergleich |
| Operator | Gleich |
| Wert | `1` |
| Einer 32-Bit-App auf 64-Bit-Clients zugeordnet | Nein |

Diese zweite Regel sorgt dafür, dass eine vorhandene SCCM-MSI ohne unsere Basiskonfiguration noch nicht als fertig eingerichtet gilt.


### Abhängigkeiten, Ablösung und Bereichstags

- Die Basis-App erhält keine Abhängigkeit auf Productiv oder Archiv.
- In **Abacus Productiv** und **Abacus Archiv** jeweils **AbaClient Basis 4.3** als Abhängigkeit eintragen; automatisch installieren: **Ja**.
- Keine Ablösung zwischen Basis und den beiden Link-Apps.
- Bereichstags entsprechend euren bisherigen Berechtigungen.

### Zuweisungen

| Zweck | Gruppe |
| --- | --- |
| Required | Keine, wird mit Dependencie installiert |
| Uninstall | GROUP-M365-CH-APP-AbacusArchiv-Uninstall |
| Uninstall | GROUP-M365-CH-APP-AbacusProductiv-Uninstall |


Benachrichtigungen, Verfügbarkeit, Fristen und Bereitstellungsoptimierung entsprechend euren bestehenden Zuweisungen übernehmen. Für denselben Benutzer beziehungsweise dasselbe Gerät keine widersprüchliche Installations-/Deinstallationszuweisung setzen.

Das Entfernen einer Gruppenzugehörigkeit deinstalliert die App nicht automatisch. Auch die Deinstallation von Productiv/Archiv entfernt die Basis-Abhängigkeit nicht automatisch. Die Dateischutzprüfung in Uninstall.ps1 ist eine zusätzliche Sicherung und ersetzt keine korrekte Reihenfolge der Zuweisungen.

### Quellen

- [Microsoft: Win32-App hinzufügen und zuweisen](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- Die am 05.10.2026 bereitgestellten Dateien Install (2).ps1 und Uninstall(2).ps1 sowie die zuletzt übermittelten Intune-Paketlogs.
