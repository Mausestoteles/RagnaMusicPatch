# RagnaMusic Patch

Bringt das Aussehen von RagnaMusic in den Spotify-Desktop-Client: dunkle Flächen, Bernstein
als Akzent, die Schriften von RagnaMusic, Einfärben nach dem Cover und oben rechts das Badge
**RagnaPatched** mit eingebautem Theme-Umschalter und Update-Hinweis.

Der Patch kombiniert zwei bestehende Projekte und lädt beide bei jedem Lauf frisch von GitHub:

- [SpotX](https://github.com/SpotX-Official/SpotX) (MIT): patcht den Spotify-Client
  (Werbung, Update-Sperre, Startseite ohne Podcasts)
- [Spicetify](https://github.com/spicetify/cli) (LGPL-2.1): spielt das Theme auf

## Benutzung

1. [Neueste `RagnaMusicPatch.zip`](https://github.com/Mausestoteles/RagnaMusicPatch/releases/latest)
   herunterladen und entpacken.
2. **`Start Patch.bat`** doppelklicken.
3. Warten, bis Spotify neu startet. Oben rechts steht dann **RagnaPatched**.

Voraussetzungen: Windows 10 oder 11, Internetverbindung. Spotify muss nicht installiert sein,
SpotX installiert dann die Desktop-Version.

Entfernen: **`Uninstall Patch.bat`** oder Startmenü → RagnaMusic Patch → **RagnaMusic Patch
entfernen**. Spotify läuft danach wieder im Originalzustand.

## Updates

Gibt es eine neue Version, erscheint in Spotify unten rechts **Update verfügbar** und am Badge
ein Punkt. **Updaten** lädt die neue Version, prüft ihre Prüfsumme und spielt sie auf; Spotify
startet danach neu. Deine Theme-Einstellungen bleiben erhalten.

Ohne Knopf geht es auch:

- Startmenü → RagnaMusic Patch → **RagnaMusic Patch aktualisieren**
- **`Update Patch.bat`** aus der Zip. Das ist der Weg für ältere Installationen (0.1.0), die
  den Updater noch nicht haben.

Ist Spotify noch gepatcht, wird nur das Theme erneuert. Hat ein Spotify-Update den Patch
entfernt, läuft der komplette Patch.

## Theme wechseln

Ein Klick auf **RagnaPatched** (oder Profilmenü → **RagnaMusic Theme**) öffnet den
Umschalter. Jede Wahl wirkt sofort und bleibt nach einem Neustart von Spotify erhalten:

- **Farbschema:** Dunkel, Hell, OLED (reines Schwarz) sowie Vertraut, Ähnlich und Entdecken
  in den Farben der drei RagnaMusic-Algorithmen
- **Eigenes Theme:** Basis (Dunkel, Hell, OLED) plus eine beliebige Akzentfarbe über
  Farbwähler, Hex-Wert oder Schnellauswahl. Zu dunkle oder zu helle Akzente werden
  automatisch so angepasst, dass sie lesbar bleiben.
- **Nach Cover einfärben:** an oder aus
- **Zurücksetzen:** zurück zum Farbschema, mit dem gepatcht wurde

Unten im Umschalter stehen die Patch-Details und **Nach Updates suchen**.

## Optionen

Optionen werden an `Start Patch.bat` angehängt (oder direkt an `patch.ps1`):

| Option | Wirkung |
|---|---|
| `-Scheme light` | startet im hellen Farbschema (später jederzeit im Umschalter änderbar) |
| `-ThemeOnly` | nur das Theme neu aufspielen, SpotX nicht erneut ausführen |
| `-Update` | neueste Version holen und aufspielen (wie `Update Patch.bat`) |
| `-Premium` | SpotX ohne Werbeblocker (für Premium-Konten) |
| `-KeepPodcasts` | Podcasts und Hörbücher auf der Startseite lassen |
| `-AllowUpdates` | Spotify-Updates nicht sperren (danach Patch erneut ausführen) |
| `-DefenderExclusions` | SpotX darf Ausnahmen in Microsoft Defender eintragen |
| `-SpotXRef <commit>` | bestimmte SpotX-Version statt `main` |
| `-SpicetifyVersion 2.45.3` | bestimmte Spicetify-Version bei der Installation |
| `-Yes` | keine Rückfragen |
| `-Uninstall [-RemoveSpicetify]` | Patch entfernen, optional auch Spicetify selbst |

Beispiel: `"Start Patch.bat" -Scheme light`

## Gut zu wissen

- **Microsoft-Store-Version:** SpotX und Spicetify brauchen die Desktop-Version. Der Patch
  fragt nach und ersetzt die Store-Version; danach einmal neu bei Spotify anmelden.
- **Smart App Control (Windows 11):** blockiert den Patch. SpotX entfernt außerdem die
  Signaturen von Spotify, mit eingeschaltetem Smart App Control startet Spotify danach nicht
  mehr. Abschalten lässt es sich unter Windows-Sicherheit → App- & Browsersteuerung; bei vielen
  Windows-Versionen geht es danach nur per Neuinstallation wieder an. Auf Firmen-PCs die IT
  fragen.
- **Administratorrechte:** Spicetify rät davon ab. Läuft der Patch als Administrator, Spotify
  später aber ohne, kann das Fenster schwarz bleiben. Am besten als normaler Benutzer starten.
- **Spotify-Updates** sind standardmäßig gesperrt, weil ein Update den Patch entfernt. Wer sie
  erlaubt, führt danach einfach `Update Patch.bat` aus.
- **Nach Spotify-Änderungen** kann einzelnes Styling ausfallen; Spotify zeigt dann an diesen
  Stellen sein eigenes Aussehen.
- SpotX verändert den offiziellen Client; die Nutzung erfolgt auf eigenes Risiko und kann gegen
  die Nutzungsbedingungen von Spotify verstoßen.

## Inhalt

```
RagnaMusicPatch/
├── Start Patch.bat         Patch starten
├── Update Patch.bat        neueste Version holen und aufspielen
├── Uninstall Patch.bat     Patch entfernen
├── patch.ps1               eigentlicher Patcher und Updater
├── ragna.ico               Symbol für Startmenü und ragnapatch://
└── theme/RagnaMusic/       Spicetify-Theme
    ├── color.ini           Farbschemata dark und light (aus RagnaMusic tokens.css)
    ├── user.css            Schriften, Akzente, Einfärben, Badge, Umschalter, Update-Hinweis
    ├── theme.js            Badge, Theme-Umschalter, Update-Prüfung, Farbe nach Cover
    └── assets/ragna/       Logo und Schriften (SIL Open Font License, siehe fonts/)
```

Der Patch richtet außerdem ein: eine Kopie in `%LOCALAPPDATA%\RagnaMusicPatch`, das
Link-Protokoll `ragnapatch://` (startet nur das Update) und zwei Startmenü-Einträge. Die
Deinstallation entfernt alles wieder.

## Neue Version veröffentlichen

1. `$PatchVersion` in `patch.ps1` erhöhen, z. B. auf `0.3.0`.
2. Committen, Tag `v0.3.0` setzen und pushen. Der Workflow `.github/workflows/release.yml`
   baut daraus mit `tools/build-zip.ps1` die Zip samt Prüfsumme und legt das Release an.
3. Ohne GitHub Actions: `tools\build-zip.ps1` lokal ausführen und die beiden Dateien aus
   `dist\` von Hand an ein Release `v0.3.0` hängen.

Spotify meldet die neue Version spätestens nach sechs Stunden oder sofort über
**Nach Updates suchen**.
