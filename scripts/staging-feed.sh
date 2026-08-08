#!/usr/bin/env bash
#
# Serve a Sparkle appcast on localhost, so the update path can be rehearsed
# before it is real for anyone.
#
# Why this exists: the only way to know an update *installs* is to watch one
# install. Doing that against the live feed means the first rehearsal is also
# the performance — every user checking for updates in that window gets whatever
# you were testing. This serves the same appcast to one machine instead.
#
# It also makes the tamper check cheap. A signature verifier nobody has watched
# reject something is only known to accept, and flipping a character in a local
# feed is a two-second edit.
#
#   ./scripts/staging-feed.sh <path-to-appcast-item.xml> <path-to.dmg> [port]
#
# `build-dmg.sh` writes the item to dist/appcast-item-<version>.xml. Pass that
# and the DMG it describes — the enclosure URL has to resolve to a real file, or
# the rehearsal only proves the feed parses.
#
# Then build the *older* version with its feed pointed here — Sparkle requires
# HTTPS for a feed unless the app allows the exception, so the scratch build
# needs both, in HomeRec/Info.plist:
#
#     <key>SUFeedURL</key>
#     <string>http://127.0.0.1:8765/appcast.xml</string>
#     <key>NSAppTransportSecurity</key>
#     <dict>
#       <key>NSAllowsLocalNetworking</key><true/>
#     </dict>
#
# ⚠️ Never commit a build with those two keys. `SUFeedURL` is a permanent
# contract with every copy of the app ever shipped; a scratch value that escapes
# into a release points those copies at a machine that is not on.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

ITEM="${1:?usage: staging-feed.sh <appcast-item.xml> <update.dmg> [port]}"
DMG="${2:?usage: staging-feed.sh <appcast-item.xml> <update.dmg> [port]}"
PORT="${3:-8765}"

[ -f "$ITEM" ] || { echo "error: no such item file: $ITEM" >&2; exit 1; }
[ -f "$DMG" ]  || { echo "error: no such DMG: $DMG" >&2; exit 1; }

STAGING_DIR="$(mktemp -d)"
FEED="$STAGING_DIR/appcast.xml"
cp "$DMG" "$STAGING_DIR/$(basename "$DMG")"

# The entry's `length` is what Sparkle checks the download against, and a
# mismatch fails after the download rather than before it. Catch it here.
ITEM_LEN="$(sed -nE 's/.*length="([0-9]+)".*/\1/p' "$ITEM" | head -1)"
REAL_LEN="$(stat -f%z "$DMG")"
if [ -n "$ITEM_LEN" ] && [ "$ITEM_LEN" != "$REAL_LEN" ]; then
  echo "error: the entry says length=$ITEM_LEN but the DMG is $REAL_LEN bytes." >&2
  echo "       The item was built for a different file — re-sign it." >&2
  exit 1
fi

# The channel wrapper is the live feed's, minus the commentary — the point is to
# serve something structurally identical to production, so a failure here means
# the entry is wrong rather than the scaffolding.
{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
  echo '  <channel>'
  echo '    <title>Home Rec (staging)</title>'
  echo "    <link>http://127.0.0.1:$PORT/appcast.xml</link>"
  echo '    <description>Local rehearsal feed. Not served to anyone.</description>'
  echo '    <language>en</language>'
  cat "$ITEM"
  echo '  </channel>'
  echo '</rss>'
} > "$FEED"

echo "Staging feed assembled from $(basename "$ITEM"):"
echo
sed -n 's/^ *//p' "$FEED" | grep -E "sparkle:(short)?[Vv]ersion|enclosure url|length=" | sed 's/^/  /'
echo
echo "Serving http://127.0.0.1:$PORT/appcast.xml"
echo "Point a scratch build's SUFeedURL there. Ctrl-C to stop."
echo
echo "To rehearse the tamper check, edit this file and change one character of"
echo "sparkle:edSignature — Sparkle must refuse the update:"
echo "  $FEED"
echo

# `--bind 127.0.0.1` on purpose: loopback only. A feed bound to 0.0.0.0 is
# reachable by anything on the network, which is the opposite of the point.
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$STAGING_DIR"
