<#
.SYNOPSIS
  RagnaMusic Patch: SpotX + Spicetify + RagnaMusic-Theme für den Spotify-Desktop-Client.

.DESCRIPTION
  Ablauf:
    1. Spotify beenden. Ist Spicetify schon aktiv, zuerst „spicetify restore“
       (SpotX bricht sonst ab).
    2. SpotX in der aktuellen Version von GitHub laden und ausführen. Es installiert bei
       Bedarf den Spotify-Desktop-Client und patcht ihn.
    3. Spotify einmal starten, damit die Datei „prefs“ entsteht (braucht Spicetify).
    4. Spicetify installieren (Release-Zip von GitHub), falls es fehlt.
    5. Theme „RagnaMusic“ ins Spicetify-Verzeichnis kopieren, aktivieren und anwenden.

  SpotX und Spicetify werden nicht mitgeliefert, sondern jedes Mal von ihren offiziellen
  GitHub-Seiten geladen. So passen sie immer zur aktuellen Spotify-Version.

  Danach richtet der Patch den Updater ein: Kopie nach %LOCALAPPDATA%\RagnaMusicPatch,
  Link-Protokoll ragnapatch:// (Knopf „Updaten“ in Spotify) und Startmenü-Einträge.

.PARAMETER Scheme
  Farbschema: dark (Standard) oder light.

.PARAMETER Premium
  SpotX ohne Werbeblocker installieren (für Premium-Konten).

.PARAMETER KeepPodcasts
  Podcasts und Hörbücher auf der Startseite lassen.

.PARAMETER AllowUpdates
  Spotify-Updates nicht blockieren. Nach jedem Update muss der Patch neu laufen.

.PARAMETER DefenderExclusions
  SpotX darf Ausnahmen für Spotify in Microsoft Defender eintragen.

.PARAMETER ThemeOnly
  Nur das Theme neu aufspielen, SpotX nicht erneut ausführen.

.PARAMETER Update
  Neueste Version von GitHub holen (Prüfsumme wird geprüft) und aufspielen. Ist Spotify
  noch gepatcht, wird nur das Theme erneuert, sonst läuft der komplette Patch. Funktioniert
  auch für Installationen von 0.1.0, die noch keinen Updater haben.

.PARAMETER NoDownload
  Mit -Update: nicht auf GitHub nachsehen, sondern dieses Paket installieren.

.PARAMETER UpdateRepo
  GitHub-Repo mit den Releases (Standard: Mausestoteles/RagnaMusicPatch).

