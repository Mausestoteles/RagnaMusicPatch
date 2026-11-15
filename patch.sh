#!/usr/bin/env bash
# RagnaMusic Patch für Linux: SpotX-Bash + Spicetify + RagnaMusic-Theme für den Spotify-Client.
#
# Gegenstück zu patch.ps1 (Windows). Ablauf:
#   1. Spotify finden (.deb unter /usr/share/spotify oder /opt/spotify, Flatpak). Snap ist
#      schreibgeschützt und lässt sich weder von SpotX noch von Spicetify patchen: nach
#      Rückfrage wird es durch die .deb-Version ersetzt (über SpotX-Bash --installdeb).
#   2. Spotify beenden. Ist Spicetify schon aktiv, zuerst „spicetify restore“.
#   3. SpotX-Bash in der aktuellen Version von GitHub laden und ausführen.
#   4. Spotify-Ordner für Spicetify beschreibbar machen (wie in der Spicetify-Anleitung).
#   5. Spotify einmal starten, damit die Datei „prefs“ entsteht.
#   6. Spicetify installieren (Release von GitHub nach ~/.spicetify), falls es fehlt.
#   7. Theme „RagnaMusic“ kopieren, aktivieren und anwenden.
#   8. Updater: Kopie nach ~/.local/share/RagnaMusicPatch, Link-Protokoll ragnapatch://
#      und zwei Einträge im Anwendungsmenü.
#
# Aufruf:  bash patch.sh [Optionen]      (bash patch.sh --help zeigt alle)

set -uo pipefail

PATCH_VERSION='0.3.0'
THEME_NAME='RagnaMusic'
PATCHER_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
THEME_SOURCE="$PATCHER_ROOT/theme/$THEME_NAME"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="$DATA_HOME/RagnaMusicPatch"
APPS_DIR="$DATA_HOME/applications"
SPICETIFY_HOME="$HOME/.spicetify"
PROTOCOL_NAME='ragnapatch'
DESKTOP_UPDATE='ragnamusic-patch-update.desktop'
DESKTOP_REMOVE='ragnamusic-patch-remove.desktop'
FLATPAK_ID='com.spotify.Client'
# was zum Patcher gehört; dieselbe Liste nutzt tools/build-zip.ps1 für das Release
PATCHER_FILES=(patch.ps1 patch.sh README.md ragna.ico 'Start Patch.bat' 'Update Patch.bat' 'Uninstall Patch.bat' theme)

# ---------- Optionen ----------

SCHEME='dark'
SCHEME_GIVEN=''
PREMIUM=''
KEEP_PODCASTS=''
ALLOW_UPDATES=''
THEME_ONLY=''
UPDATE=''
NO_DOWNLOAD=''
UPDATE_REPO='Mausestoteles/RagnaMusicPatch'
WAIT_AT_END=''
UNINSTALL=''
REMOVE_SPICETIFY=''
SPOTX_REF='main'
SPICETIFY_VERSION=''
SPOTIFY_PATH_GIVEN=''
YES=''

show_help() {
  cat <<'EOF'
RagnaMusic Patch für Linux

  bash patch.sh [Optionen]

  --scheme dark|light       Farbschema beim Patchen (Standard: dark)
  --theme-only              nur das Theme neu aufspielen, SpotX nicht erneut ausführen
  --update                  neueste Version holen (Prüfsumme wird geprüft) und aufspielen
  --premium                 SpotX ohne Werbeblocker (für Premium-Konten)
  --keep-podcasts           Podcasts und Hörbücher auf der Startseite lassen
  --allow-updates           Spotify-Updates nicht sperren (danach Patch erneut ausführen)
  --spotify-path <ordner>   Spotify-Ordner selbst angeben (enthält Apps/xpui.spa)
  --spotx-ref <commit>      bestimmte SpotX-Bash-Version statt main
  --spicetify-version <v>   bestimmte Spicetify-Version bei der Installation, z. B. 2.45.3
  --update-repo <owner/repo> GitHub-Repo mit den Releases
  --yes                     keine Rückfragen
  --uninstall [--remove-spicetify]
                            Patch entfernen, optional auch Spicetify selbst
EOF
}

