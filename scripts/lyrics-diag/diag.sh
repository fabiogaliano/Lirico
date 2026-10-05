#!/usr/bin/env bash
# Lyrics candidate diagnostic — pulls the current track from the player Lirico
# would follow, reads the app's search settings, then runs the
# candidate/ranking comparison.
#
# Usage:
#   ./diag.sh                       # current track + Release app settings
#   ./diag.sh --debug               # read the Debug build's settings instead
#   ./diag.sh --title T --artist A [--album AL --duration SECS]   # override track
#   ./diag.sh --no-prepare          # skip the line filter (compare raw provider lines)
#   ./diag.sh --show-lines 20
#   LIRICO_DEFAULTS_DOMAIN=<domain> ./diag.sh   # read settings from any defaults domain
#
# Written for the bash 3.2 that ships with macOS: no associative arrays.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST="$HERE/../../Lirico/Supporting Files/UserDefaults.plist"
BIN="$HERE/.build/debug/lyrics-diag"
DOMAIN="${LIRICO_DEFAULTS_DOMAIN:-com.fabiogaliano.Lirico}"

TITLE=""; ARTIST=""; ALBUM=""; DURATION=""
PASS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) TITLE="$2"; shift 2;;
    --artist) ARTIST="$2"; shift 2;;
    --album) ALBUM="$2"; shift 2;;
    --duration) DURATION="$2"; shift 2;;
    --debug) DOMAIN="dev.fabiogaliano.Lirico"; shift;;
    *) PASS_ARGS+=("$1"); shift;;
  esac
done

# ---- App settings: the persisted value, else the default the app registers ----
DOMAIN_PLIST="$(mktemp -t lyrics-diag)"
trap 'rm -f "$DOMAIN_PLIST"' EXIT
if defaults read "$DOMAIN" >/dev/null 2>&1; then
  defaults export "$DOMAIN" "$DOMAIN_PLIST"
else
  echo "note: no saved settings in '$DOMAIN'; using the app's registered defaults." >&2
fi

norm_bool() {  # true/YES→1, false/NO→0, pass through otherwise
  case "$1" in true|TRUE|YES|yes) printf '1';; false|FALSE|NO|no) printf '0';; *) printf '%s' "$1";; esac
}
# plutil reports a missing key on stdout, so only a successful extraction is
# used. Arrays go through xml1 because plutil rejects JSON extraction from any
# file holding a non-JSON value, and the domain stores colors as data.
pref() {  # key raw|json
  local f out
  for f in "$DOMAIN_PLIST" "$PLIST"; do
    if [[ "$2" == json ]]; then
      out=$(plutil -extract "$1" xml1 -o - "$f" 2>/dev/null) || continue
      printf '%s' "$out" | plutil -convert json -o - -
    else
      out=$(plutil -extract "$1" raw -o - "$f" 2>/dev/null) || continue
      printf '%s' "$out"
    fi
    return
  done
}

# ---- Resolve the player the app would follow ----
# Mirrors ScriptablePlayers.autoChoice over MusicPlayerName.scriptableCases:
# the first playing player in this order, else the first paused one. The app
# also sticks with a player it's already following, which can't be seen from
# here. Only Music and Spotify can be queried; the rest are only detected.
PLAYERS="Music Spotify Vox Audirvana Swinsian"
bundle_ids() {
  case "$1" in
    Music) echo "com.apple.Music";;
    Spotify) echo "com.spotify.client";;
    Vox) echo "com.coppertino.Vox";;
    Audirvana) echo "com.audirvana.Audirvana-Studio com.audirvana.Audirvana com.audirvana.Audirvana-Plus com.audirvana.Audirvana-Origin";;
    Swinsian) echo "com.swinsian.Swinsian";;
  esac
}
is_running() {  # lsappinfo, unlike `tell application`, never launches the player
  local id
  for id in $(bundle_ids "$1"); do
    [[ -n "$(lsappinfo find "bundleid=$id" 2>/dev/null)" ]] && return 0
  done
  return 1
}
query_player() {  # prints "state" or "state\ntitle\nartist\nalbum\nduration-seconds"
  case "$1" in
    Music) osascript -e 'tell application "Music"
      set s to player state as text
      if s is "stopped" then return s
      try
        return s & linefeed & (name of current track) & linefeed & (artist of current track) & linefeed & (album of current track) & linefeed & (duration of current track)
      on error
        return s
      end try
    end tell' 2>/dev/null || echo stopped;;
    Spotify) osascript -e 'tell application "Spotify"
      set s to player state as text
      if s is "stopped" then return s
      try
        return s & linefeed & (name of current track) & linefeed & (artist of current track) & linefeed & (album of current track) & linefeed & ((duration of current track) / 1000)
      on error
        return s
      end try
    end tell' 2>/dev/null || echo stopped;;
    *) echo unknown;;
  esac
}

