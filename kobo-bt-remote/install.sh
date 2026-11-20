#!/usr/bin/env bash
# Installeert kobo.koplugin + de remote-setup-patch op een via USB verbonden Kobo.
#
#   ./install.sh                 zoekt de Kobo en installeert
#   ./install.sh --wait          wacht tot de Kobo verbonden is en installeert dan
#   ./install.sh /pad/naar/kobo  gebruik dit koppelpunt
#   ./install.sh --dry-run       laat alleen zien wat er zou gebeuren
#
# Werkt op macOS en Linux. Voor Windows: install.ps1.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$HERE/payload/koreader"
WAIT=0
DRY=0
MOUNT=""

for arg in "$@"; do
    case "$arg" in
        --wait) WAIT=1 ;;
        --dry-run) DRY=1 ;;
        -h | --help)
            sed -n '2,9p' "$0"
            exit 0
            ;;
        *) MOUNT="$arg" ;;
    esac
done

say() { printf '%s\n' "$*"; }
run() {
    if [ "$DRY" = 1 ]; then
        say "  [dry-run] $*"
    else
        "$@"
    fi
}

is_kobo() { [ -d "$1/.kobo" ] && [ -f "$1/.kobo/version" ]; }

find_kobo() {
    local candidates=(
        "/Volumes/KOBOeReader"
        "/media/${USER:-}/KOBOeReader"
        "/run/media/${USER:-}/KOBOeReader"
        "/media/KOBOeReader"
        "/mnt/KOBOeReader"
    )
    local c
    for c in "${candidates[@]}" /Volumes/* /media/"${USER:-}"/* /run/media/"${USER:-}"/*; do
        if [ -d "$c" ] && is_kobo "$c"; then
            printf '%s\n' "$c"
            return 0
        fi
    done 2>/dev/null
    return 1
}

if [ -n "$MOUNT" ]; then
    is_kobo "$MOUNT" || {
        say "Fout: $MOUNT lijkt geen Kobo te zijn (geen .kobo/version)."
        exit 1
    }
else
    if ! MOUNT="$(find_kobo)"; then
        if [ "$WAIT" = 1 ]; then
            say "Wachten op de Kobo... (sluit hem aan en tik op 'Verbinden'; Ctrl+C om te stoppen)"
            until MOUNT="$(find_kobo)"; do sleep 2; done
            sleep 3 # laat het bestandssysteem even rustig worden
        else
            say "Geen Kobo gevonden. Sluit hem aan via USB, tik op 'Verbinden' en probeer opnieuw,"
            say "of gebruik: ./install.sh --wait   of   ./install.sh /pad/naar/KOBOeReader"
            exit 1
        fi
    fi
fi

KOREADER="$MOUNT/.adds/koreader"
say "Kobo gevonden op: $MOUNT"
say "Firmware/model-regel: $(head -n1 "$MOUNT/.kobo/version")"

if [ ! -d "$KOREADER" ]; then
    say "Fout: KOReader is niet gevonden in $KOREADER. Installeer eerst KOReader."
    exit 1
fi

# Model-check op basis van het apparaat-ID (laatste 3 cijfers van .kobo/version)
DEVID="$(head -n1 "$MOUNT/.kobo/version" | tr -d '\r' | awk -F, '{print $NF}' | tail -c 4)"
# 388/389 bevestigd; overige IDs zijn "waarschijnlijk". De patch op de Kobo
# controleert het model zelf exact, dit is alleen informatief.
case "$DEVID" in
    388) MODEL="Kobo Libra 2" ; SUPPORTED=1 ;;
    389) MODEL="Kobo Elipsa 2E" ; SUPPORTED=1 ;;
    390 | 391 | 393) MODEL="Kobo Libra Colour / Clara BW / Clara Colour (waarschijnlijk)" ; SUPPORTED=1 ;;
    383) MODEL="Kobo Sage (waarschijnlijk)" ; SUPPORTED=0 ;;
    386) MODEL="Kobo Clara 2E (waarschijnlijk)" ; SUPPORTED=0 ;;
    387) MODEL="Kobo Elipsa (waarschijnlijk)" ; SUPPORTED=0 ;;
    *) MODEL="onbekend" ; SUPPORTED=2 ;;
esac
say "Model (op basis van ID $DEVID): $MODEL"
if [ "$SUPPORTED" = 0 ]; then
    say ""
    say "LET OP: dit model wordt niet ondersteund door kobo.koplugin's Bluetooth."
    say "Zie README.md, sectie 'Mijn model wordt niet ondersteund'. De installatie gaat"
    say "door, maar de oude Bluetooth-plugin blijft dan ingeschakeld."
    say ""
elif [ "$SUPPORTED" = 2 ]; then
    say "(Model niet herkend door dit script; de patch op de Kobo controleert het zelf nog.)"
fi

# Back-up naar de computer
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HERE/backups/$STAMP"
say ""
say "Back-up maken in: $BACKUP"
run mkdir -p "$BACKUP"
[ -f "$KOREADER/settings.reader.lua" ] && run cp "$KOREADER/settings.reader.lua" "$BACKUP/"
[ -d "$KOREADER/plugins" ] && for d in "$KOREADER"/plugins/*.koplugin; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in
        kobo.koplugin | *[Bb]luetooth* | bt* | *pageturn* | *page_turn*) run cp -R "$d" "$BACKUP/" ;;
    esac
done
[ -d "$KOREADER/patches" ] && run cp -R "$KOREADER/patches" "$BACKUP/patches"

# Oude/andere Bluetooth-plugins melden (de patch schakelt ze op de Kobo uit)
OTHERS=""
for d in "$KOREADER"/plugins/*.koplugin; do
    [ -d "$d" ] || continue
    n="$(basename "$d" .koplugin)"
    [ "$n" = "kobo" ] && continue
    case "$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')" in
        *bluetooth* | bt* | *pageturn* | *page_turn* | *btremote*) OTHERS="$OTHERS $n" ;;
    esac
done
if [ -n "$OTHERS" ]; then
    say "Andere Bluetooth-plugin(s) gevonden:$OTHERS"
    if [ "$SUPPORTED" != 0 ]; then
        say "  -> worden bij de eerste start automatisch uitgeschakeld (niet verwijderd)."
    fi
fi

# Installeren
say ""
say "Installeren..."
run mkdir -p "$KOREADER/plugins" "$KOREADER/patches"
run rm -rf "$KOREADER/plugins/kobo.koplugin"
run cp -R "$PAYLOAD/plugins/kobo.koplugin" "$KOREADER/plugins/"
run cp "$PAYLOAD/patches/2-bt-remote-setup.lua" "$KOREADER/patches/"

# macOS laat ._-bestanden achter op FAT-schijven; die verwarren KOReader niet, maar ruim ze op
if [ "$(uname)" = "Darwin" ] && [ "$DRY" = 0 ]; then
    find "$KOREADER/plugins/kobo.koplugin" "$KOREADER/patches" -name '._*' -delete 2>/dev/null || true
    dot_clean -m "$KOREADER" 2>/dev/null || true
fi
run sync

say ""
say "Klaar. Geïnstalleerd:"
say "  $KOREADER/plugins/kobo.koplugin  (versie $(grep -o '"[0-9.]*"' "$PAYLOAD/plugins/kobo.koplugin/_meta.lua" | head -1 | tr -d '"'), commit $(cat "$HERE/PLUGIN_COMMIT" 2>/dev/null || echo '?'))"
say "  $KOREADER/patches/2-bt-remote-setup.lua"
say ""
say "Volgende stappen:"
say "  1. Werp de Kobo veilig uit en koppel los."
say "  2. Start KOReader (opnieuw). Bluetooth gaat nu vanzelf aan."
say "  3. Koppel de 8BitDo één keer: zie README.md, stap 'Eerste keer koppelen'."
