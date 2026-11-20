#!/usr/bin/env bash
# Ververst de meegeleverde kobo.koplugin vanuit GitHub.
#
#   tools/update-plugin.sh            nieuwste commit op main (nieuwste Bluetooth-fixes)
#   tools/update-plugin.sh v0.4.1     een bepaalde release-tag (ouder, maar "officieel")
#   tools/update-plugin.sh <commit>   een bepaalde commit
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-main}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git clone -q https://github.com/OGKevin/kobo.koplugin "$TMP/src"
git -C "$TMP/src" checkout -q "$REF"
COMMIT="$(git -C "$TMP/src" rev-parse HEAD)"

DEST="$HERE/payload/koreader/plugins/kobo.koplugin"
rm -rf "$DEST"
mkdir -p "$DEST"
(cd "$TMP/src" && cp _meta.lua main.lua README.md CHANGELOG.md LICENSE "$DEST/" && cp -R src "$DEST/")
echo "$COMMIT" >"$HERE/PLUGIN_COMMIT"

echo "kobo.koplugin bijgewerkt naar $REF ($COMMIT)."
echo "Controleer of de patch nog klopt: luajit test/test_patch.lua"