while (($#)); do
  case "$1" in
    --scheme|-Scheme) SCHEME="${2:-}"; SCHEME_GIVEN=1; shift ;;
    --premium|-Premium) PREMIUM=1 ;;
    --keep-podcasts|-KeepPodcasts) KEEP_PODCASTS=1 ;;
    --allow-updates|-AllowUpdates) ALLOW_UPDATES=1 ;;
    --theme-only|-ThemeOnly) THEME_ONLY=1 ;;
    --update|-Update) UPDATE=1 ;;
    --no-download|-NoDownload) NO_DOWNLOAD=1 ;;
    --update-repo|-UpdateRepo) UPDATE_REPO="${2:-}"; shift ;;
    --wait-at-end|-WaitAtEnd) WAIT_AT_END=1 ;;
    --uninstall|-Uninstall) UNINSTALL=1 ;;
    --remove-spicetify|-RemoveSpicetify) REMOVE_SPICETIFY=1 ;;
    --spotx-ref|-SpotXRef) SPOTX_REF="${2:-}"; shift ;;
    --spicetify-version|-SpicetifyVersion) SPICETIFY_VERSION="${2:-}"; shift ;;
    --spotify-path) SPOTIFY_PATH_GIVEN="${2:-}"; shift ;;
    --yes|-y|-Yes) YES=1 ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "Unbekannte Option: $1 (bash patch.sh --help)" >&2; exit 2 ;;
  esac
  shift
done

# ---------- Ausgabe ----------

if [[ -t 1 ]]; then
  C_Y=$'\e[33m'; C_YB=$'\e[1;33m'; C_G=$'\e[32m'; C_R=$'\e[31m'; C_D=$'\e[90m'; C_W=$'\e[1;37m'; C_0=$'\e[0m'
else
  C_Y=''; C_YB=''; C_G=''; C_R=''; C_D=''; C_W=''; C_0=''
fi

banner() {
  echo
  echo "${C_Y}  ┌───┐${C_0}"
  echo "${C_Y}  │ R │  ${C_YB}Ragna${C_W}Music Patch $PATCH_VERSION${C_0}"
  echo "${C_Y}  └───┘  SpotX-Bash + Spicetify + RagnaMusic-Theme (Linux)${C_0}"
  echo
}
step() { echo; echo "${C_YB}» $*${C_0}"; }
ok()   { echo "${C_G}  √ $*${C_0}"; }
info() { echo "${C_D}  $*${C_0}"; }
warn() { echo "${C_Y}  ! $*${C_0}"; }
fail() { echo "${C_R}  × $*${C_0}" >&2; }

# Bricht mit Meldung ab (wie throw in patch.ps1)
die() {
  echo
  fail "$*"
  wait_at_end 1
  exit 1
}

wait_at_end() {
  [[ -n "$WAIT_AT_END" ]] || return 0
  echo
  if [[ "${1:-0}" == 0 ]]; then
    info 'Dieses Fenster schließt sich in 10 Sekunden.'
    sleep 10
  else
    read -r -p '  Enter drücken zum Schließen ' _ || true
  fi
}

confirm() {
  [[ -n "$YES" ]] && return 0
  local answer
  while true; do
    # keine Eingabe möglich (z. B. umgeleitete Konsole): als Nein werten
    read -r -p "  $1 [j/n] " answer || return 1
    case "${answer,,}" in
      j|ja|y|yes) return 0 ;;
      n|nein|no) return 1 ;;
    esac
  done
}

# Ausgabe von Spicetify im Stil des Patchers: Farbcodes und Spinner raus, Füllzeilen weg
tool_line() {
  local text="$1"
  text="$(printf '%s' "$text" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr '\r' '\n' | grep -v '^[[:space:]]*$' | tail -n 1)"
  text="${text#"${text%%[![:space:]]*}"}"
  [[ -z "$text" ]] && return
  [[ "$text" =~ ^spicetify\ v[0-9] || "$text" == *'to apply new config'* ]] && return
  local rest="${text#* }"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  case "$text" in
    success\ *|ok\ *) ok "$rest" ;;
    warning\ *|warn\ *) warn "$rest" ;;
    error\ *|fatal\ *) fail "$rest" ;;
    info\ *|note\ *) info "$rest" ;;
    *) info "$text" ;;
  esac
}

