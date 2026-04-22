# Claude Tracker

A native macOS menubar app that surfaces [Claude Code](https://claude.com/claude-code) usage in real time — rate-limit windows, estimated cost, active sessions, and a dedicated detail view for each session.

## What it shows

- **5-hour block** and **7-day window** — live percentages and reset times, pulled straight from Claude Code's own rate-limit payload. Flips to "Idle" when the window resets.
- **Today** and **this week** — estimated cost.
- **Active sessions** — determined by prompt-cache warmth (5-minute or 1-hour TTL), not a dumb last-ping heuristic. A session is "active" as long as your next message would still hit a warm cache.
- **By project** — Today / 7 days / All-time scope toggle.
- **Session detail window** — header with duration and cost, hourly cost chart, tool-call counts, files touched (clickable to reveal in Finder), model mix.
- **Notifications** at 80% / 95% on both the 5-hour and 7-day windows. Per-reset dedup so each window fires each threshold at most once.
- **Live pricing** — fetched from [LiteLLM's price list](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json), cached locally, configurable auto-refresh. Hardcoded fallback table if both the fetch and cache fail.

## How it works

Claude Code passes a rich JSON payload (model, context %, cost, rate limits, session id) into its statusline script on stdin. Claude Tracker piggybacks on that: your statusline script mirrors the payload to two files, and the app reads them.

- `~/.claude/statusline-input.json` — shared; account-global rate-limit state is authoritative here.
- `~/.claude/claudetracker/sessions/<session-id>.json` — per-session, so concurrent Claude Code instances never race on the same file.

Per-project / model / session detail is parsed incrementally from `~/.claude/projects/**/*.jsonl` — the same files [ccusage](https://github.com/ryoppippi/ccusage) reads. Cost estimates use live LiteLLM pricing with a hardcoded fallback.

## Install

### Homebrew tap

```
brew tap sgrl/claude-tracker
brew install --cask claude-tracker
```

### Manual

Download the latest `.dmg` from [Releases](https://github.com/sgrl/claude-tracker/releases), drag `claudetracker.app` into `/Applications/`, then run:

```
xattr -dr com.apple.quarantine /Applications/claudetracker.app
```

## Statusline setup

In most cases, nothing to do — the app installs the hook for you. On first launch the popover shows a banner offering to set it up; clicking **Install hook** writes `~/.claude/statusline-claudetracker.sh` and adds a `statusLine` entry to `~/.claude/settings.json`. Live rate-limit data appears on the next Claude Code tick.

If you already have a custom statusline configured, the installer stops and shows a **Copy bridge snippet** button (Settings → Setup). Paste the snippet into your existing script right after `input=$(cat)`. The snippet looks like this:

```bash
# --- claudetracker bridge start ---
_ctk_tmp="$HOME/.claude/statusline-input.json.$$.tmp"
printf '%s' "$input" > "$_ctk_tmp" \
  && mv "$_ctk_tmp" "$HOME/.claude/statusline-input.json"

_ctk_sid=$(printf '%s' "$input" \
  | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]+"' \
  | head -1 \
  | cut -d'"' -f4)
if [ -n "$_ctk_sid" ]; then
  _ctk_dir="$HOME/.claude/claudetracker/sessions"
  mkdir -p "$_ctk_dir"
  _ctk_sess_tmp="$_ctk_dir/${_ctk_sid}.json.$$.tmp"
  printf '%s' "$input" > "$_ctk_sess_tmp" \
    && mv "$_ctk_sess_tmp" "$_ctk_dir/${_ctk_sid}.json"
fi
# --- claudetracker bridge end ---
```

Uninstalling the hook (Settings → Setup → Uninstall) removes our managed script and clears the `statusLine` entry we added. It won't touch any statusline script you already had.

## Build from source

Requirements:

- macOS 14 (Sonoma) or later
- Xcode 15+ installed at `/Applications/Xcode.app` (Command Line Tools alone won't build `.app` targets)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

Release build:

```
bash scripts/build-release.sh
```

Package as DMG:

```
bash scripts/make-dmg.sh
```

Regenerate the app icon:

```
bash scripts/make-icon.sh
```

Development — open in Xcode:

```
xcodegen generate
open claudetracker.xcodeproj
```

Run tests:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project claudetracker.xcodeproj -scheme claudetracker test
```

## License

[MIT](LICENSE).