.PARAMETER WaitAtEnd
  Fenster am Ende offen lassen (für Start über ragnapatch:// ohne .bat).

.PARAMETER Uninstall
  Spicetify und SpotX wieder entfernen, Spotify läuft danach im Originalzustand.

.PARAMETER RemoveSpicetify
  Mit -Uninstall: auch das Programm Spicetify und seine Einstellungen löschen.

.PARAMETER SpotXRef
  Branch oder Commit von SpotX (Standard: main).

.PARAMETER SpicetifyVersion
  Spicetify-Version für eine Neuinstallation, z. B. 2.45.3 (Standard: neueste).

.PARAMETER Yes
  Alle Rückfragen mit Ja beantworten.

.EXAMPLE
  .\patch.ps1
  .\patch.ps1 -Scheme light
  .\patch.ps1 -ThemeOnly
  .\patch.ps1 -Update
  .\patch.ps1 -Uninstall -RemoveSpicetify
#>
[CmdletBinding()]
param(
    [ValidateSet('dark', 'light')]
    [string]$Scheme = 'dark',
    [switch]$Premium,
    [switch]$KeepPodcasts,
    [switch]$AllowUpdates,
    [switch]$DefenderExclusions,
    [switch]$ThemeOnly,
    [switch]$Update,
    [switch]$NoDownload,
    [string]$UpdateRepo = 'Mausestoteles/RagnaMusicPatch',
    [switch]$WaitAtEnd,
    [switch]$Uninstall,
    [switch]$RemoveSpicetify,
    [string]$SpotXRef = 'main',
    [string]$SpicetifyVersion,
    [switch]$Yes
)

# beim Update soll das zuletzt gewählte Schema bleiben, außer es wird ausdrücklich angegeben
$SchemeGiven = $PSBoundParameters.ContainsKey('Scheme')

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PatchVersion = '0.2.1'
$ThemeName = 'RagnaMusic'
$PatcherRoot = $PSScriptRoot
$ThemeSource = Join-Path $PatcherRoot "theme\$ThemeName"
$SpotifyDir = Join-Path $env:APPDATA 'Spotify'
$SpotifyExe = Join-Path $SpotifyDir 'Spotify.exe'
$SpotifyPrefs = Join-Path $SpotifyDir 'prefs'
$SpicetifyDir = Join-Path $env:LOCALAPPDATA 'spicetify'
$SpicetifyUserData = Join-Path $env:APPDATA 'spicetify'
$StoreSpotifyName = 'SpotifyAB.SpotifyMusic'
$InstallDir = Join-Path $env:LOCALAPPDATA 'RagnaMusicPatch'
$ProtocolName = 'ragnapatch'
$StartMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\RagnaMusic Patch'
# was zum Patcher gehört; dieselbe Liste nutzt tools\build-zip.ps1 für das Release
$PatcherFiles = 'patch.ps1', 'README.md', 'ragna.ico', 'Start Patch.bat', 'Update Patch.bat', 'Uninstall Patch.bat', 'theme'

# ---------- Ausgabe ----------

function Write-Banner {
    Write-Host ''
    Write-Host '  ┌───┐' -ForegroundColor DarkYellow
    Write-Host '  │ R │  ' -ForegroundColor DarkYellow -NoNewline
    Write-Host 'Ragna' -ForegroundColor Yellow -NoNewline
    Write-Host "Music Patch $PatchVersion" -ForegroundColor White
    Write-Host '  └───┘  SpotX + Spicetify + RagnaMusic-Theme' -ForegroundColor DarkYellow
    Write-Host ''
}

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "» $Text" -ForegroundColor Yellow
}

function Write-Ok([string]$Text) {
    Write-Host "  √ $Text" -ForegroundColor Green
}

function Write-Info([string]$Text) {
    Write-Host "  $Text" -ForegroundColor Gray
}

function Write-Warn([string]$Text) {
    Write-Host "  ! $Text" -ForegroundColor DarkYellow
}

function Write-Fail([string]$Text) {
    Write-Host "  × $Text" -ForegroundColor Red
}

# Ausgabe von Spicetify im Stil des Patchers: Farbcodes und Spinner raus, Füllzeilen weg
function Write-ToolLine([string]$Line) {
    $text = $Line -replace '\x1b\[[0-9;?]*[A-Za-z]', ''
    $text = ($text -split "`r" | Where-Object { $_.Trim() } | Select-Object -Last 1)
    if (-not $text) { return }
    $text = $text.Trim()
    if ($text -match '^spicetify v\d' -or $text -match 'to apply new config' -or $text -match '^[▀▄█⠀-⣿]') { return }
    switch -Regex ($text) {
        '^(?:success|ok)\s+(.+)$' { Write-Ok $Matches[1]; return }
        '^(?:info|note)\s+(.+)$' { Write-Info $Matches[1]; return }
        '^(?:warning|warn)\s+(.+)$' { Write-Warn $Matches[1]; return }
        '^(?:error|fatal)\s+(.+)$' { Write-Fail $Matches[1]; return }
        default { Write-Info $text }
    }
}

function Confirm-Step([string]$Question) {
    if ($Yes) { return $true }
    while ($true) {
        $raw = Read-Host "  $Question [j/n]"
        # keine Eingabe möglich (z. B. umgeleitete Konsole): als Nein werten
        if ($null -eq $raw) { return $false }
        $answer = $raw.Trim().ToLower()
        if ($answer -in 'j', 'ja', 'y', 'yes') { return $true }
        if ($answer -in 'n', 'nein', 'no') { return $false }
    }
}

# ---------- Spotify ----------

