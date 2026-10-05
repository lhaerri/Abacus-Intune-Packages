# Abacus Archiv – eigenstaendige PowerShell-App

## 1. Kurze Uebersicht

Richtet Abacus Archiv fuer DCHABACARCHIV01 ein. AbaClient Basis muss bereits installiert und konfiguriert sein. Je Vorgang wird genau eine eigenstaendige PowerShell-Datei direkt gestartet.

## 2. Was wird installiert und eingerichtet?

| Datei im Paket | Aufgabe |
| --- | --- |
| Source/Install.ps1 | Prueft 64-Bit und Administratorrechte sowie Basis-Marker und MSI-Registrierung. Kopiert die Abalink, erstellt und prueft beide Verknuepfungen und schreibt den Erkennungsmarker zuletzt. Alle Funktionen sind eingebaut. |
| Source/Uninstall.ps1 | Entfernt ausschliesslich die eigene Abalink, beide eigenen Verknuepfungen und den eigenen Registry-Schluessel. Basis und die andere Link-App bleiben erhalten. Alle Funktionen sind eingebaut. |
| Source/Files/AbacusArchiv.abalink | **Vor dem Verpacken selbst ergaenzen:** eure originale Verbindung zu DCHABACARCHIV01. Diese Datei wurde nicht angehaengt und ist nicht im Download enthalten. |

Installationsziele:

- `C:\ProgramData\AbaClient\AbacusArchiv.abalink`
- `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\AbaClient\Abacus Archiv.lnk`
- `C:\Users\Public\Desktop\Abacus Archiv.lnk`
- Registry: `HKLM\SOFTWARE\AbacusDeployment\Archiv` mit PackageRevision (REG_SZ) = 1, ExpectedServer, AbalinkSHA256 und ConfiguredAt.

Die Abalink wird unveraendert kopiert und per SHA256 verglichen. Ihr Serverinhalt wird nicht umgeschrieben oder auf DCHABACARCHIV01 geprueft. ExpectedServer ist Dokumentation im Registry-Marker. Deshalb die echte Abalink vorher inhaltlich beziehungsweise durch Oeffnen pruefen.

Logs unter `C:\ProgramData\AbacusDeployment\Logs`: `Archiv-Install.log`, `Archiv-Install-Trace.log`, `Archiv-Uninstall.log`, `Archiv-Uninstall-Trace.log`. Die Trace-Logs beginnen vor der Umgebungspruefung, entsprechend der bereitgestellten Basis-App. Ein blockierter PowerShell-Start kann noch keine Script-Logs erzeugen.

Es gibt keine CMD- oder Common-Datei, kein Dot-Sourcing, keinen weiteren PowerShell-Prozess und keine Verwendung von -Command, -EncodedCommand, Add-Type oder DllImport. WScript.Shell wird als COM-Objekt fuer Verknuepfungen verwendet, nicht als separater Script-Prozess gestartet.

## 3. Intune-Einstellungen und Verpackung

Die vorhandene App aktualisieren: neue Paketdatei hochladen und beide Befehle ersetzen. Die bisherigen Erkennungsmarker bleiben kompatibel. Bereits erkannte Installationen werden durch diese Aenderung allein nicht erneut ausgefuehrt.

### Verpackung

Im Ordner `Abacus-Archiv` ausfuehren (IntuneWinAppUtil.exe muss erreichbar sein):

```bat
IntuneWinAppUtil.exe -c ".\Source" -s "Install.ps1" -o ".\Output" -q
```

Vorher `Source\Files\AbacusArchiv.abalink` ergaenzen. Setup-Datei ist Install.ps1. Output liegt ausserhalb von Source. Das erzeugte Install.intunewin in die passende App hochladen.

### App-Informationen

- Typ: Windows-App (Win32).
- Name: Abacus Archiv.
- Beschreibung: Verbindung zu DCHABACARCHIV01; benoetigt AbaClient Basis.
- Herausgeber: Abacus.
- Version: 1, entsprechend PackageRevision; optional.
- Kategorie, Logo, Besitzer, URLs und Bereichstags: nach euren bisherigen Einstellungen.

### Programm

Installer-Typ: Befehlszeile. PowerShell direkt aufrufen, ohne CMD:

Installation:

```text
C:\Windows\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ".\Install.ps1"
```

Deinstallation:

```text
C:\Windows\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ".\Uninstall.ps1"
```

Diese Befehle setzen Windows unter C:\Windows voraus und sind fuer den Intune-Aufruf aus einem 32-Bit-Prozess gedacht. Fuer einen manuellen Test aus 64-Bit-PowerShell stattdessen System32 verwenden. Fuer den Deinstallationsbefehl keine Umgebungsvariable verwenden.

| Einstellung | Wert |
| --- | --- |
| Installationsverhalten | System |
| Installationszeit | 10 Minuten |
| Neustartverhalten | Keine bestimmte Aktion |
| Verfuegbare Deinstallation zulassen | Nach bisheriger Einstellung; bei Abhaengigkeiten kann der Portal-Button fehlen |
| Rueckgabecode 0 | Erfolg |
| Rueckgabecode 1 | Fehler |
| Rueckgabecode 1618 | Wiederholen (gleichzeitiger Vorgang) |
| Rueckgabecode 60002 | Fehler (Basis fehlt oder ist unvollstaendig) |

### Anforderungen

- Architektur: x64; die Scripts verlangen einen 64-Bit-PowerShell-Prozess.
- Mindestbetriebssystem: Windows 11 21H2, entsprechend der bisherigen Paketkonfiguration. Fuer den Betrieb eine von euch unterstuetzte Windows-Version verwenden.
- Keine weiteren Anforderungen.

### Erkennungsregeln

Manuell konfigurieren. **Alle vier Regeln muessen erfuellt sein.** Bei jeder Regel den 32-Bit-Schalter auf Nein setzen.

| Typ | Pfad | Name | Pruefung |
| --- | --- | --- | --- |
| Registry | HKEY_LOCAL_MACHINE\SOFTWARE\AbacusDeployment\Archiv | PackageRevision | Zeichenfolgenvergleich: gleich 1 |
| Datei | C:\ProgramData\AbaClient | AbacusArchiv.abalink | Datei vorhanden |
| Datei | C:\ProgramData\Microsoft\Windows\Start Menu\Programs\AbaClient | Abacus Archiv.lnk | Datei vorhanden |
| Datei | C:\Users\Public\Desktop | Abacus Archiv.lnk | Datei vorhanden |

### Abhaengigkeiten und Zuweisungen

- AbaClient Basis 4.3 als Abhaengigkeit, automatisch installieren: Ja.
- Keine Ablösung zwischen Productiv und Archiv; beide koennen parallel installiert sein.
- Erforderlich: `GROUP-M365-CH-APP-AbacusArchiv`, entsprechend eurer bestehenden Zuweisung.
- Deinstallieren nur ueber eure separate Deinstallationsgruppe; fuer dasselbe Ziel keine widerspruechliche Installations-/Deinstallationszuweisung.
- Zum ersten Test auf die Testgruppe begrenzen.

Die neuen Install.ps1 und Uninstall.ps1 gemaess eurem bestehenden Seculution-Verfahren freigeben. Eine erfolgreiche Syntaxpruefung ersetzt keinen Windows-/Intune-/Seculution-Test.

Quelle fuer direkte 64-Bit-PowerShell-Aufrufe und Intune-Einstellungen: https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32
