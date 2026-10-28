#!/bin/sh
# Shell-Gegenstueck zu appdata.Secure: prueft vor dem Start eines Dienstes, dass root dem Modulordner
# unter /DATA/AppData trauen kann, und setzt das Sticky-Bit auf den Elternordner.
#
#   sh appdata-guard.sh [--no-create] <ordner>...   Exit 0 = sicher, 1 = verweigert (Meldung auf stderr)
#   --no-create: ein fehlender Ordner wird verweigert statt angelegt (fuer Skripte, die bewusst nichts
#   anlegen, solange die Platte mit dem Ordner nicht da ist - sonst legte ein anderer ihn an)
#
# Warum: /DATA/AppData ist auf ZimaOS 1.8 0777 ohne Sticky-Bit (gemessen auf dem zweiten Test-NAS, 26.10.2026, KB §79.11),
# die Freigabe von /DATA ist per SMB beschreibbar - wer dort schreibt, benennt den Ordner eines Moduls um
# und legt einen eigenen hin (wg-quick-Config mit PostUp, pool.env, die root einliest). Mit Sticky-Bit
# benennt nur noch der Eigentuemer um; ein Ordner, der nicht root gehoert, wird verweigert.
#
# Einbau: als ExecStartPre= der Unit, die die Datei liest - ausser die Unit liest eine EnvironmentFile=
# aus diesem Ordner (die Umgebung gilt auch fuer ExecStartPre): dann eine eigene Guard-Unit davor.
#
# /DATA, das nicht root gehoert, bekommt root als Eigentuemer (Modus bleibt, Meldung auf stderr mit Rueckweg):
# auf nas-main gehoerte /DATA dem Login-Benutzer (uid 999, sein Home; gemessen 28.10.2026), auf nas-test und remote-cube root.
# Der Eigentuemer kann /DATA/AppData umbenennen - die Pruefung verweigerte zu Recht, und jedes Modul blieb stehen.
# Nur genau /DATA, nur ein echter Ordner; danach wird neu gemessen und wie bisher geprueft.
#
# Ein Symlink im Weg (/DATA/AppData auf eine andere Platte) wird gefolgt, wenn er in einem Schritt auf einen
# vorhandenen Ordner ohne weitere Symlinks zeigt; dann wird dieser echte Weg bis / geprueft (Meldung auf stderr).
# Frueher wurde ein Elternordner als Symlink verweigert ("kein echter Ordner"), und die Vorfahren hinter einem
# Symlink blieben ungeprueft. Wer im Forum nur den Symlink-Test strich, liess den Ordner des Ziels ungeprueft.
#
# Fuer Tests: APPDATA_GUARD_DATA (Standard /DATA) = der Ordner, der repariert wird; APPDATA_GUARD_CHOWN
# (Standard chown) = Befehl dafuer; APPDATA_GUARD_UID (Standard 0) = vertrauenswuerdiger Eigentuemer des Ordners,
# APPDATA_GUARD_PATH_UID (Standard wie APPDATA_GUARD_UID) = der Vorfahren und des Elternordners.
set -u
TRUST="${APPDATA_GUARD_UID:-0}"
PTRUST="${APPDATA_GUARD_PATH_UID:-$TRUST}"
DATA="${APPDATA_GUARD_DATA:-/DATA}"
CHOWN="${APPDATA_GUARD_CHOWN:-chown}"
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
# Vorfahr <a> des Wegs zu $dir: gehoert root (oder PTRUST) und ist geschuetzt; /DATA eines anderen wird repariert
ancestor() {
  st=$(stat -L -c '%u %a' "$1") || refuse "$1 nicht lesbar"
  uid=${st% *} mode=${st#* }
  if [ "$1" = "$DATA" ] && [ "$uid" != 0 ] && [ "$uid" != "$PTRUST" ] && [ -d "$1" ] && [ ! -L "$1" ]; then
    gid=$(stat -c %g "$1") || refuse "$1 nicht lesbar"
    $CHOWN 0:0 "$1" || refuse "$1 gehoert uid $uid - andere koennen den Weg zu $dir aendern; Eigentuemer root nicht gesetzt"
    echo "appdata-guard: $1 gehoerte uid $uid (konnte den Weg zu $dir aendern) - Eigentuemer auf root gesetzt (zurueck: chown $uid:$gid $1)" >&2
    st=$(stat -L -c '%u %a' "$1") || refuse "$1 nicht lesbar"
    uid=${st% *} mode=${st#* }
  fi
  [ "$uid" = 0 ] || [ "$uid" = "$PTRUST" ] || refuse "$1 gehoert uid $uid - andere koennen den Weg zu $dir aendern"
  protected "$mode" || refuse "$1 (Modus $mode) - andere koennen den Weg zu $dir aendern"
}

# <weg> und alle seine Vorfahren bis / (der Weg enthaelt keine Symlinks)
chain() {
  c=$1
  while :; do
    ancestor "$c"
    [ "$c" = / ] && break
    c=$(dirname "$c")
  done
}

# Ziel des Symlinks <l> als absoluter Weg; nur ein Schritt auf einen vorhandenen Weg ohne weitere Symlinks
target() {
  t=$(readlink "$1") || refuse "$1 nicht lesbar"
  case "$t" in /*) ;; *) t=$(dirname "$1")/$t ;; esac
  r=$(readlink -e "$t") || refuse "$1 zeigt auf $t, das fehlt"
  [ "$r" = "$t" ] || refuse "$1 zeigt auf $t, dort liegen weitere Symlinks oder . und .. - gefolgt wird nur einem Symlink auf einen echten Weg"
  echo "$r"
}

for dir in "$@"; do
  dir=${dir%/}
  parent=$(dirname "$dir")
  a=$(dirname "$parent")
  while :; do
    ancestor "$a"
    if [ -L "$a" ]; then r=$(target "$a") || exit 1; chain "$r"; fi
    [ "$a" = / ] && break
    a=$(dirname "$a")
  done
  if [ -L "$parent" ]; then
    r=$(target "$parent") || exit 1
    chain "$(dirname "$r")"
    echo "appdata-guard: $parent ist ein Symlink auf $r - geprueft und benutzt wird $r" >&2
    parent=$r dir=$r/$(basename "$dir")
  fi
  [ -e "$parent" ] || refuse "$parent fehlt"
  [ -d "$parent" ] || refuse "$parent ist kein Ordner"
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