function Test-Elevated {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-Spotify {
    $processes = Get-Process -Name 'Spotify' -ErrorAction SilentlyContinue
    if (-not $processes) { return }
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20 -and (Get-Process -Name 'Spotify' -ErrorAction SilentlyContinue); $i++) {
        Start-Sleep -Milliseconds 250
    }
    Write-Ok 'Spotify beendet'
}

# Ersetzt eine Datei durch ihre Sicherung. Ist die Datei noch gesperrt (Spotify beendet
# sich gerade, Virenscanner prüft sie), wird bis zu 10 s lang erneut versucht.
function Restore-Backup([string]$Backup, [string]$Target) {
    for ($i = 0; $i -lt 20; $i++) {
        try {
            Move-Item -LiteralPath $Backup -Destination $Target -Force -ErrorAction Stop
            return $true
        }
        catch {
            Stop-Spotify
            Start-Sleep -Milliseconds 500
        }
    }
    $false
}

function Get-SpotifyVersion {
    if (-not (Test-Path -LiteralPath $SpotifyExe)) { return $null }
    (Get-Item -LiteralPath $SpotifyExe).VersionInfo.ProductVersion
}

function Test-Spicetified {
    # Spicetify entpackt xpui.spa in einen Ordner; daran erkennt auch SpotX den Zustand
    Test-Path -LiteralPath (Join-Path $SpotifyDir 'Apps\xpui\xpui.js')
}

# Spicetify braucht die Datei „prefs“, die Spotify erst beim ersten Start anlegt
function Initialize-SpotifyPrefs {
    if (Test-Path -LiteralPath $SpotifyPrefs) { return }
    Write-Info 'Spotify startet einmal kurz, damit seine Einstellungen entstehen …'
    Start-Process -FilePath $SpotifyExe | Out-Null
    for ($i = 0; $i -lt 120 -and -not (Test-Path -LiteralPath $SpotifyPrefs); $i++) {
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 3
    Stop-Spotify
    if (-not (Test-Path -LiteralPath $SpotifyPrefs)) {
        throw 'Spotify hat keine Datei „prefs“ angelegt. Bitte Spotify einmal starten, anmelden und den Patch danach erneut ausführen.'
    }
    Write-Ok 'Spotify-Einstellungen angelegt'
}

# ---------- SpotX ----------

function Invoke-SpotX {
    $storeSpotify = Get-AppxPackage -Name $StoreSpotifyName -ErrorAction SilentlyContinue

    $spotxArgs = @('-new_theme', '-confirm_spoti_recomended_over', '-adsections_off', '-no_pause')
    $spotxArgs += $(if ($KeepPodcasts) { '-podcasts_on' } else { '-podcasts_off' })
    $spotxArgs += $(if ($AllowUpdates) { '-block_update_off' } else { '-block_update_on' })
    if (-not $DefenderExclusions) { $spotxArgs += '-defender_exclusions_off' }
    if ($Premium) { $spotxArgs += '-premium' }

    if ($storeSpotify) {
        Write-Warn 'Spotify ist aus dem Microsoft Store installiert. SpotX und Spicetify brauchen die Desktop-Version.'
        Write-Info 'Die Store-Version wird entfernt und durch die Desktop-Version ersetzt. Danach einmal neu anmelden.'
        if (-not (Confirm-Step 'Store-Version entfernen und Desktop-Version installieren?')) {
            throw 'Abgebrochen: Mit der Store-Version von Spotify funktioniert der Patch nicht.'
        }
        $spotxArgs += '-confirm_uninstall_ms_spoti'
    }

    $url = "https://raw.githubusercontent.com/SpotX-Official/SpotX/$SpotXRef/run.ps1"
    $script = Join-Path ([IO.Path]::GetTempPath()) "ragna-spotx-$PID.ps1"
    Write-Info "Lade SpotX ($SpotXRef) …"
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing
    $source = [Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray()).TrimStart([char]0xFEFF)
    # Willkommens-Banner von SpotX ausblenden; Status und Fortschritt bleiben unverändert
    $source = $source -replace '(?m)^Write-Host \(\$lang\)\.Welcome[ \t]*\r?\n[ \t]*Write-Host[ \t]*\r?$', '# Banner ausgeblendet (RagnaMusic Patch)'
    # mit BOM, sonst liest Windows PowerShell 5.1 die Datei als ANSI
    [IO.File]::WriteAllText($script, $source, (New-Object Text.UTF8Encoding $true))
    try {
        Write-Info "Starte SpotX mit: $($spotxArgs -join ' ')"
        Write-Host ''
        # eigener Prozess, damit ein „exit“ in SpotX nicht diesen Patcher beendet
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script @spotxArgs
        $code = $LASTEXITCODE
    }
    finally {
        Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue
    }

    if ($code -ne 0) { throw "SpotX ist mit Code $code beendet worden." }
    if (-not (Test-Path -LiteralPath $SpotifyExe) -or -not (Test-Path -LiteralPath (Join-Path $SpotifyDir 'Apps\xpui.spa'))) {
        throw 'SpotX ist durchgelaufen, aber Spotify ist nicht vollständig installiert. Ausgabe oben prüfen.'
    }
    Write-Ok 'SpotX angewendet'
}

# ---------- Spicetify ----------

function Get-SpicetifyExe {
    $local = Join-Path $SpicetifyDir 'spicetify.exe'
    if (Test-Path -LiteralPath $local) { return $local }
    $cmd = Get-Command -Name 'spicetify' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $null
}

function Install-Spicetify {
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        default { 'x32' }
    }
    $version = $SpicetifyVersion
    if (-not $version) {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/spicetify/cli/releases/latest' -UseBasicParsing
        $version = $release.tag_name -replace '^v', ''
    }
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Ungültige Spicetify-Version: $version" }

    $zip = Join-Path ([IO.Path]::GetTempPath()) "ragna-spicetify-$PID.zip"
    Write-Info "Lade Spicetify $version ($arch) …"
    Invoke-WebRequest -Uri "https://github.com/spicetify/cli/releases/download/v$version/spicetify-$version-windows-$arch.zip" -OutFile $zip -UseBasicParsing
    try {
        New-Item -ItemType Directory -Force -Path $SpicetifyDir | Out-Null
        Expand-Archive -Path $zip -DestinationPath $SpicetifyDir -Force
    }
    finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    }

    # wie das offizielle Installationsskript: in den PATH des Benutzers aufnehmen
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if (($userPath -split ';') -notcontains $SpicetifyDir) {
        [Environment]::SetEnvironmentVariable('PATH', (($userPath.TrimEnd(';'), $SpicetifyDir) -join ';').TrimStart(';'), 'User')
    }
    if (($env:PATH -split ';') -notcontains $SpicetifyDir) { $env:PATH = "$env:PATH;$SpicetifyDir" }

    Write-Ok "Spicetify $version installiert"
    Join-Path $SpicetifyDir 'spicetify.exe'
}