need() {
  local missing=() cmd
  for cmd in "$@"; do command -v "$cmd" >/dev/null || missing+=("$cmd"); done
  ((${#missing[@]} == 0)) && return 0
  die "Es fehlen Programme: ${missing[*]}. Unter Ubuntu/Debian: sudo apt install ${missing[*]}"
}

# ---------- Spotify ----------

SPOTIFY_DIR=''
SPOTIFY_KIND=''   # deb | flatpak | other | snap | ''
SPOTIFY_PREFS=''
FLATPAK_SCOPE=''  # --user | --system

detect_spotify() {
  SPOTIFY_DIR=''; SPOTIFY_KIND=''; SPOTIFY_PREFS="$HOME/.config/spotify/prefs"
  local dir
  if [[ -n "$SPOTIFY_PATH_GIVEN" ]]; then
    [[ -f "$SPOTIFY_PATH_GIVEN/Apps/xpui.spa" || -d "$SPOTIFY_PATH_GIVEN/Apps/xpui" ]] ||
      die "Im angegebenen Ordner liegt kein Spotify (Apps/xpui.spa fehlt): $SPOTIFY_PATH_GIVEN"
    SPOTIFY_DIR="$SPOTIFY_PATH_GIVEN"; SPOTIFY_KIND='other'
    [[ "$SPOTIFY_DIR" == *flatpak* ]] && { SPOTIFY_KIND='flatpak'; SPOTIFY_PREFS="$HOME/.var/app/$FLATPAK_ID/config/spotify/prefs"; }
    return
  fi
  for dir in /usr/share/spotify /opt/spotify /usr/lib/spotify "$HOME/.local/share/spotify-launcher/install/usr/share/spotify"; do
    if [[ -x "$dir/spotify" && ( -f "$dir/Apps/xpui.spa" || -d "$dir/Apps/xpui" ) ]]; then
      SPOTIFY_DIR="$dir"
      if command -v dpkg-query >/dev/null && dpkg-query -W -f='${Status}' spotify-client 2>/dev/null | grep -q 'install ok installed'; then
        SPOTIFY_KIND='deb'
      else
        SPOTIFY_KIND='other'
      fi
      return
    fi
  done
  if command -v flatpak >/dev/null; then
    local scope location
    for scope in --user --system; do
      location="$(flatpak info "$scope" --show-location "$FLATPAK_ID" 2>/dev/null)" || continue
      dir="$location/files/extra/share/spotify"
      if [[ -f "$dir/Apps/xpui.spa" || -d "$dir/Apps/xpui" ]]; then
        SPOTIFY_DIR="$dir"; SPOTIFY_KIND='flatpak'; FLATPAK_SCOPE="$scope"
        SPOTIFY_PREFS="$HOME/.var/app/$FLATPAK_ID/config/spotify/prefs"
        return
      fi
    done
  fi
  if command -v snap >/dev/null && snap list spotify >/dev/null 2>&1; then
    SPOTIFY_KIND='snap'
  fi
}

spotify_running() { pgrep -x spotify >/dev/null 2>&1 || pgrep -f '/spotify/spotify' >/dev/null 2>&1; }

stop_spotify() {
  spotify_running || return 0
  pkill -x spotify 2>/dev/null
  local i
  for ((i = 0; i < 20; i++)); do spotify_running || break; sleep 0.25; done
  spotify_running && { pkill -9 -x spotify 2>/dev/null; sleep 0.5; }
  ok 'Spotify beendet'
}

start_spotify() {
  if [[ "$SPOTIFY_KIND" == 'flatpak' ]]; then
    nohup flatpak run "$FLATPAK_ID" >/dev/null 2>&1 &
  else
    nohup "$SPOTIFY_DIR/spotify" >/dev/null 2>&1 &
  fi
  disown 2>/dev/null || true
}

spotify_version() {
  if [[ "$SPOTIFY_KIND" == 'flatpak' ]]; then
    flatpak info "$FLATPAK_ID" 2>/dev/null | sed -nE 's/^ *Version: *//p' | head -n 1
  elif [[ -x "$SPOTIFY_DIR/spotify" ]]; then
    "$SPOTIFY_DIR/spotify" --version 2>/dev/null | sed -nE 's/.*version ([0-9][^, ]*).*/\1/p' | head -n 1
  fi
}

# Spicetify entpackt xpui.spa in einen Ordner; daran erkennt auch SpotX den Zustand
is_spicetified() { [[ -n "$SPOTIFY_DIR" && -f "$SPOTIFY_DIR/Apps/xpui/xpui.js" ]]; }

# Snap ist schreibgeschützt: .deb-Version installieren (SpotX-Bash patcht sie dabei gleich)
replace_snap() {
  warn 'Spotify ist als Snap installiert. Snap-Pakete sind schreibgeschützt, Spicetify kann sie nicht verändern.'
  info 'Die Snap-Version wird durch die offizielle .deb-Version ersetzt. Danach einmal neu bei Spotify anmelden.'
  command -v apt-get >/dev/null ||
    die 'Ohne APT (Debian, Ubuntu, Mint …) bitte Spotify als Flatpak installieren: flatpak install flathub com.spotify.Client'
  confirm 'Snap-Version entfernen und .deb-Version installieren?' || die 'Abgebrochen: Mit der Snap-Version von Spotify funktioniert der Patch nicht.'
  stop_spotify
  install_deb
  info 'Entferne die Snap-Version …'
  sudo snap remove spotify >/dev/null || warn 'Snap-Version ließ sich nicht entfernen (sudo snap remove spotify).'
  hash -r
  detect_spotify
  [[ "$SPOTIFY_KIND" == 'deb' ]] || die 'Die .deb-Version von Spotify wurde nicht gefunden. Ausgabe oben prüfen.'
  ok "Spotify (.deb) installiert: $SPOTIFY_DIR"
}

# Spicetify braucht Schreibrechte im Spotify-Ordner (Anleitung von Spicetify)
make_writable() {
  [[ -w "$SPOTIFY_DIR" && -w "$SPOTIFY_DIR/Apps" ]] && [[ ! -e "$SPOTIFY_DIR/Apps/xpui.spa" || -w "$SPOTIFY_DIR/Apps/xpui.spa" ]] && return 0
  info "Spicetify braucht Schreibrechte in $SPOTIFY_DIR (sudo) …"
  sudo chmod a+wr "$SPOTIFY_DIR" && sudo chmod -R a+wr "$SPOTIFY_DIR/Apps" ||
    die "Konnte $SPOTIFY_DIR nicht beschreibbar machen."
  ok 'Spotify-Ordner für Spicetify freigegeben'
}

# Spicetify braucht die Datei „prefs“, die Spotify erst beim ersten Start anlegt
init_prefs() {
  [[ -f "$SPOTIFY_PREFS" ]] && return 0
  info 'Spotify startet einmal kurz, damit seine Einstellungen entstehen …'
  start_spotify
  local i
  for ((i = 0; i < 120; i++)); do [[ -f "$SPOTIFY_PREFS" ]] && break; sleep 0.5; done
  sleep 3
  stop_spotify
  [[ -f "$SPOTIFY_PREFS" ]] ||
    die 'Spotify hat keine Datei „prefs“ angelegt. Bitte Spotify einmal starten, anmelden und den Patch danach erneut ausführen.'
  ok 'Spotify-Einstellungen angelegt'
}

# Spotify-Updates sperren: bei .deb per apt-mark hold, bei Flatpak per flatpak mask
block_updates() {
  case "$SPOTIFY_KIND" in
    deb)
      if [[ -n "$ALLOW_UPDATES" ]]; then
        sudo apt-mark unhold spotify-client >/dev/null 2>&1 || true
      elif sudo apt-mark hold spotify-client >/dev/null; then
        ok 'Spotify-Updates gesperrt (apt-mark hold spotify-client)'
      else
        warn 'Spotify-Updates konnten nicht gesperrt werden.'
      fi ;;
    flatpak)
      if [[ -n "$ALLOW_UPDATES" ]]; then
        flatpak mask "$FLATPAK_SCOPE" --remove "$FLATPAK_ID" >/dev/null 2>&1 || true
      elif flatpak mask "$FLATPAK_SCOPE" "$FLATPAK_ID" >/dev/null 2>&1; then
        ok 'Spotify-Updates gesperrt (flatpak mask)'
      else
        warn 'Spotify-Updates konnten nicht gesperrt werden (flatpak mask braucht Flatpak 1.12).'
      fi ;;
  esac
}

unblock_updates() {
  case "$SPOTIFY_KIND" in
    deb) sudo apt-mark unhold spotify-client >/dev/null 2>&1 && ok 'Spotify-Updates wieder freigegeben' ;;
    flatpak) flatpak mask "$FLATPAK_SCOPE" --remove "$FLATPAK_ID" >/dev/null 2>&1 && ok 'Spotify-Updates wieder freigegeben' ;;
  esac
  return 0
}

