# Abacus – Intune-Pakete

Die Bereitstellung besteht aus drei separaten Win32-Apps:

| Paket | Aufgabe |
|---|---|
| AbaClient Basis | Installiert den Client und richtet Update-Einstellung, Firewall-Regeln und Basiskonfiguration ein. |
| Abacus Productiv | Verteilt die Verbindung zu **DCHABAC02** und erstellt die Verknüpfungen **Abacus Productiv**. |
| Abacus Archiv | Verteilt die Verbindung zu **DCHABACARCHIV01** und erstellt die Verknüpfungen **Abacus Archiv**. |

Productiv und Archiv erhalten in Intune **AbaClient Basis** als Abhängigkeit mit **Automatisch installieren: Ja**. Alle Apps laufen im SYSTEM-Kontext. Die Detail-READMEs enthalten die Dateien, Abläufe und vollständigen Intune-Einstellungen. Diese Haupt-README neben den drei Detail-READMEs ablegen.

## Installation

1. Gerät auf welchem die gewünschte App installiert werden soll, in Gruppe "GROUP-M365-CH-APP-AbacusArchiv" oder "GROUP-M365-CH-APP-AbacusProductiv" hinzufügen.
2. Aufgrund der Dependencie wird zuerst die Basis installiert.
3. Danach wird die entsprechende Abalink installiert.
4. Beide Gruppen können gleichzeitig inem Gerät hinzugefügt werden.

## Deinstallation

1. Gerät auf welchem die gewünschte App deinstalliert werden soll, in Gruppe "GROUP-M365-CH-APP-AbacusArchiv-Uninstall" oder "GROUP-M365-CH-APP-AbacusProductiv-Uninstall" hinzufügen.
2. Die Abalink wird deinstalliert.
3. Die Basis wird ebenfalls deinstalliert, wenn das Gerät in keiner der beiden Installations-Gruppen mehr ist.

## .intunewin erstellen

1. Die Original-MSI in `Abacus-Basis\Source` und die geprüften Verbindungsdateien in `Abacus-Productiv\Source\Files\AbacusProductiv.abalink` beziehungsweise `Abacus-Archiv\Source\Files\AbacusArchiv.abalink` ergänzen. Die Paket-Scripts müssen vollständig enthalten sein.
2. Das [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) herunterladen und `IntuneWinAppUtil.exe` ausserhalb der Source-Ordner ablegen.
3. Das Tool für jedes Paket separat starten und folgende Angaben verwenden. Beispielablage: `C:\Abacus`.

| Abfrage | Basis | Productiv | Archiv |
|---|---|---|---|
| Source folder | `C:\Abacus\Abacus-Basis\Source` | `C:\Abacus\Abacus-Productiv\Source` | `C:\Abacus\Abacus-Archiv\Source` |
| Setup file | `Install.ps1` | `Install.ps1` | `Install.ps1` |
| Output folder | `C:\Abacus\Output\Basis` | `C:\Abacus\Output\Productiv` | `C:\Abacus\Output\Archiv` |
| Catalog folder | `N` | `N` | `N` |

Das Tool verpackt den gesamten jeweiligen Source-Ordner inklusive Unterordnern. Die drei getrennt erzeugten `Install.intunewin` in Intune als **Windows-App (Win32)** hochladen und gemäss der jeweiligen Detail-README konfigurieren. READMEs gehören nicht in die Source-Ordner.