function Invoke-Spicetify {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $all = @($Arguments)
    # Spicetify verweigert sonst den Start mit Administratorrechten
    if ($script:BypassAdmin) { $all += '--bypass-admin' }
    & $script:Spicetify @all | ForEach-Object { Write-ToolLine $_ }
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $message = "spicetify $($Arguments -join ' ') ist mit Code $code fehlgeschlagen."
        if ($AllowFailure) { Write-Warn $message } else { throw $message }
    }
}

function Get-SpicetifyCliVersion {
    $out = & $script:Spicetify -v 2>$null | Select-Object -Last 1
    if ($out) { "$out".Trim() } else { $null }
}

function Install-Theme {
    $themes = Join-Path $SpicetifyUserData 'Themes'
    $target = Join-Path $themes $ThemeName
    New-Item -ItemType Directory -Force -Path $themes | Out-Null
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    Copy-Item -LiteralPath $ThemeSource -Destination $target -Recurse

    # Patch-Daten für das Badge „RagnaPatched“
    $info = [ordered]@{
        patchVersion     = $PatchVersion
        patchedAt        = (Get-Date -Format 'dd.MM.yyyy HH:mm')
        scheme           = $Scheme
        spotxRef         = $SpotXRef
        spicetifyVersion = Get-SpicetifyCliVersion
        spotifyVersion   = Get-SpotifyVersion
        updateRepo       = $UpdateRepo
    } | ConvertTo-Json -Compress
    $themeJs = Join-Path $target 'theme.js'
    $content = [IO.File]::ReadAllText($themeJs)
    $content = $content.Replace('/*RAGNA_PATCH_INFO*/ null', $info)
    [IO.File]::WriteAllText($themeJs, $content, (New-Object Text.UTF8Encoding $false))

    Write-Ok "Theme nach $target kopiert"
}