PLAYER="(manual args)"
if [[ -z "$TITLE" || -z "$ARTIST" ]]; then
  if [[ "$(pref UseSystemWideNowPlaying raw)" == "true" ]]; then
    echo "note: Lirico follows system-wide Now Playing, which diag can't read; checking Music and Spotify instead." >&2
  fi
  PLAYING=""; PLAYING_INFO=""; PAUSED=""; PAUSED_INFO=""; UNQUERYABLE=""
  for p in $PLAYERS; do
    is_running "$p" || continue
    info="$(query_player "$p")"
    case "$(printf '%s\n' "$info" | sed -n '1p')" in
      stopped) ;;
      paused) if [[ -z "$PAUSED" ]]; then PAUSED="$p"; PAUSED_INFO="$info"; fi;;
      unknown) UNQUERYABLE="$UNQUERYABLE $p";;
      *) PLAYING="$p"; PLAYING_INFO="$info"; break;;
    esac
  done
  if [[ -n "$PLAYING" ]]; then
    PLAYER="$PLAYING"; INFO="$PLAYING_INFO"
  elif [[ -n "$UNQUERYABLE" ]]; then
    echo "Running player(s)${UNQUERYABLE} may be the one Lirico follows but can't be queried here. Pass --title/--artist." >&2; exit 1
  elif [[ -n "$PAUSED" ]]; then
    PLAYER="$PAUSED"; INFO="$PAUSED_INFO"
  else
    echo "No supported player is playing or paused. Start playback or pass --title/--artist." >&2; exit 1
  fi
  if [[ "$(printf '%s\n' "$INFO" | wc -l)" -lt 5 ]]; then
    echo "$PLAYER reports no current track. Pass --title/--artist." >&2; exit 1
  fi
  TITLE=$(printf '%s\n' "$INFO" | sed -n '2p')
  ARTIST=$(printf '%s\n' "$INFO" | sed -n '3p')
  ALBUM=$(printf '%s\n' "$INFO" | sed -n '4p')
  DURATION=$(printf '%s\n' "$INFO" | sed -n '5p')
fi
# AppleScript formats numbers with the system locale; normalize a comma decimal
# separator (e.g. "154,48") to a dot so Swift can parse it.
DURATION="${DURATION//,/.}"

export DIAG_SOURCE_PRIORITY_ENABLED="$(norm_bool "$(pref LyricsSourcePriorityEnabled raw)")"
export DIAG_SOURCE_PRIORITY_ORDER="$(pref LyricsSourcePriorityOrder json | tr -d '[]" \n')"
export DIAG_MUSIXMATCH_TOKEN="$(pref MusixmatchToken raw)"
export DIAG_FILTER_ENABLED="$(norm_bool "$(pref LyricsFilterEnabled raw)")"
export DIAG_FILTER_KEYS_JSON="$(pref LyricsFilterKeys json)"
rm -f "$DOMAIN_PLIST"

# ---- Build (a no-op when sources are unchanged), then run ----
# Build output goes to stderr so --json stays parseable.
( cd "$HERE" && swift build --quiet >&2 )

ARGS=( --player "$PLAYER" --domain "$DOMAIN" --title "$TITLE" --artist "$ARTIST" )
[[ -n "$ALBUM" ]] && ARGS+=( --album "$ALBUM" )
[[ -n "$DURATION" ]] && ARGS+=( --duration "$DURATION" )
ARGS+=( "${PASS_ARGS[@]+"${PASS_ARGS[@]}"}" )

exec "$BIN" "${ARGS[@]}"
