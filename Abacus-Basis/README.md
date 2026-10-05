# AbaClient Basis fuer Intune

Dieses Paket installiert AbaClient und konfiguriert die gemeinsame Basis fuer
Abacus Productiv und Abacus Archiv. Ziel: Windows x64, Windows PowerShell 5.1,
Ausfuehrung als SYSTEM durch Intune. Es enthaelt keine Serververbindungen.

## Paket vervollstaendigen

Die MSI wurde nicht mitgeliefert. Kopiere deine Originaldatei
`abaclient-4.3.1194-de.msi` direkt in den Ordner `Source`.
`Abacus.exe`, `Programdata` und `Users` aus dem alten Paket werden nicht kopiert.

Alle fuenf Script-Dateien im Ordner `Source` muessen zusammenbleiben:

- Install.cmd
- Install.ps1
- Uninstall.cmd
- Uninstall.ps1
- Basis.Common.ps1

`Basis.Common.ps1` ist die gemeinsame Funktionsdatei. Sie wird nicht separat gestartet.
`Tools\Validate-Scripts.ps1` fuehrt nur die Syntaxpruefung aus.

## Installation

Intune-Installationsbefehl: `cmd.exe /c Install.cmd`

Die CMD waehlt 64-Bit-PowerShell sowohl aus einem 32-Bit-Intune-Prozess als auch
beim manuellen Start aus einer 64-Bit-Konsole. Die Installation:

1. Prueft x64-Kontext und Administratorrechte.
2. Liest ProductCode, ProductVersion und ProductName aus der MSI.
3. Entfernt einen bisherigen PackageRevision-Erkennungsmarker.
4. Installiert die MSI mit `/qn /norestart`, falls der ProductCode nicht bereits
   in gleicher oder hoeherer Version registriert ist. Eine bereits passende
   Installation wird nicht automatisch repariert; die Basiskonfiguration erfolgt trotzdem.
5. Schreibt `m/Auto/Update` als REG_SZ `false` unter
   `Software\JavaSoft\Prefs\abaclientsetting` in den Benutzer-Hives.
   Dieser Registry-Wert wird aus deinem bestehenden Script uebernommen.
6. Beruecksichtigt geladene Benutzer-Hives, vorhandene lokale/Domaenen-/Entra-
   Benutzerprofile mit NTUSER.DAT und das Default-Profil fuer neue Benutzer.
   Dienstprofile werden nicht konfiguriert. Gesperrte Hives fuehren zu einem
   Fehler; die App wird dann nicht als erfolgreich eingerichtet markiert.
7. Erstellt eingehende Allow-Regeln fuer vorhandene java.exe/javaw.exe unter
   `%ProgramFiles%\Abacus\AbaClient\jre`, `jre11`, `jre17`, `jre17-x64`, `jre21`.
   Alle Firewall-Profile werden beruecksichtigt, wie im bisherigen Script.
   Es muss mindestens eine dieser Runtimes vorhanden sein. Abweichende Pfade
   muessen in Basis.Common.ps1 angepasst werden. Zentral vorgegebene Firewall-
   Richtlinien koennen lokale Regeln uebersteuern; dies auf dem Testgeraet pruefen.
8. Schreibt den Erkennungsmarker erst nach erfolgreicher Konfiguration.

Die Update-Einstellung wird einmalig vorgegeben. Eine laufende Erzwingung gegen
Benutzeraenderungen ist nicht Bestandteil des Pakets. Nach dem Test im AbaClient
pruefen, dass der uebernommene Registry-Wert mit Version 4.3.1194 wirksam ist.

## Deinstallation

Intune-Deinstallationsbefehl: `cmd.exe /c Uninstall.cmd`

Die Deinstallation wird mit Code 60001 abgebrochen, wenn mindestens eine der
geplanten Productiv-/Archiv-Abalink-Dateien oder deren Startmenue-/Desktop-
Verknuepfungen noch existiert. Diese Apps zuerst deinstallieren.
Das ist eine Pruefung unserer sechs geplanten Dateipfade, keine allgemeine
Erkennung weiterer Abacus-Verbindungen oder laufender Sitzungen.

Der gespeicherte ProductCode wird mit `/x /qn /norestart` deinstalliert. Falls noch
keine Basis-Metadaten existieren, wird der ProductCode aus der beigelegten MSI gelesen.
Eine bereits fehlende MSI-Installation gilt als erfolgreich entfernt.
Das Script entfernt danach nur die eigene Firewall-Regelgruppe und den eigenen
Registry-Schluessel `HKLM\SOFTWARE\AbacusDeployment\Basis`.

Benutzer-Registry-Einstellungen bleiben erhalten: Der urspruengliche Update-Wert
ist nicht bekannt und wird nicht pauschal auf `true` zurueckgesetzt.
Logs und persoenliche Abacus-Daten bleiben ebenfalls erhalten.
Eine MSI-Deinstallation kann ihre eigenen, vom MSI verwalteten Dateien und
Verknuepfungen entfernen. Die beiden Serverdateien werden durch dieses Script
nicht geloescht.