# ---------- Updater ----------

function Test-NewerVersion([string]$Candidate, [string]$Current) {
    try { [version]$Candidate -gt [version]$Current } catch { $false }
}

# Argumente für Start-Process; Windows PowerShell 5.1 setzt selbst keine Anführungszeichen
function Join-Arguments([string[]]$Arguments) {
    ($Arguments | ForEach-Object { if ($_ -match '[\s"]' -or $_ -eq '') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
}

function Get-LatestRelease {
    $headers = @{ 'User-Agent' = 'RagnaMusicPatch'; Accept = 'application/vnd.github+json' }
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$UpdateRepo/releases/latest" -Headers $headers -UseBasicParsing
    }
    catch {
        Write-Warn "Keine Releases auf GitHub erreichbar ($UpdateRepo): $($_.Exception.Message)"
        return $null
    }
    $zip = $release.assets | Where-Object { $_.name -eq 'RagnaMusicPatch.zip' } | Select-Object -First 1
    $sha = $release.assets | Where-Object { $_.name -eq 'RagnaMusicPatch.zip.sha256' } | Select-Object -First 1
    if (-not $zip -or -not $sha) {
        Write-Warn "Release $($release.tag_name) enthält keine RagnaMusicPatch.zip mit Prüfsumme."
        return $null
    }
    [pscustomobject]@{
        Version = $release.tag_name -replace '^v', ''
        ZipUrl  = $zip.browser_download_url
        ShaUrl  = $sha.browser_download_url
    }
}

# Lädt das Release, prüft die Prüfsumme und startet dessen patch.ps1 -Update. Beendet danach
# dieses Skript, denn den Rest erledigt die neue Version.
function Invoke-SelfUpdate($Release) {
    $work = Join-Path ([IO.Path]::GetTempPath()) "ragna-update-$PID"
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $code = 1
    try {
        $zip = Join-Path $work 'RagnaMusicPatch.zip'
        $shaFile = Join-Path $work 'RagnaMusicPatch.zip.sha256'
        Write-Info "Lade RagnaMusic Patch $($Release.Version) …"
        Invoke-WebRequest -Uri $Release.ZipUrl -OutFile $zip -UseBasicParsing
        Invoke-WebRequest -Uri $Release.ShaUrl -OutFile $shaFile -UseBasicParsing
        $expected = ((Get-Content -LiteralPath $shaFile -Raw).Trim() -split '\s+')[0]
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        if ($actual -ne $expected) { throw "Prüfsumme des Updates stimmt nicht (erwartet $expected, erhalten $actual). Update abgebrochen." }
        Write-Ok 'Prüfsumme stimmt'

        Expand-Archive -Path $zip -DestinationPath $work -Force
        $next = Join-Path $work 'RagnaMusicPatch\patch.ps1'
        if (-not (Test-Path -LiteralPath $next)) { throw 'Das Update-Paket hat einen unerwarteten Aufbau.' }

        $childArgs = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $next, '-Update', '-NoDownload', '-UpdateRepo', $UpdateRepo)
        if ($SchemeGiven) { $childArgs += '-Scheme', $Scheme }
        if ($WaitAtEnd) { $childArgs += '-WaitAtEnd' }
        # gleiches Konsolenfenster, damit Farben und Fortschritt der neuen Version sichtbar bleiben
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList (Join-Arguments $childArgs) -NoNewWindow -Wait -PassThru
        $code = $process.ExitCode
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit $code
}

function Get-InstalledScheme {
    $config = Join-Path $SpicetifyUserData 'config-xpui.ini'
    if (-not (Test-Path -LiteralPath $config)) { return $null }
    $match = Select-String -LiteralPath $config -Pattern '^\s*color_scheme\s*=\s*(\w+)' | Select-Object -First 1
    if ($match -and $match.Matches[0].Groups[1].Value -in 'dark', 'light') { $match.Matches[0].Groups[1].Value } else { $null }
}

function New-Shortcut([string]$Path, [string]$Target, [string]$Description) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($Path)
    $link.TargetPath = $Target
    # nicht im Installationsordner, sonst ließe er sich beim Deinstallieren nicht löschen
    $link.WorkingDirectory = $env:USERPROFILE
    $link.Description = $Description
    $link.IconLocation = (Join-Path $InstallDir 'ragna.ico')
    $link.Save()
}

