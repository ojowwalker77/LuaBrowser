# phi-browser skill — setup

## 1. Install the skill

Easiest: in Phi Browser open **Settings → General → Developer**, under "Install
the phi-browser skill" click **Install** next to your agent — Claude Code
(`~/.claude/skills`), Codex (`~/.codex/skills`), or OpenClaw
(`~/.openclaw/skills`). This links the skill bundled inside the app into that
agent's `skills/phi-browser`, so it stays current with each Phi Browser update.

Or link it by hand from a source checkout (swap the destination for your agent):

```bash
ln -sfn /Users/jixiang/Phi/phibrowser-mac/tools/claude-skill/phi-browser ~/.claude/skills/phi-browser
```

Requires Node >= 22 (global WebSocket). No npm dependencies.

## 2. Enable Phi Browser's CDP endpoint (one-time, per machine)

The endpoint is OFF by default. Enable it with a user default, then relaunch
Phi Browser:

```bash
# Canary builds (scheme PhiBrowser-canary):
defaults write com.phibrowser.canary.Mac PhiRemoteDebuggingPort -int 0
# Release builds:
defaults write com.phibrowser.Mac PhiRemoteDebuggingPort -int 0
```

`0` = ephemeral port (recommended). A fixed port (e.g. `9333`) also works.
Alternatively launch the binary directly with `--remote-debugging-port=0`
(process args are forwarded to the embedded Chromium).

To disable again: `defaults delete <bundle id> PhiRemoteDebuggingPort`.

Security note: the endpoint listens on 127.0.0.1 only, but ANY local process
can control the browser through it while enabled. Leave it off when not in
use.

## 3. Verify

After relaunching Phi Browser:

```bash
cat ~/Library/Application\ Support/com.phibrowser.canary.Mac/DevToolsActivePort
# line 1: port, line 2: /devtools/browser/<uuid>
curl -s http://127.0.0.1:$(head -1 ~/Library/Application\ Support/com.phibrowser.canary.Mac/DevToolsActivePort)/json/version
```

Then a smoke round:

```bash
node ~/.claude/skills/phi-browser/scripts/runner.mjs <<'EOF'
const task = await ensureAgentSpace('smoke test')
cliLog(task)
await openTab('https://example.com')
cliLog(await pageInfo())
EOF
```

A robot (🤖) Space pip with a pulsing badge appears in the Space switcher;
click it to watch the agent live.

For a full functional pass (skill development), run the self-test instead —
it drives a throwaway hidden Space against a local HTTP server, ~60s:

```bash
node ~/.claude/skills/phi-browser/scripts/selftest.mjs
```

## Troubleshooting

- **DevToolsActivePort not found**: the default isn't set for the bundle id
  actually running (canary vs release), or the browser wasn't relaunched.
  Set `PHI_USER_DATA_DIR` to override the user-data-dir candidates.
- **Endpoint not responding**: stale DevToolsActivePort after a crash —
  relaunch Phi Browser.
- **"No Phi app connection available"**: the CDP endpoint is up but the Mac
  client's message router has no registered connection to the framework (the
  `PhiAgentSpace` domain tunnels every `agentSpace.*` call through it). Seen
  right after launch before any window exists, or when the app side is
  stopped or half-initialized (e.g. a paused Xcode debug session, or local
  changes to the embedded-extension launch flags — the router rides that
  infrastructure). Open a Phi window and retry; if it persists, relaunch
  Phi Browser. Distinct from "unknown method" below, which means the
  framework itself is too old.
- **"PhiAgentSpace.sendMessage" unknown method**: the running Phi Framework
  predates the PhiAgentSpace domain. Rebuild it:
  `autoninja -C out/PhiRelease "Phi Framework.framework"` in chromium/src,
  then rebuild/relaunch the Swift app (scheme PhiBrowser-canary).
- **create_failed from ensureAgentSpace**: no browser window is open yet —
  open one Phi window first, then retry.
