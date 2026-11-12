#!/bin/zsh
# Compare TrailBrowser vs Chrome resident memory loading the same tabs.
# Isolates each browser so a running Safari/Chrome can't skew the numbers:
#   - Chrome: sum the launched instance's process tree.
#   - TrailBrowser: sum the app plus only the WebKit processes that appear
#     after launch (WebKit XPC services are reparented to launchd, not the app).
set -e
cd "${0:A:h}/.."   # run from repo root regardless of caller's cwd

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

# PIDs of all live WebKit XPC processes (WebContent/Networking/GPU).
webkit_pids() { pgrep -f "com.apple.WebKit" 2>/dev/null | sort -u; }
# Sum RSS (KB) of a given newline-separated PID list.
rss_of_pids() {
  [ -z "$1" ] && { printf 0; return; }
  ps -o rss= -p "$(echo "$1" | tr '\n' ',')" 2>/dev/null | awk '{s+=$1} END {printf "%d", s+0}'
}
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
BEFORE=$(webkit_pids)            # WebKit processes that already exist (e.g. Safari)
./$APP "${URLS[@]}" >/dev/null 2>&1 &
TBPID=$!
echo "launched pid $TBPID with ${#URLS[@]} tabs; waiting ${WAIT}s..."
sleep $WAIT
set +e                           # ps may fail if the app exited; don't abort the run
AFTER=$(webkit_pids)
NEW_WEBKIT=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER"))   # only TB's new WebKit procs
TB_WEBKIT=$(rss_of_pids "$NEW_WEBKIT")
APPRSS=$(ps -o rss= -p $TBPID 2>/dev/null | tr -d ' '); APPRSS=${APPRSS:-0}
TB_TOTAL=$((TB_WEBKIT+APPRSS))
set -e
echo "TB WebKit procs: $(echo "$NEW_WEBKIT" | grep -c . ) | WebKit RSS: $((TB_WEBKIT/1024)) MB | app: $((APPRSS/1024)) MB"
echo "==> TrailBrowser total (app + its WebKit processes): $((TB_TOTAL/1024)) MB"
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
