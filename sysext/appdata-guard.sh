#!/bin/sh
# Shell-Gegenstueck zu appdata.Secure: prueft vor dem Start eines Dienstes, dass root dem Modulordner
# unter /DATA/AppData trauen kann, und setzt das Sticky-Bit auf den Elternordner.
#
#   sh appdata-guard.sh [--no-create] <ordner>...   Exit 0 = sicher, 1 = verweigert (Meldung auf stderr)
#   --no-create: ein fehlender Ordner wird verweigert statt angelegt (fuer Skripte, die bewusst nichts
#   anlegen, solange die Platte mit dem Ordner nicht da ist - sonst legte ein anderer ihn an)
#
# Warum: /DATA/AppData ist auf ZimaOS 1.8 0777 ohne Sticky-Bit (gemessen .184, 26.10.2026, KB §79.11),
# die Freigabe von /DATA ist per SMB beschreibbar - wer dort schreibt, benennt den Ordner eines Moduls um
# und legt einen eigenen hin (wg-quick-Config mit PostUp, pool.env, die root einliest). Mit Sticky-Bit
# benennt nur noch der Eigentuemer um; ein Ordner, der nicht root gehoert, wird verweigert.
#
# Einbau: als ExecStartPre= der Unit, die die Datei liest - ausser die Unit liest eine EnvironmentFile=
# aus diesem Ordner (die Umgebung gilt auch fuer ExecStartPre): dann eine eigene Guard-Unit davor.
#
# Fuer Tests: APPDATA_GUARD_UID (Standard 0) = vertrauenswuerdiger Eigentuemer des Ordners,
# APPDATA_GUARD_PATH_UID (Standard wie APPDATA_GUARD_UID) = der Vorfahren und des Elternordners.
set -u
TRUST="${APPDATA_GUARD_UID:-0}"
PTRUST="${APPDATA_GUARD_PATH_UID:-$TRUST}"
refuse() { echo "appdata-guard: $*" >&2; exit 1; }

# geschuetzt: weder Gruppe noch andere duerfen schreiben, oder Sticky-Bit gesetzt
protected() { # <oktalmodus>
  m=$1
  case "$m" in ????) sticky=$(( (0$m >> 9) & 1 )) ;; *) sticky=0 ;; esac
  [ $(( 0$m & 022 )) -eq 0 ] || [ "$sticky" = 1 ]
}

CREATE=1
[ "${1:-}" = --no-create ] && { CREATE=0; shift; }
[ $# -ge 1 ] || refuse "Aufruf: appdata-guard.sh [--no-create] <ordner>..."
for dir in "$@"; do
  dir=${dir%/}
  parent=$(dirname "$dir")
  a=$(dirname "$parent")
  while :; do
    st=$(stat -L -c '%u %a' "$a") || refuse "$a nicht lesbar"
    uid=${st% *} mode=${st#* }
    [ "$uid" = 0 ] || [ "$uid" = "$PTRUST" ] || refuse "$a gehoert uid $uid - andere koennen den Weg zu $dir aendern"
    protected "$mode" || refuse "$a (Modus $mode) - andere koennen den Weg zu $dir aendern"
    [ "$a" = / ] && break
    a=$(dirname "$a")
  done
  [ -d "$parent" ] && [ ! -L "$parent" ] || refuse "$parent ist kein echter Ordner"
  st=$(stat -c '%u %a' "$parent") || refuse "$parent nicht lesbar"
  uid=${st% *} mode=${st#* }
  [ "$uid" = 0 ] || [ "$uid" = "$PTRUST" ] || refuse "$parent gehoert uid $uid"
  if ! protected "$mode"; then
    chmod +t "$parent" || refuse "Sticky-Bit auf $parent nicht gesetzt"
  fi
  if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then
    [ "$CREATE" = 1 ] || refuse "$dir fehlt"
    mkdir -m 700 "$dir" || refuse "$dir nicht angelegt"
  fi
  [ ! -L "$dir" ] || refuse "$dir ist ein Symlink"
  [ -d "$dir" ] || refuse "$dir ist kein Ordner"
  st=$(stat -c '%u %a' "$dir") || refuse "$dir nicht lesbar"
  uid=${st% *} mode=${st#* }
  [ "$uid" = 0 ] || [ "$uid" = "$TRUST" ] || refuse "$dir gehoert uid $uid, nicht root - verweigert"
  [ $(( 0$mode & 022 )) -eq 0 ] || refuse "andere duerfen in $dir schreiben (Modus $mode)"
done
exit 0