# ---------- SpotX-Bash ----------

run_spotx() {
  local url="https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/$SPOTX_REF/spotx.sh"
  local script
  script="$(mktemp "${TMPDIR:-/tmp}/ragna-spotx-XXXXXX.sh")"
  info "Lade SpotX-Bash ($SPOTX_REF) …"
  curl -fsSL "$url" -o "$script" || { rm -f "$script"; die "SpotX-Bash ließ sich nicht laden ($url)."; }
  info "Starte SpotX-Bash mit: $*"
  echo
  bash "$script" "$@"
  local code=$?
  rm -f "$script"
  ((code == 0)) || die "SpotX-Bash ist mit Code $code beendet worden."
}

SPOTX_DONE=''

# kein -c: das löscht Spotifys Local Storage und damit die Wahl im Theme-Umschalter
spotx_args() {
  SPOTX_ARGS=(--noninteractive)
  [[ -z "$KEEP_PODCASTS" ]] && SPOTX_ARGS+=(-h)
  [[ -n "$PREMIUM" ]] && SPOTX_ARGS+=(-p)
  return 0
}

# Spotify als .deb installieren; SpotX-Bash patcht es dabei gleich mit
install_deb() {
  spotx_args
  run_spotx "${SPOTX_ARGS[@]}" --installdeb --stable
  SPOTX_DONE=1
}

invoke_spotx() {
  spotx_args
  run_spotx "${SPOTX_ARGS[@]}" -P "$SPOTIFY_DIR"
  [[ -f "$SPOTIFY_DIR/Apps/xpui.spa" ]] ||
    die 'SpotX-Bash ist durchgelaufen, aber Spotify ist nicht vollständig (Apps/xpui.spa fehlt). Ausgabe oben prüfen.'
  ok 'SpotX angewendet'
}