# Kopiert den Patcher an einen festen Ort und verknüpft ragnapatch:// und das Startmenü damit
function Install-Patcher {
    $source = [IO.Path]::GetFullPath($PatcherRoot).TrimEnd('\')
    $target = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
    if ($source -ne $target) {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        foreach ($item in $PatcherFiles) {
            $path = Join-Path $source $item
            if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $target -Recurse -Force }
        }
    }

    # Die URL selbst wird nicht ausgewertet: ragnapatch:// startet immer nur das Update
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $command = '"{0}" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "{1}" -Update -WaitAtEnd' -f $powershell, (Join-Path $target 'patch.ps1')
    $key = "HKCU:\Software\Classes\$ProtocolName"
    New-Item -Path "$key\shell\open\command" -Force | Out-Null
    Set-Item -Path $key -Value 'URL:RagnaMusic Patch'
    New-ItemProperty -Path $key -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
    New-Item -Path "$key\DefaultIcon" -Force | Out-Null
    Set-Item -Path "$key\DefaultIcon" -Value (Join-Path $target 'ragna.ico')
    Set-Item -Path "$key\shell\open\command" -Value $command

    New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null
    New-Shortcut (Join-Path $StartMenuDir 'RagnaMusic Patch aktualisieren.lnk') (Join-Path $target 'Update Patch.bat') 'Neueste Version von RagnaMusic Patch holen und aufspielen'
    New-Shortcut (Join-Path $StartMenuDir 'RagnaMusic Patch entfernen.lnk') (Join-Path $target 'Uninstall Patch.bat') 'Spotify wieder in den Originalzustand versetzen'

    Write-Ok "Updater eingerichtet ($target)"
}

function Remove-Patcher {
    $key = "HKCU:\Software\Classes\$ProtocolName"
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    if (Test-Path -LiteralPath $StartMenuDir) { Remove-Item -LiteralPath $StartMenuDir -Recurse -Force }
    if (Test-Path -LiteralPath $InstallDir) {
        Set-Location -LiteralPath $env:TEMP
        try {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Warn "Ordner $InstallDir ließ sich nicht ganz löschen: $($_.Exception.Message)"
        }
    }
    Write-Ok 'Updater, Startmenü-Einträge und ragnapatch:// entfernt'
}

function Wait-AtEnd([bool]$Success) {
    if (-not $WaitAtEnd) { return }
    Write-Host ''
    if ($Success) {
        Write-Info 'Dieses Fenster schließt sich in 10 Sekunden.'
        Start-Sleep -Seconds 10
    }
    else {
        Read-Host '  Enter drücken zum Schließen' | Out-Null
    }
}

# ---------- Ablauf ----------

function Invoke-Update {
    Write-Step 'Nach Updates suchen'
    if ($NoDownload) {
        Write-Info "Installiere RagnaMusic Patch $PatchVersion …"
    }
    else {
        $release = Get-LatestRelease
        if ($release -and (Test-NewerVersion $release.Version $PatchVersion)) {
            Write-Ok "Neue Version $($release.Version) gefunden (dieses Paket: $PatchVersion)"
            Invoke-SelfUpdate $release
        }
        if ($release) { Write-Ok "Aktuell: RagnaMusic Patch $PatchVersion" }
        else { Write-Info "Spiele dieses Paket ($PatchVersion) auf." }
    }

    if (-not $SchemeGiven) {
        $installed = Get-InstalledScheme
        if ($installed) { $script:Scheme = $installed }
    }
    # nach einem Spotify-Update fehlt der Patch: dann komplett, sonst reicht das Theme
    $script:ThemeOnly = Test-Spicetified
    if (-not $ThemeOnly) { Write-Info 'Spotify ist nicht (mehr) gepatcht, daher läuft der komplette Patch.' }
    Invoke-Patch
}

