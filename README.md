# Saturn

**Your day, within reach.** A native workspace for Omarchy: tasks, focus, daily notes, calendar, mail and a desktop assistant.

[Website & interactive preview](https://saturn.vercel.app/) · [Releases](https://github.com/k0d3d/saturn/releases) · [Report an issue](https://github.com/k0d3d/saturn/issues)

Saturn runs inside Omarchy's Quickshell desktop. Hover over its bar icon for a quick look, click to pin it, or right-click for the full workspace. It follows your current theme. An application-menu launcher opens the same native workspace. This is an Omarchy Linux plugin, not an Electron wrapper or a cross-platform standalone app.

## Installation

Requires **Omarchy with its plugin-capable Quickshell shell** (tested on Omarchy 4.0.4), Git, Python 3.11+, Qt Quick Controls and `notify-send`. Omarchy supplies the desktop dependencies. Local tasks, notes and focus need no account. Node.js is only used for website development.

```sh
curl -fsSL https://saturn.vercel.app/install.sh | bash
```

[Inspect the installer](install.sh). It clones the public repository, validates the manifest, enables `k0d3d.saturn`, and installs a user-local application launcher. It never uses sudo, changes keyboard shortcuts or includes account credentials.

Alternatively, use Omarchy's plugin manager:

```sh
omarchy plugin add https://github.com/k0d3d/saturn.git --enable
bash ~/.config/omarchy/plugins/k0d3d.saturn/scripts/install-desktop.sh
```

The plugin also initializes its storage when installed directly through the plugin manager. Open **Saturn** in the application menu, or run `saturn`.

### Updating and removing

```sh
omarchy plugin update k0d3d.saturn
```

If a QML dependency remains cached, run `omarchy restart shell` after updating. Your local tasks, notes, credentials and focus history are stored outside the plugin directory.

Disable with `omarchy plugin disable k0d3d.saturn`; remove with `omarchy plugin remove k0d3d.saturn`. To remove launcher files too, remove `~/.local/bin/saturn`, the deprecated `~/.local/bin/omapulse` and `~/.local/bin/omaowl` aliases, `$XDG_DATA_HOME/applications/saturn.desktop` and `$XDG_DATA_HOME/icons/hicolor/scalable/apps/saturn.svg` (data home defaults to `~/.local/share`). User data is deliberately retained.

Upgrading from Oma Pulse (`kosta.omaowl`): remove the old id with `omarchy plugin remove kosta.omaowl` (keeps your data), then install Saturn. On first start Saturn migrates `~/.local/share/omaowl/workspace.json` to `~/.local/share/saturn/workspace.json` (schema 2) with a timestamped backup under `$XDG_DATA_HOME/omaowl-backups/`, and copies private credentials from `~/.config/omaowl` and `~/.config/oma-pulse` into `~/.config/saturn`. The originals are never deleted. For a local prototype, inspect `install.sh` and run `bash install.sh --adopt`. Ordinary installation refuses to overwrite an existing plugin.

### Keyboard shortcut

Bind `saturn command` in your Hyprland bindings using a key you choose. Existing Super+N bindings from the local prototype continue to work; a fresh install does not claim that shortcut. `saturn dashboard` opens full screen; Escape returns to the compact workspace.

On this workstation, **Super+Alt+N** opens the full dashboard. Its binding is
`o.bind("SUPER + ALT + N", "Saturn full dashboard", "saturn dashboard")`.

## Formerly Oma Pulse / Oma Owl

Version 0.8.0 renames the project to **Saturn** and the plugin id to `k0d3d.saturn`. Data and credentials migrate automatically as described above. The deprecated `omapulse` and `omaowl` commands and IPC aliases keep existing shortcuts working for one release; new shortcuts should use `saturn`. Run the desktop installer once to refresh the app-menu name and icon.

## Connections

Open **Connections** to choose your mail and calendar providers. Tasks are always local and need no account; you can switch between HEY, Gmail, Outlook and IMAP mail, and between OmaCal and direct Google Calendar. See the [connection setup guide](CONNECTIONS.md). New Google/Microsoft adapters are beta and require your own OAuth app registration; live-account sign-in has not yet been verified.

All integrations are optional:

| Connection | Setup | Adds |
| --- | --- | --- |
| OmaCal | Install OmaCal and connect a calendar there | Read-only daily event feed and links to the full calendar |
| IMAP | Connections → TLS server, username and app password | Unread headers, mark read and Undo |
| Gmail / Outlook | Connections → account setup with your OAuth client ID | Unread inbox, mark read and Undo |
| Google Calendar | Connections → Google Calendar OAuth setup | Read-only eight-day feed without OmaCal |
| HEY | Install a compatible `hey` CLI and run `hey auth login` | New for You, mark read and Undo |
| Codex | Install Codex CLI and run `codex login` | Assistant answers and supported desktop actions |
| Voxtype | Install and configure Voxtype's daemon | Dictation into the command input |

The HEY adapter expects the CLI's `box view imbox --json`, `seen` / `unseen`, and `watch` commands. Codex uses `exec` with structured output and an existing login. These optional CLIs can change; check helper errors and your installed CLI version when troubleshooting. Third-party services may require accounts or paid plans. No service subscription is included.

## Messages

The **Workspace** tab includes a Messages card next to mail, with unread counts,
scrollable previews, refresh, and an **Open messages** button. Open **Messages**
(or run `saturn messages`) for the full unread conversation view.

Message sources default to **Text messages (Blip)** only. Use **Sources** in the
workspace Messages widget, Messages page, or Connections to enable **Slack (via
Beeper)** and **Other Beeper messages** independently. These choices persist and
apply before Key/All filtering, unread counts and previews. Disabling a provider
stops polling it when none of its sources are selected, while retaining its connection.
**Texts** shows Blip; **Slack** filters Slack accounts connected to Beeper; **Beeper**
shows all Beeper networks. Click a row to open that exact conversation in Blip or
Beeper. Slack opens inside Beeper. There is no separate Slack OAuth connection.

Previews refresh every 30 seconds while Workspace, Messages, or Connections is visible.
Reading the preview list does not mark conversations read; opening the source app
uses that app’s normal read behavior. Content stays in memory, outside the saved
workspace and assistant context. A connection failure is shown alongside the feed.

Click **✓** on a conversation in either view to mark it read. Pulse removes it
once the provider confirms the change; new arrivals remain unread and can bring
it back. Blip uses its local read ledger and existing `push_read` policy: the
usual `all` setting clears Blip/Pulse but does not push individual reads to the
phone. `thread` also requests per-conversation sync through the Mac.

Blip needs the optional preview/read bridge; Beeper needs a Desktop API token.
See [message setup](CONNECTIONS.md#messages-blip-and-beeper-including-slack).

**Key messages** is the default in both the card and full view. A local preview
filter hides likely sales and automated texts while keeping personal conversations
and work chats. Switch to **All** to review
everything. The **⋯** menu on each conversation lets you always keep it, hide it
from Key, or return to automatic filtering. These choices are saved locally as
conversation IDs and preferences, with no message text. **Keep useful alerts**
in the full view can include verification codes, deliveries and appointment
reminders; it is off by default.

The filter also handles dollar-off deals, early-access/restock campaigns, bare
shopping links, and opt-out variants such as “TXT STOP” and “STOP to stop”.

Filtering is a best-effort guess from the latest preview, not contact-list or
whole-thread analysis. It never deletes, blocks or marks anything read. Unknown
texts remain visible by default; review All if something seems missing.

## Tasks

Tasks are local to this computer. No account is needed and nothing is uploaded.

- **Today** shows overdue and undated tasks plus anything due today.
- **Upcoming** shows future-dated tasks in date order; **All** shows every active task.
- **Completed** keeps finished tasks in view, newest first. The circle reopens a task.
- **Archive** hides a task from every active list. Use ↩ to restore it.
- The add field understands `tomorrow`, `today`, `next Mon` and `YYYY-MM-DD`;
  the **Today** / **Tomorrow** chips and the due field set an explicit date.
- ▶ selects a task for the focus timer. Long titles wrap in full.
- Tasks are stored with `due`, `completedAt`, `archived`, tags and timestamps in
  `~/.local/share/saturn/workspace.json`, so an AI agent can read and update them.
- `saturn tasks` lists tasks; `saturn tasks add "Buy milk tomorrow"`,
  `saturn tasks complete <id>`, `saturn tasks archive <id>`,
  `saturn tasks restore <id>` and `saturn tasks due <id> 2026-11-24` work from the shell.

## Calendar

Use ‹ / › in the Events card to switch days, and **Back to today** to reset.
The date and full day's events change together. Arrows stop at the limits of
OmaCal's feed, currently today plus seven days. Event times use OmaCal's published
clock labels where available. Calendar access is read only; synchronization is
managed by OmaCal. No extra calendar account connection is needed for the OmaCal source. Alternatively, select Google Calendar in Connections and sign in directly; the default is your primary calendar. Clicking an event opens the selected full calendar on that day and closes Saturn. Weekday names appear above dates.

## Focus and notes

25/50-minute presets, custom minutes, stopwatch, pause/resume and +5 minutes.
A small, square timer notch appears below the top bar while running and the workspace is closed.
Click its time/title to return to the workspace, or pause directly from the notch. It disappears
when paused or finished. Completion sends a desktop notification.
Sessions pause after sleep or a clock gap longer than three seconds. Restarts
restore sessions paused, so unattended time is not counted as active work.

Daily notes autosave. ‹ / › browse older days; Today resets the date.
Ctrl+Enter adds the current line to the selected task source and preserves the note.
Workspace and full-screen views share the same live data.

## Assistant and voice

The command bar and **Assistant** tab share a session-only conversation. Codex uses the existing
ChatGPT CLI login; it receives the request plus the displayed tasks, calendar, note, and optional
mail previews. Turn off **Include mail previews** in the Assistant tab to omit mail.

Installed-app matches and common explicit commands (focus, volume, add task, file search, and calendar day) run locally without an AI request. Try `start 25 minutes of focus`, `volume 40%`, or `add task Buy milk tomorrow`. Codex returns a structured plan;
direct requests run automatically, including “make a timer for 10min”. Ask for a preview to get action cards with **Run** buttons. Multi-step actions run in order and stop if an action fails. Supported actions are focus control, local tasks, app/web/document opening, common-folder file search, volume, calendar navigation,
and appending notes. Results are shown after execution. It can answer questions and draft text,
but this version does not send mail, modify arbitrary system settings, or execute generated shell code.

**Voice** uses the existing Voxtype daemon. Click again to stop; the transcript fills the input
for review before submission. Optional **Hey Saturn** adds hands-free commands and spoken replies; see below. Closing the
window cancels an active Saturn recording. Codex can use live web search for weather, news, and current facts. Answers include source links. Desktop tool access stays disabled, with an isolated
working directory; it only proposes actions, which the app validates and runs for direct requests.

## Hey Saturn voice control

Say **“Hey Saturn”**, then your request. A short two-note chime confirms it heard you. The wake phrase is detected locally with
Vosk and confirmed locally with Whisper; no local voice or planner answers it.
After confirmation, a Grok voice session starts. A bounded RAM buffer preserves
the wake phrase and request during connection setup, then audio streams directly
to Grok. Wake mode sends 16 kHz microphone audio and plays 24 kHz Grok audio.

Grok controls the desktop directly through a fixed list of actions, so spoken
commands run at once and can be chained in one breath ("set the volume to 30,
switch to Slack and take a screenshot"): open or switch to apps, open sites,
move, close, float or fullscreen windows, change workspace, volume, media,
brightness, night light, do not disturb, theme and wallpaper, take a screenshot,
lock the screen, type dictated text into the focused app, report system status,
find and open files, run focus timers, and add tasks or notes. Every step is
validated before any of them runs. Questions about existing tasks, calendar,
notes or inbox still go to the Pulse assistant. Voice itself cannot run shell
commands, delete files, install software or send messages.

It can hand work to the AI agents on this computer: the agents running in
[Herdr](https://herdr.dev) (“ask Codex 22 to fix the failing tests”, “what are my
agents doing?”, “have a new Claude look at this”) and the Grok Bot desktop app
(“tell Grok Bot to …” for your main bot, set under **Connections → Grok Bot · Main bot**, or a bot’s own name to reach that one; with no main bot set, the open chat gets it). The task is sent as soon as you say it, with a
notification showing exactly what went out and to whom. Pulse
tells you when the agent finishes or needs approval; agents keep their own
permission settings. A message to Grok Bot is typed into its window, so its
reply is read there, not aloud.

Enable **Connections → Hey Saturn · Wake Grok**, or `saturn voiceWakeEnable`.
The enabled preference survives desktop restarts. Continue a conversation without
repeating the wake phrase. After a minute of silence or five minutes of cloud
conversation, cloud audio stops and local wake detection rearms. Locking or
starting dictation ends cloud streaming and pauses local wake detection.
**Escape** or asking Grok to end the conversation stops cloud audio and rearms
Hey Saturn; while it is only armed, Escape does nothing. **Shift+Escape** or
**Mic off** turns the microphone off entirely. Enable Hey Saturn again to rearm it.

Wake mode is built to stay on. A dropped network, a rejected session or a
microphone that disappears ends only that conversation: Hey Saturn reports the
problem and keeps listening, retrying the microphone with a short backoff. If the
listener itself dies, the shell restarts it. The setting survives shell restarts.

**Ctrl+Alt+P** starts a direct Grok conversation when voice is off and stops voice
when it is on. **Stop reply** interrupts only the current answer. The bar tooltip
shows **Hey Saturn → Grok** when wake mode is enabled. `saturn voiceStatus`
reports mode and state without transcripts. The older local spoken-reply process
is no longer started by Pulse.

Examples: “Hey Saturn, what's the weather?”, “Hey Saturn, open my browser”, or
“Hey Saturn, start a twenty five minute timer.” The saved weather location and
Grok's tools work identically in wake and keyboard-started conversations.

Wake detection pauses while other applications play audible audio. Pause music
or video before saying Hey Saturn. The playback guard only measures output levels
in RAM; it does not save or transcribe playback audio.

The desktop shortcut passes Escape through to the active application as usual:

```lua
o.bind("ESCAPE", "End Pulse conversation", "saturn voiceStop", { non_consuming = true })
o.bind("SHIFT + ESCAPE", "Turn Pulse microphone off", "saturn voiceDisable")
o.bind("CTRL + ALT + P", "Toggle Pulse microphone", "saturn voiceToggle")
```

To install this optional feature on another machine:

```sh
python3 scripts/setup-voice.py
saturn voiceEnable
```

Requires Voxtype with the local `base.en` Whisper model, `parec`, `paplay`, `pactl`, and
an active logind desktop session. Setup downloads Vosk’s small English model
and Piper’s British English Alan voice into `${XDG_DATA_HOME:-~/.local/share}/saturn-voice`
with an isolated Python environment. English is currently supported. Startup
can take a few seconds; failures appear in Connections. Wake recognition depends
on microphone quality, distance and background speech; it is not speaker verification.

Wake recognition, transcription and speech synthesis run locally. Microphone audio
stays in RAM, including the short rolling wake buffer and command recordings.
Commands and replies stay in Pulse’s session memory. Local supported commands run
directly; other requests and the assistant’s existing task/calendar/note/mail context
are sent to Codex using your existing login. The Assistant’s **Include mail previews**
setting applies. Background audio is not sent to Codex. Recognition pauses while
Voxtype is busy and while the screen is locked; Pulse ignores its own spoken replies.

Voice controls use the same bounded actions as the assistant, plus desktop workspace,
media, mute and window-focus controls. They do not provide unrestricted shell execution,
file deletion, or message sending. Speech can be misheard; the overlay shows what Pulse
heard, and only explicitly supported actions are executed. Long answers remain in the
Assistant tab while the spoken version is shortened. A natural-language request can
take longer than a local command while Codex responds.

## HEY mail

The HEY card shows **New for You** from the recent Imbox, preserving HEY’s order. It uses stored
HEY CLI authentication and a websocket watch for live changes, plus refresh on reopening when
stale. Clicking a message opens it in the HEY web app. Listing mail never marks it seen.
Up to 50 recent Imbox entries are loaded; full mail remains available through **Open HEY**.

## Theme

All surfaces, text, accent colors, borders, and fonts bind to Omarchy’s live theme. Cards
use subtle theme tints, and the workspace, command bar, and focus notch have square corners.

## Storage

`${XDG_DATA_HOME:-~/.local/share}/saturn/workspace.json` is the local-first source of truth:
tasks (including due dates and archived items), daily notes, the tagged note library,
timer state, activity, sync metadata and insights. It uses schema 2 and is migrated
automatically from older versions. Copy it to back up or export. Writes are atomic;
notes save after 300 ms and active timers checkpoint about every five seconds.
The shell watches the file for external edits and ignores its own write events, so an
agent can update data without a shell restart. Invalid saved workspace data is preserved
instead of silently overwritten. Credentials stay separately under
`${XDG_CONFIG_HOME:-~/.config}/saturn/` with private permissions.

## Commands

```sh
omarchy-shell saturn toggle
omarchy-shell saturn command
omarchy-shell saturn assistant
omarchy-shell saturn open
omarchy-shell saturn dashboard
omarchy-shell saturn close
omarchy-shell saturn status
omarchy plugin disable k0d3d.saturn
omarchy plugin enable k0d3d.saturn
```

`open` pins the workspace; `toggle` toggles the command bar. `dashboard` opens full screen on the first
display; the workspace's Full screen button uses its own display.

Requires Omarchy's Quickshell shell, Qt Quick Controls, Python 3, and notify-send.
OmaCal, HEY CLI, Codex, and Voxtype provide their respective optional integrations.

### HEY quick actions

Swipe an email left or click its ✓ button to mark it read in HEY. The widget confirms the remote status, then removes it from New for You. **Undo** marks the last email unread again; repeated Undo walks back the last 20 reads in this session. Failed updates show an error and leave the email available. Actions use the email’s own linked account.


## Build and verify

```sh
npm run check
npm test
npm run build:site
omarchy plugin validate .
```

`site/` is a responsive landing page with a limited interactive sample, not a browser port of the plugin. Website builds copy only that directory and the public installer. All visuals use sample data. GitHub Actions checks the source and creates a checksum-bearing source archive for version tags; Vercel hosts the static site.

## License and credits

Publicly viewable source; no open-source license is granted at this time (`UNLICENSED`), following Oma Beats' distribution model. Barlow is used under the included SIL Open Font License. The original workspace concept was inspired by NotchOwl; Saturn is an independent project, not affiliated with Omarchy or its connected services.
## Grok live voice

In **Connections → Grok live**, save an xAI API key and click **Start Grok live**.
This streams microphone audio to xAI while the session is active and plays Grok's
audio as it arrives. It uses separately billed xAI API usage, not Cursor Ultra.
**Hey Saturn** starts this same Grok conversation after a local wake check.
**Ctrl+Alt+P**, `saturn voiceEnable`, and `saturn voiceToggle` now use Grok by
default. There is no fallback to the older local voice. Wake mode returns to local
wake detection after an idle timeout; it does not keep cloud audio running.

The prototype uses `grok-voice-latest`, Ara, PCM16 at 24 kHz, and server-side turn
detection. A temporary PipeWire WebRTC echo-cancellation module lets you speak
over a reply to interrupt. It routes only this session and does not change the
desktop's default microphone or speakers; the module is removed when the session
ends. If echo cancellation is unavailable, the UI says so and the microphone
pauses during replies as a fallback. Use
**Stop reply** to interrupt speech; **Escape / End chat / End Grok / Shift+Escape**
ends the live conversation and turns the microphone off.
Sessions also end after five minutes, one minute idle, desktop locking, or
dictation starting. Commands use Pulse's existing assistant and action validation;
these can take longer than ordinary conversation. The saved Omarchy weather city
(with coordinates rounded to city-level precision) and local time are provided
to both assistants. "What's the weather?" uses that location without another
city question. Grok uses a direct Open-Meteo weather tool and its own web search
for public information, avoiding the Codex handoff. Tasks, calendar, notes and
inbox context are not preloaded into Grok; requested tool results are returned.

**Turn detected → playback** measures from receipt of the server's end-of-speech
event until the first audio is handed to local playback. It excludes the server's
speech-end detection delay and the sound system's final buffering, so it is not a
full mouth-to-ear measurement. Compare several short conversational turns.

The key lives at `$XDG_CONFIG_HOME/saturn/grok-api-key` (normally
`~/.config/saturn/grok-api-key`) with mode `0600`, outside the plugin and
workspace JSON. `XAI_API_KEY` in the process environment takes precedence.
Audio is held in RAM; this prototype does not save recordings or conversation
transcripts to disk. Pulse's normal assistant handles delegated requests.

The existing voice environment already includes WebSockets. On another machine,
run `python3 scripts/setup-grok-voice.py`; `parec`, `paplay`, and `loginctl` are also
required. CLI: `saturn grokStart`, `saturn grokStop`, `saturn grokStatus`.
`pactl` and PipeWire's WebRTC echo-cancellation module enable spoken interruption.
Developer check: `grok_voice.py weather-probe` verifies the weather answer without
opening the microphone or playing audio; it uses a small amount of xAI API usage.