# ---------- Spicetify ----------

SPICETIFY=''

find_spicetify() {
  if [[ -x "$SPICETIFY_HOME/spicetify" ]]; then SPICETIFY="$SPICETIFY_HOME/spicetify"
  elif command -v spicetify >/dev/null; then SPICETIFY="$(command -v spicetify)"
  else SPICETIFY=''
  fi
}

install_spicetify() {
  local arch version tarball
  case "$(uname -m)" in
    x86_64|amd64) arch='amd64' ;;
    aarch64|arm64) arch='arm64' ;;
    *) die "Spicetify gibt es nicht für $(uname -m)." ;;
  esac
  version="$SPICETIFY_VERSION"
  if [[ -z "$version" ]]; then
    version="$(latest_tag spicetify/cli)" || die 'Neueste Spicetify-Version nicht ermittelbar.'
  fi
  version="${version#v}"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Ungültige Spicetify-Version: $version"
  tarball="$(mktemp "${TMPDIR:-/tmp}/ragna-spicetify-XXXXXX.tar.gz")"
  info "Lade Spicetify $version ($arch) …"
  curl -fsSL "https://github.com/spicetify/cli/releases/download/v$version/spicetify-$version-linux-$arch.tar.gz" -o "$tarball" ||
    { rm -f "$tarball"; die 'Spicetify ließ sich nicht laden.'; }
  mkdir -p "$SPICETIFY_HOME"
  tar -xzf "$tarball" -C "$SPICETIFY_HOME" || { rm -f "$tarball"; die 'Spicetify ließ sich nicht entpacken.'; }
  rm -f "$tarball"
  chmod +x "$SPICETIFY_HOME/spicetify"
  # wie das offizielle Installationsskript ein Ort im PATH; ~/.local/bin hat Ubuntu dort
  mkdir -p "$HOME/.local/bin"
  ln -sf "$SPICETIFY_HOME/spicetify" "$HOME/.local/bin/spicetify"
  SPICETIFY="$SPICETIFY_HOME/spicetify"
  ok "Spicetify $version installiert"
}

spicetify_run() {
  local allow_failure=''
  [[ "$1" == '--allow-failure' ]] && { allow_failure=1; shift; }
  local args=("$@")
  # Spicetify verweigert sonst den Start als root
  ((EUID == 0)) && args+=(--bypass-admin)
  local line code
  "$SPICETIFY" "${args[@]}" 2>&1 | while IFS= read -r line; do tool_line "$line"; done
  code="${PIPESTATUS[0]}"
  if [[ "$code" != 0 ]]; then
    if [[ -n "$allow_failure" ]]; then warn "spicetify $* ist mit Code $code fehlgeschlagen."
    else die "spicetify $* ist mit Code $code fehlgeschlagen."
    fi
  fi
}

spicetify_config_dir() {
  local file
  file="$("$SPICETIFY" -c 2>/dev/null | tail -n 1)"
  if [[ -n "$file" && "$file" == /* ]]; then dirname -- "$file"
  else echo "${XDG_CONFIG_HOME:-$HOME/.config}/spicetify"
  fi
}

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

install_theme() {
  local themes target info
  themes="$(spicetify_config_dir)/Themes"
  target="$themes/$THEME_NAME"
  mkdir -p "$themes"
  rm -rf -- "$target"
  cp -r -- "$THEME_SOURCE" "$target"

  # Patch-Daten für das Badge „RagnaPatched“
  info="{\"patchVersion\":$(json_str "$PATCH_VERSION"),\"patchedAt\":$(json_str "$(date '+%d.%m.%Y %H:%M')")"
  info+=",\"scheme\":$(json_str "$SCHEME"),\"spotxRef\":$(json_str "$SPOTX_REF")"
  info+=",\"spicetifyVersion\":$(json_str "$("$SPICETIFY" -v 2>/dev/null | tail -n 1)")"
  info+=",\"spotifyVersion\":$(json_str "$(spotify_version)"),\"updateRepo\":$(json_str "$UPDATE_REPO")"
  info+=",\"platform\":\"linux\"}"
  RAGNA_INFO="$info" perl -0pi -e 's{/\*RAGNA_PATCH_INFO\*/ null}{$ENV{RAGNA_INFO}}' "$target/theme.js" ||
    die 'Patch-Daten ließen sich nicht in theme.js schreiben.'
  ok "Theme nach $target kopiert"
}

installed_scheme() {
  [[ -n "$SPICETIFY" ]] || return 0
  local config
  config="$(spicetify_config_dir)/config-xpui.ini"
  [[ -f "$config" ]] || return 0
  sed -nE 's/^[[:space:]]*color_scheme[[:space:]]*=[[:space:]]*(dark|light)[[:space:]]*$/\1/p' "$config" | head -n 1
}

# ---------- Updater ----------

# Neuester Release-Tag über die Weiterleitung von /releases/latest (ohne API-Limit und JSON)
latest_tag() {
  local location
  location="$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest")" || return 1
  [[ "$location" == */tag/* ]] || return 1
  printf '%s\n' "${location##*/tag/}"
}

is_newer() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" ]]
}

