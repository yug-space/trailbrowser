#!/bin/zsh
set -e

URLS=(
  https://example.com
  https://en.wikipedia.org/wiki/Web_browser
  https://news.ycombinator.com
  https://www.gnu.org
  https://www.python.org
  https://go.dev
  https://www.rust-lang.org
  https://www.kernel.org
  https://www.bbc.com/news
  https://www.theverge.com
  https://github.com/torvalds/linux
  https://stackoverflow.com
)
WAIT=${1:-30}
APP=TrailBrowser.app/Contents/MacOS/TrailBrowser
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

webkit_rss() { ps -axo rss,command | grep "com.apple.WebKit" | grep -v grep | awk '{s+=$1} END {printf "%d", s+0}'; }
proc_count() { ps -axo command | grep "$1" | grep -v grep | wc -l | tr -d ' '; }
# Sum RSS (KB) of a PID and all its descendants — isolates one browser instance
tree_rss() {
  ps -axo pid=,ppid=,rss= | awk -v root=$1 '
    { rssv[$1]=$3; parent[$1]=$2 }
    END {
      desc[root]=1; changed=1
      while (changed) { changed=0
        for (p in parent) if (!(p in desc) && (parent[p] in desc)) { desc[p]=1; changed=1 } }
      s=0; for (p in desc) s+=rssv[p]; printf "%d", s+0
    }'
}
tree_count() {
  ps -axo pid=,ppid= | awk -v root=$1 '
    { parent[$1]=$2 }
    END { desc[root]=1; changed=1
      while (changed) { changed=0
        for (p in parent) if (!(p in desc) && (parent[p] in desc)) { desc[p]=1; changed=1 } }
      n=0; for (p in desc) n++; print n }'
}

echo "### TrailBrowser ###"
pkill -f "$APP" 2>/dev/null || true
sleep 3
W0=$(webkit_rss)
echo "WebKit RSS baseline (TB quit): $((W0/1024)) MB"
./$APP "${URLS[@]}" >/dev/null 2>&1 &
TBPID=$!
echo "launched pid $TBPID with ${#URLS[@]} tabs; waiting ${WAIT}s..."
sleep $WAIT
W1=$(webkit_rss)
APPRSS=$(ps -o rss= -p $TBPID | tr -d ' ')
TB_WEBKIT=$((W1-W0))
TB_TOTAL=$((TB_WEBKIT+APPRSS))
WC=$(proc_count "com.apple.WebKit.WebContent")
echo "WebKit RSS running: $((W1/1024)) MB | delta(TB WebKit): $((TB_WEBKIT/1024)) MB | app: $((APPRSS/1024)) MB"
echo "WebContent processes (system-wide, incl Safari): $WC"
echo "==> TrailBrowser total (delta WebKit + app): $((TB_TOTAL/1024)) MB"
pkill -f "$APP" 2>/dev/null || true
sleep 2

echo ""
echo "### Chrome (throwaway profile, same URLs) ###"
TMPDIR_CHROME=$(mktemp -d)
"$CHROME" --user-data-dir="$TMPDIR_CHROME" --no-first-run --no-default-browser-check \
  --disable-extensions "${URLS[@]}" >/dev/null 2>&1 &
CHPID=$!
echo "launched pid $CHPID (isolated profile); waiting ${WAIT}s..."
sleep $WAIT
CH_TOTAL=$(tree_rss $CHPID)
echo "Chrome instance processes (this tree only): $(tree_count $CHPID)"
echo "==> Chrome total RSS (launched instance only): $((CH_TOTAL/1024)) MB"
kill $CHPID 2>/dev/null || true
sleep 2
rm -rf "$TMPDIR_CHROME"

echo ""
echo "### RESULT (${#URLS[@]} tabs, ${WAIT}s settle) ###"
echo "TrailBrowser: $((TB_TOTAL/1024)) MB"
echo "Chrome:       $((CH_TOTAL/1024)) MB"
if [ $CH_TOTAL -gt 0 ]; then
  echo "Ratio TB/Chrome: $(echo "scale=2; $TB_TOTAL/$CH_TOTAL" | bc)"
fi