function Invoke-Patch {
    if (-not (Test-Path -LiteralPath (Join-Path $ThemeSource 'color.ini'))) {
        throw "Theme-Ordner fehlt: $ThemeSource"
    }

    Write-Step 'Spotify vorbereiten'
    Stop-Spotify
    $script:Spicetify = Get-SpicetifyExe

    if (-not $ThemeOnly) {
        if (Test-Spicetified) {
            if (-not $script:Spicetify) {
                throw 'Spotify ist bereits verändert (Apps\xpui), aber Spicetify wurde nicht gefunden. Spotify bitte neu installieren.'
            }
            Write-Info 'Spicetify ist aktiv und wird vor SpotX zurückgesetzt …'
            # -n: restore würde Spotify sonst sofort neu starten und dessen Dateien sperren
            Invoke-Spicetify -Arguments 'restore', '-n'
            Stop-Spotify
            if (Test-Spicetified) { throw 'Spicetify konnte Spotify nicht zurücksetzen. Spotify bitte neu installieren.' }
            Write-Ok 'Spicetify zurückgesetzt'
        }

        Write-Step 'SpotX'
        Invoke-SpotX
        Stop-Spotify
    }
    elseif (-not (Test-Path -LiteralPath $SpotifyExe)) {
        throw 'Spotify (Desktop-Version) wurde nicht gefunden. Erst den vollständigen Patch ohne -ThemeOnly ausführen.'
    }

    Initialize-SpotifyPrefs

    Write-Step 'Spicetify'
    if (-not $script:Spicetify) { $script:Spicetify = Install-Spicetify }
    else { Write-Ok "Spicetify gefunden: $($script:Spicetify)" }

    # „ und “ zählen in PowerShell als Anführungszeichen, daher hier ohne
    Write-Step "Theme $ThemeName ($Scheme)"
    Install-Theme
    # Pfade fest setzen: nach einem Wechsel von der Store-Version zeigen sie sonst ins Leere
    Invoke-Spicetify -Arguments @(
        'config',
        'spotify_path', $SpotifyDir,
        'prefs_path', $SpotifyPrefs,
        'current_theme', $ThemeName,
        'color_scheme', $Scheme,
        'inject_css', '1',
        'replace_colors', '1',
        'overwrite_assets', '1',
        'inject_theme_js', '1'
    )
    Write-Ok 'Theme aktiviert'

    Write-Step 'Anwenden'
    if (Test-Spicetified) {
        Invoke-Spicetify -Arguments 'apply'
    }
    else {
        Invoke-Spicetify -Arguments 'backup', 'apply'
    }
    Write-Ok 'Spotify ist gepatcht und startet neu'

    Write-Step 'Updater'
    Install-Patcher

    Write-Host ''
    Write-Host '  Fertig. Oben rechts in Spotify steht jetzt „RagnaPatched“.' -ForegroundColor Green
    Write-Info 'Ein Klick darauf öffnet den Theme-Umschalter.'
    if ($AllowUpdates) {
        Write-Warn 'Spotify-Updates sind erlaubt: Nach einem Update diesen Patch erneut ausführen.'
    }
}