# Lädt das Release, prüft die Prüfsumme und startet dessen patch.sh --update. Beendet danach
# dieses Skript, denn den Rest erledigt die neue Version.
self_update() {
  local tag="$1" work zip expected actual next code
  work="$(mktemp -d "${TMPDIR:-/tmp}/ragna-update-XXXXXX")"
  zip="$work/RagnaMusicPatch.zip"
  info "Lade RagnaMusic Patch ${tag#v} …"
  if ! curl -fsSL "https://github.com/$UPDATE_REPO/releases/download/$tag/RagnaMusicPatch.zip" -o "$zip" ||
     ! curl -fsSL "https://github.com/$UPDATE_REPO/releases/download/$tag/RagnaMusicPatch.zip.sha256" -o "$zip.sha256"; then
    rm -rf -- "$work"; die 'Update ließ sich nicht laden.'
  fi
  expected="$(awk '{print tolower($1); exit}' "$zip.sha256")"
  actual="$(sha256sum "$zip" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] ||
    { rm -rf -- "$work"; die "Prüfsumme des Updates stimmt nicht (erwartet $expected, erhalten $actual). Update abgebrochen."; }
  ok 'Prüfsumme stimmt'
  unzip -q "$zip" -d "$work" || { rm -rf -- "$work"; die 'Update ließ sich nicht entpacken.'; }
  next="$work/RagnaMusicPatch/patch.sh"
  if [[ ! -f "$next" ]]; then
    rm -rf -- "$work"
    warn "Version ${tag#v} enthält keine Linux-Fassung. Spiele dieses Paket ($PATCH_VERSION) auf."
    return 0
  fi
  local args=(--update --no-download --update-repo "$UPDATE_REPO")
  [[ -n "$SCHEME_GIVEN" ]] && args+=(--scheme "$SCHEME")
  [[ -n "$WAIT_AT_END" ]] && args+=(--wait-at-end)
  bash "$next" "${args[@]}"
  code=$?
  rm -rf -- "$work"
  exit "$code"
}

desktop_quote() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/[\\"`$]/\\&/g')"; }

# Kopiert den Patcher an einen festen Ort und verknüpft ragnapatch:// und das Anwendungsmenü
install_patcher() {
  local source target item icon
  source="$(cd -- "$PATCHER_ROOT" && pwd -P)"
  mkdir -p "$INSTALL_DIR"
  target="$(cd -- "$INSTALL_DIR" && pwd -P)"
  if [[ "$source" != "$target" ]]; then
    rm -rf -- "$target"
    mkdir -p "$target"
    for item in "${PATCHER_FILES[@]}"; do
      [[ -e "$source/$item" ]] && cp -r -- "$source/$item" "$target/"
    done
  fi
  chmod +x "$target/patch.sh" 2>/dev/null || true
  icon="$target/theme/$THEME_NAME/assets/ragna/logo.png"

  mkdir -p "$APPS_DIR"
  # Die URL selbst wird nicht ausgewertet: ragnapatch:// startet immer nur das Update
  cat > "$APPS_DIR/$DESKTOP_UPDATE" <<EOF
[Desktop Entry]
Type=Application
Name=RagnaMusic Patch aktualisieren
Comment=Neueste Version von RagnaMusic Patch holen und aufspielen
Exec=bash $(desktop_quote "$target/patch.sh") --update --wait-at-end
Icon=$icon
Terminal=true
Categories=AudioVideo;Audio;
MimeType=x-scheme-handler/$PROTOCOL_NAME;
EOF
  cat > "$APPS_DIR/$DESKTOP_REMOVE" <<EOF
[Desktop Entry]
Type=Application
Name=RagnaMusic Patch entfernen
Comment=Spotify wieder in den Originalzustand versetzen
Exec=bash $(desktop_quote "$target/patch.sh") --uninstall --wait-at-end
Icon=$icon
Terminal=true
Categories=AudioVideo;Audio;
EOF
  command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" >/dev/null 2>&1
  if command -v xdg-mime >/dev/null; then
    xdg-mime default "$DESKTOP_UPDATE" "x-scheme-handler/$PROTOCOL_NAME" 2>/dev/null
  else
    warn 'xdg-mime fehlt: der Knopf „Updaten“ in Spotify funktioniert nicht, das Menü schon.'
  fi
  ok "Updater eingerichtet ($target)"
}

