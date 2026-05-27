#!/usr/bin/env bash
# Lyrics candidate diagnostic — auto-pulls the current track from the music
# player that Lirico/Lirico is configured to use, reads the app's real search
# settings, then runs the candidate/ranking comparison.
#
# Usage:
#   ./diag.sh                       # use configured player's current track + real settings
#   ./diag.sh --title T --artist A [--album AL --duration SECS]   # override track
#   ./diag.sh --no-prepare          # skip the line filter (compare raw provider lines)
#   ./diag.sh --show-lines 20
set -euo pipefail

DOMAIN="com.fabiogaliano.Lirico"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST="$HERE/../../Lirico/Supporting Files/UserDefaults.plist"
BIN="$HERE/.build/debug/lyrics-diag"

norm_bool() {  # true/YES→1, false/NO→0, pass through otherwise
  case "$1" in true|TRUE|YES|yes) printf '1';; false|FALSE|NO|no) printf '0';; *) printf '%s' "$1";; esac
}
read_default() {  # key  fallback  — persisted value, else registered default, else fallback
  local key="$1" fallback="$2" val
  if val=$(defaults read "$DOMAIN" "$key" 2>/dev/null); then norm_bool "$val"; return; fi
  if val=$(plutil -extract "$key" raw -o - "$PLIST" 2>/dev/null); then norm_bool "$val"; return; fi
  norm_bool "$fallback"
}

# ---- Resolve the configured player (mirrors MusicPlayers.Selected.selectPlayer) ----
PLAYER_IDX=$(read_default PreferredPlayerIndex 1)
declare -A PLAYER_BY_IDX=( [0]="Music" [1]="Spotify" [2]="Vox" [3]="Audirvana" [4]="Swinsian" )
PLAYER=""
if [[ "$PLAYER_IDX" == "-1" ]]; then
  for p in Spotify Music; do
    if osascript -e "tell application \"System Events\" to (name of processes) contains \"$p\"" 2>/dev/null | grep -q true; then PLAYER="$p"; break; fi
  done
  [[ -z "$PLAYER" ]] && PLAYER="Spotify"
else
  PLAYER="${PLAYER_BY_IDX[$PLAYER_IDX]:-Spotify}"
fi

# ---- Pull current track from that player (unless overridden via --title/--artist) ----
TITLE=""; ARTIST=""; ALBUM=""; DURATION=""
PASS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) TITLE="$2"; shift 2;;
    --artist) ARTIST="$2"; shift 2;;
    --album) ALBUM="$2"; shift 2;;
    --duration) DURATION="$2"; shift 2;;
    *) PASS_ARGS+=("$1"); shift;;
  esac
done

if [[ -z "$TITLE" || -z "$ARTIST" ]]; then
  if [[ "$PLAYER" == "Spotify" ]]; then
    INFO=$(osascript -e 'tell application "Spotify"
      if it is running and player state is not stopped then
        return (get name of current track) & "\n" & (get artist of current track) & "\n" & (get album of current track) & "\n" & ((duration of current track) / 1000)
      else
        return "NOTPLAYING"
      end if
    end tell' 2>/dev/null) || INFO="NOTPLAYING"
  elif [[ "$PLAYER" == "Music" ]]; then
    INFO=$(osascript -e 'tell application "Music"
      if it is running and player state is not stopped then
        return (get name of current track) & "\n" & (get artist of current track) & "\n" & (get album of current track) & "\n" & (duration of current track)
      else
        return "NOTPLAYING"
      end if
    end tell' 2>/dev/null) || INFO="NOTPLAYING"
  else
    echo "Player '$PLAYER' is not scriptable here. Pass --title/--artist manually." >&2; exit 1
  fi
  if [[ "$INFO" == "NOTPLAYING" || -z "$INFO" ]]; then
    echo "No track playing in $PLAYER. Start playback or pass --title/--artist." >&2; exit 1
  fi
  TITLE=$(echo "$INFO" | sed -n '1p')
  ARTIST=$(echo "$INFO" | sed -n '2p')
  ALBUM=$(echo "$INFO" | sed -n '3p')
  DURATION=$(echo "$INFO" | sed -n '4p')
fi
# AppleScript formats numbers with the system locale; normalize a comma decimal
# separator (e.g. "154,48") to a dot so Swift can parse it.
DURATION="${DURATION//,/.}"

# ---- Read real app search settings ----
export DIAG_SOURCE_PRIORITY_ENABLED="$(read_default LyricsSourcePriorityEnabled 0)"
ORDER=$(defaults read "$DOMAIN" LyricsSourcePriorityOrder 2>/dev/null | tr -d '()" \n' || true)
export DIAG_SOURCE_PRIORITY_ORDER="$ORDER"
export DIAG_MUSIXMATCH_TOKEN="$(defaults read "$DOMAIN" MusixmatchToken 2>/dev/null || true)"
export DIAG_FILTER_ENABLED="$(read_default LyricsFilterEnabled 1)"
# Filter keys: live domain if set, else the registered default from the plist.
if defaults read "$DOMAIN" LyricsFilterKeys >/dev/null 2>&1; then
  TMP=$(mktemp).plist; defaults export "$DOMAIN" "$TMP"
  export DIAG_FILTER_KEYS_JSON="$(plutil -extract LyricsFilterKeys json -o - "$TMP" 2>/dev/null || plutil -extract LyricsFilterKeys json -o - "$PLIST")"
  rm -f "$TMP"
else
  export DIAG_FILTER_KEYS_JSON="$(plutil -extract LyricsFilterKeys json -o - "$PLIST" 2>/dev/null || echo '[]')"
fi

# ---- Build if needed, then run ----
if [[ ! -x "$BIN" ]]; then ( cd "$HERE" && swift build ); fi

ARGS=( --player "$PLAYER" --title "$TITLE" --artist "$ARTIST" )
[[ -n "$ALBUM" ]] && ARGS+=( --album "$ALBUM" )
[[ -n "$DURATION" ]] && ARGS+=( --duration "$DURATION" )
ARGS+=( "${PASS_ARGS[@]+"${PASS_ARGS[@]}"}" )

exec "$BIN" "${ARGS[@]}"