## Intune-Erkennung

Fuehre nach dem Hinzufuegen der MSI aus:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Get-MsiInfo.ps1
```

Das Tool liest nur MSI-Metadaten; es installiert nichts. Verwende die Ausgabe
fuer die erste Erkennungsregel:

- Regeltyp MSI
- ProductCode aus der Ausgabe
- Versionspruefung Ja
- Operator Groesser oder gleich
- Version: ProductVersion aus der Ausgabe

Zweite Erkennungsregel:

- Regeltyp Registrierung
- Schluessel `HKEY_LOCAL_MACHINE\SOFTWARE\AbacusDeployment\Basis`
- Wertname `PackageRevision`
- Zeichenfolgenvergleich Gleich `1`
- Einer 32-Bit-App auf 64-Bit-Clients zugeordnet: Nein

Alle Regeln muessen erfuellt sein. Bereits per SCCM installierte Clients ohne
unseren Marker werden dadurch einmalig konfiguriert. Der Marker bestaetigt die
erfolgreiche Ausfuehrung, nicht die dauerhafte Unveraendertheit aller Einstellungen.

## Weitere Intune-Einstellungen

- App-Typ: Windows-App (Win32)
- Name: AbaClient Basis
- Herausgeber: Abacus Research AG
- Installertyp: Befehlszeile
- Installationsverhalten: System
- Architektur: x64
- Installationszeit: 30 Minuten
- Verfuegbare Deinstallation zulassen: Nein
- Neustartverhalten: Verhalten anhand von Rueckgabecodes bestimmen
- 0 und 1707: Erfolg
- 3010: Soft reboot
- 1641: Hard reboot
- 1618: Retry
- 60001: Fehlgeschlagen (optional explizit hinzufuegen; nicht als Erfolg behandeln)
- Keine Abhaengigkeiten und keine Abloesung fuer die Basis
- Zunaechst Required-Zuweisung nur an eine Testgeraetegruppe

Edge AutoOpenFileTypes wird separat ueber ein Intune-Konfigurationsprofil gesetzt.
Alte Abacus2026-Dateien und alte Firewall-Regeln werden nicht bereinigt. Damit
bleibt der bisherige Zugang fuer den schrittweisen Wechsel erhalten.
Alte SCCM-Zuweisungen duerfen die neue Konfiguration spaeter nicht ueberschreiben
oder die neuen Verbindungsdateien durch die alte Bereinigung entfernen.

## Verpacken

Nur `Source` mit dem Microsoft Win32 Content Prep Tool verpacken.
Setup-Datei: `Install.cmd`. Ausgabeordner ausserhalb von Source.
`Tools` und README muessen nicht in das Intune-Paket aufgenommen werden.

## Logs und Rueckgabecodes

Logs: `%ProgramData%\AbacusDeployment\Logs`

- Basis-Install.log
- Basis-Uninstall.log
- Basis-MSI-Install-<Zeitstempel>.log
- Basis-MSI-Uninstall-<Zeitstempel>.log

Der lokale Dateilock verhindert parallele Basis-Vorgaenge. MSI-Fehler werden
weitergegeben. Konfigurationsfehler liefern 1. Erfolg mit MSI-Neustartbedarf
liefert 3010. 1641 beendet den Vorgang ohne Konfigurationsmarker, damit die
Konfiguration nach einem Neustart erneut versucht werden kann.
Erfolgreiche 1707-Ausgaben werden auf 0 normalisiert.

## Pruefung vor der Verteilung

Die Dateien wurden unter Linux mit einem PowerShell-Grammatikparser statisch
geprueft. Eine echte Windows-/MSI-/Intune-Ausfuehrung war hier nicht moeglich.

Syntax zusaetzlich mit dem originalen Windows-PowerShell-Parser pruefen:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Validate-Scripts.ps1
```

Auf einem isolierten Testclient:

1. Install.cmd als Administrator oder ueber Intune als SYSTEM ausfuehren.
   MSI-Registrierung, Logs, Erkennungsmarker, Firewall-Regeln und Abalink-
   Dateizuordnung pruefen.
2. Bei einem angemeldeten sowie einem vorhandenen, nicht angemeldeten Benutzer
   im AbaClient pruefen, dass automatische Updates deaktiviert sind.
3. Ein neues Test-Benutzerprofil anlegen und dieselbe Einstellung pruefen.
4. Install.cmd erneut starten: erfolgreiche Basiskonfiguration ohne doppelte
   eigene Firewall-Regeln erwarten.
5. Bei vorhandenen geplanten Productiv-/Archiv-Dateien Uninstall.cmd starten:
   Abbruch mit 60001, Client bleibt installiert.
6. Ohne diese Dateien deinstallieren: MSI, eigener Marker und eigene Regeln
   verschwinden. Erneute Deinstallation ist ebenfalls erfolgreich.

## Referenzen

- https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32
- https://learn.microsoft.com/en-us/intune/app-management/deployment/create-win32-package
- https://downloads.abacus.ch/fileadmin/ablage/dokumente/05_abaclient/AbaClient_4.1-Referenz_DE.pdf