remove_patcher() {
  rm -f -- "$APPS_DIR/$DESKTOP_UPDATE" "$APPS_DIR/$DESKTOP_REMOVE"
  local mimeapps="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
  [[ -f "$mimeapps" ]] && sed -i "/^x-scheme-handler\/$PROTOCOL_NAME=/d" "$mimeapps"
  command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" >/dev/null 2>&1
  [[ -d "$INSTALL_DIR" ]] && { cd / && rm -rf -- "$INSTALL_DIR"; }
  ok 'Updater, Menü-Einträge und ragnapatch:// entfernt'
}

# ---------- Ablauf ----------

invoke_update() {
  step 'Nach Updates suchen'
  if [[ -n "$NO_DOWNLOAD" ]]; then
    info "Installiere RagnaMusic Patch $PATCH_VERSION …"
  else
    local tag
    if tag="$(latest_tag "$UPDATE_REPO")"; then
      if is_newer "${tag#v}" "$PATCH_VERSION"; then
        ok "Neue Version ${tag#v} gefunden (dieses Paket: $PATCH_VERSION)"
        self_update "$tag"
      else
        ok "Aktuell: RagnaMusic Patch $PATCH_VERSION"
      fi
    else
      warn "Keine Releases auf GitHub erreichbar ($UPDATE_REPO)."
      info "Spiele dieses Paket ($PATCH_VERSION) auf."
    fi
  fi

  find_spicetify
  if [[ -z "$SCHEME_GIVEN" ]]; then
    local installed
    installed="$(installed_scheme)"
    [[ -n "$installed" ]] && SCHEME="$installed"
  fi
  detect_spotify
  # nach einem Spotify-Update fehlt der Patch: dann komplett, sonst reicht das Theme
  if is_spicetified; then THEME_ONLY=1
  else THEME_ONLY=''; info 'Spotify ist nicht (mehr) gepatcht, daher läuft der komplette Patch.'
  fi
  invoke_patch
}

invoke_patch() {
  [[ -f "$THEME_SOURCE/color.ini" ]] || die "Theme-Ordner fehlt: $THEME_SOURCE"

  step 'Spotify vorbereiten'
  [[ -n "$SPOTIFY_KIND" ]] || detect_spotify
  find_spicetify

  if [[ "$SPOTIFY_KIND" == 'snap' ]]; then
    [[ -n "$THEME_ONLY" ]] && die 'Spotify ist als Snap installiert. Erst den vollständigen Patch ohne --theme-only ausführen.'
    replace_snap
  elif [[ -z "$SPOTIFY_KIND" ]]; then
    [[ -n "$THEME_ONLY" ]] && die 'Spotify wurde nicht gefunden. Erst den vollständigen Patch ohne --theme-only ausführen.'
    command -v apt-get >/dev/null ||
      die 'Spotify wurde nicht gefunden. Bitte Spotify installieren (Flatpak: flatpak install flathub com.spotify.Client) und den Patch erneut starten.'
    warn 'Spotify ist nicht installiert.'
    confirm 'Spotify (.deb) installieren?' || die 'Abgebrochen.'
    install_deb
    detect_spotify
    [[ "$SPOTIFY_KIND" == 'deb' ]] || die 'Spotify wurde nach der Installation nicht gefunden. Ausgabe oben prüfen.'
  fi
  ok "Spotify gefunden: $SPOTIFY_DIR ($SPOTIFY_KIND)"
  stop_spotify

  if [[ -z "$THEME_ONLY" ]]; then
    if is_spicetified; then
      [[ -n "$SPICETIFY" ]] ||
        die 'Spotify ist bereits verändert (Apps/xpui), aber Spicetify wurde nicht gefunden. Spotify bitte neu installieren.'
      info 'Spicetify ist aktiv und wird vor SpotX zurückgesetzt …'
      # -n: restore würde Spotify sonst sofort neu starten
      spicetify_run restore -n
      stop_spotify
      is_spicetified && die 'Spicetify konnte Spotify nicht zurücksetzen. Spotify bitte neu installieren.'
      ok 'Spicetify zurückgesetzt'
    fi

    if [[ -z "$SPOTX_DONE" ]]; then
      step 'SpotX'
      invoke_spotx
    fi
    stop_spotify
    block_updates
  fi

  make_writable
  init_prefs

  step 'Spicetify'
  if [[ -z "$SPICETIFY" ]]; then install_spicetify
  else ok "Spicetify gefunden: $SPICETIFY"
  fi

  step "Theme $THEME_NAME ($SCHEME)"
  install_theme
  # Pfade fest setzen: nach einem Wechsel von Snap/Flatpak zeigen sie sonst ins Leere
  spicetify_run config \
    spotify_path "$SPOTIFY_DIR" \
    prefs_path "$SPOTIFY_PREFS" \
    current_theme "$THEME_NAME" \
    color_scheme "$SCHEME" \
    inject_css 1 \
    replace_colors 1 \
    overwrite_assets 1 \
    inject_theme_js 1
  ok 'Theme aktiviert'

  step 'Anwenden'
  # „backup apply“ legt beim ersten Mal die Sicherung an, danach reicht „apply“
  if is_spicetified; then spicetify_run apply
  else spicetify_run backup apply
  fi
  ok 'Spotify ist gepatcht und startet neu'

  step 'Updater'
  install_patcher

  echo
  echo "${C_G}  Fertig. Oben rechts in Spotify steht jetzt „RagnaPatched“.${C_0}"
  info 'Ein Klick darauf öffnet den Theme-Umschalter.'
  [[ -n "$ALLOW_UPDATES" ]] && warn 'Spotify-Updates sind erlaubt: Nach einem Update diesen Patch erneut ausführen.'
  return 0
}