function Invoke-Unpatch {
    Write-Step 'Spotify zurücksetzen'
    Stop-Spotify
    $script:Spicetify = Get-SpicetifyExe

    if (-not (Test-Spicetified)) {
        Write-Info 'Spicetify war nicht aktiv.'
    }
    else {
        # -n: restore würde Spotify sonst sofort neu starten und Spotify.exe sperren
        if ($script:Spicetify) { Invoke-Spicetify -Arguments 'restore', '-n' -AllowFailure }
        Stop-Spotify
        if (Test-Spicetified) { Write-Warn 'Spicetify konnte nicht vollständig entfernt werden. Spotify ggf. neu installieren.' }
        else { Write-Ok 'Spicetify entfernt' }
    }

    # wie Uninstall.bat von SpotX: Sicherungskopien zurückspielen
    $backups = [ordered]@{
        'chrome_elf.dll.bak' = 'chrome_elf.dll'
        'Spotify.dll.bak'    = 'Spotify.dll'
        'Spotify.bak'        = 'Spotify.exe'
        'Apps\xpui.bak'      = 'Apps\xpui.spa'
    }
    $restored = 0
    $failed = @()
    foreach ($bak in $backups.Keys) {
        $source = Join-Path $SpotifyDir $bak
        if (-not (Test-Path -LiteralPath $source)) { continue }
        if (Restore-Backup $source (Join-Path $SpotifyDir $backups[$bak])) { $restored++ }
        else { $failed += $backups[$bak] }
    }
    Get-ChildItem -Path ([IO.Path]::GetTempPath()) -Filter 'SpotX_Temp*' -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    if ($restored -gt 0) { Write-Ok "SpotX entfernt ($restored Dateien zurückgespielt)" }
    elseif (-not $failed) { Write-Info 'Keine SpotX-Sicherungen gefunden.' }
    if ($failed) {
        Write-Fail "Nicht zurückgespielt (Datei gesperrt): $($failed -join ', ')"
        Write-Info 'Spotify komplett schließen und „Uninstall Patch.bat“ erneut starten.'
    }
    elseif ($restored -gt 0 -and -not (Test-Path -LiteralPath (Join-Path $SpotifyDir 'Apps\xpui.spa'))) {
        Write-Warn 'Apps\xpui.spa fehlt. Für den Originalzustand Spotify neu installieren.'
    }

    $theme = Join-Path $SpicetifyUserData "Themes\$ThemeName"
    if (Test-Path -LiteralPath $theme) {
        Remove-Item -LiteralPath $theme -Recurse -Force
        Write-Ok 'Theme gelöscht'
    }

    if ($RemoveSpicetify) {
        foreach ($dir in $SpicetifyDir, $SpicetifyUserData) {
            if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        }
        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($userPath) {
            $kept = ($userPath -split ';') | Where-Object { $_ -and $_ -ne $SpicetifyDir }
            [Environment]::SetEnvironmentVariable('PATH', ($kept -join ';'), 'User')
        }
        Write-Ok 'Spicetify-Programm und -Einstellungen gelöscht'
    }

    Remove-Patcher

    Write-Host ''
    if ($failed) {
        Write-Host '  Teilweise entfernt, siehe Hinweis oben.' -ForegroundColor DarkYellow
        Wait-AtEnd $false
        exit 1
    }
    Write-Host '  Fertig. Spotify läuft wieder im Originalzustand.' -ForegroundColor Green
    Write-Info 'Updates sind wieder freigegeben; Spotify aktualisiert sich beim nächsten Start selbst.'
}

# ---------- Start ----------

Write-Banner
try {
    if ($env:OS -ne 'Windows_NT') { throw 'RagnaMusic Patch läuft nur unter Windows.' }
    if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw 'PowerShell 5.1 oder neuer wird benötigt.' }

    # Ein Update startet man bewusst (Knopf in Spotify, Startmenü, .bat): keine Rückfragen
    if ($Update) { $script:Yes = $true }

    $script:BypassAdmin = $false
    if (Test-Elevated) {
        Write-Warn 'Der Patch läuft mit Administratorrechten.'
        Write-Info 'Spicetify rät davon ab: Läuft Spotify danach ohne Adminrechte, kann das Fenster schwarz bleiben.'
        Write-Info 'Unproblematisch, wenn du immer als Administrator arbeitest (wie beim Konto „Administrator“).'
        if (-not (Confirm-Step 'Trotzdem fortfahren?')) { throw 'Abgebrochen.' }
        $script:BypassAdmin = $true
    }

    if ($Uninstall) { Invoke-Unpatch }
    elseif ($Update) { Invoke-Update }
    else { Invoke-Patch }
    Wait-AtEnd $true
    exit 0
}
catch {
    Write-Host ''
    Write-Fail $_.Exception.Message
    Wait-AtEnd $false
    exit 1
}