invoke_unpatch() {
  step 'Spotify zurücksetzen'
  detect_spotify
  find_spicetify
  [[ -n "$SPOTIFY_DIR" ]] || warn 'Spotify wurde nicht gefunden, entferne nur Theme und Updater.'
  stop_spotify

  if ! is_spicetified; then
    info 'Spicetify war nicht aktiv.'
  else
    [[ -n "$SPICETIFY" ]] && spicetify_run --allow-failure restore -n
    stop_spotify
    if is_spicetified; then warn 'Spicetify konnte nicht vollständig entfernt werden. Spotify ggf. neu installieren.'
    else ok 'Spicetify entfernt'
    fi
  fi

  # SpotX-Bash spielt seine Sicherungen (spotify.bak, Apps/xpui.bak) selbst zurück
  if [[ -n "$SPOTIFY_DIR" && ( -f "$SPOTIFY_DIR/Apps/xpui.bak" || -f "$SPOTIFY_DIR/spotify.bak" ) ]]; then
    local url="https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/$SPOTX_REF/spotx.sh" script
    script="$(mktemp "${TMPDIR:-/tmp}/ragna-spotx-XXXXXX.sh")"
    if curl -fsSL "$url" -o "$script" && bash "$script" --uninstall -P "$SPOTIFY_DIR"; then
      ok 'SpotX entfernt'
    else
      fail 'SpotX ließ sich nicht entfernen. Spotify ggf. neu installieren.'
    fi
    rm -f "$script"
  else
    info 'Keine SpotX-Sicherungen gefunden.'
  fi
  unblock_updates

  if [[ -n "$SPICETIFY" ]]; then
    local theme
    theme="$(spicetify_config_dir)/Themes/$THEME_NAME"
    [[ -d "$theme" ]] && { rm -rf -- "$theme"; ok 'Theme gelöscht'; }
  fi

  if [[ -n "$REMOVE_SPICETIFY" ]]; then
    local config_dir=''
    [[ -n "$SPICETIFY" ]] && config_dir="$(spicetify_config_dir)"
    rm -rf -- "$SPICETIFY_HOME"
    [[ -n "$config_dir" && "$config_dir" == */spicetify ]] && rm -rf -- "$config_dir"
    [[ -L "$HOME/.local/bin/spicetify" ]] && rm -f -- "$HOME/.local/bin/spicetify"
    ok 'Spicetify-Programm und -Einstellungen gelöscht'
  fi

  remove_patcher

  echo
  echo "${C_G}  Fertig. Spotify läuft wieder im Originalzustand.${C_0}"
}

# ---------- Start ----------

# beim Einbinden per „source“ (Tests) nur die Funktionen laden
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

banner
[[ "$(uname -s)" == 'Linux' ]] || die 'patch.sh ist für Linux. Unter Windows bitte „Start Patch.bat“ nutzen.'
[[ "$SCHEME" == 'dark' || "$SCHEME" == 'light' ]] || die "Farbschema muss dark oder light sein, nicht „$SCHEME“."
need curl unzip zip perl tar sha256sum sed awk pgrep

# Ein Update startet man bewusst (Knopf in Spotify, Menü): keine Rückfragen
[[ -n "$UPDATE" ]] && YES=1

if ((EUID == 0)); then
  warn 'Der Patch läuft als root.'
  info 'Spicetify rät davon ab: Spotify und Spicetify gehören dem normalen Benutzer. Den Patch ohne sudo starten,'
  info 'nach dem Passwort fragt er selbst, wenn er es braucht.'
  confirm 'Trotzdem fortfahren?' || die 'Abgebrochen.'
fi

if [[ -n "$UNINSTALL" ]]; then invoke_unpatch
elif [[ -n "$UPDATE" ]]; then invoke_update
else invoke_patch
fi
wait_at_end 0
exit 0
