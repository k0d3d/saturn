# Choose your connections

Open **Connections** in Saturn (or run `saturn connections`). Selections are saved and shared by the compact and full-screen workspaces. Switching providers preserves your local tasks, notes and existing logins. One mail provider and one calendar source are displayed at a time.

| Panel | Choices | Setup |
| --- | --- | --- |
| Tasks | Local, Todoist | Local needs no account; Todoist uses your API key |
| Mail | HEY, Gmail, Outlook, IMAP, Off | HEY CLI login, or provider OAuth below |
| Calendar | OmaCal, Google Calendar, Off | Existing OmaCal feed, or Google OAuth below |

Gmail, Outlook and direct Google Calendar are **beta integrations with user-supplied OAuth app credentials**. Saturn does not ship a shared Google/Microsoft OAuth registration. These adapters have automated protocol and UI checks; live account sign-in still needs verification with your own registration. They are not zero-setup sign-in buttons.

## Google: Gmail or Calendar

1. In [Google Cloud Console](https://console.cloud.google.com/), create or select a project. Enable **Gmail API** for Gmail, or **Google Calendar API** for Calendar.
2. Configure the OAuth consent screen. If the application is in testing, add the Google account you will connect as a test user.
3. Create an OAuth client of type **Desktop app**. Copy its client ID and client secret into the matching account setup in Saturn.
4. For Calendar, leave Calendar ID blank for your primary calendar. To use another calendar you can access, paste its ID from Google Calendar’s **Settings → Integrate calendar**.
5. Choose **Connect in browser**, sign in, approve access, and return to Saturn. Choose Gmail or Google Calendar as the displayed source.

Gmail and Calendar have separate sign-ins and tokens so each requests only its own permissions. Gmail requests `gmail.modify` for inbox previews and marking messages read/unread; Calendar requests `calendar.readonly` for calendar metadata and events. No sending or calendar editing controls are provided. Google may limit unverified/testing apps or require verification before broader distribution; follow the requirements shown in your Cloud project.

The sign-in uses a temporary local loopback callback with PKCE and a random state value, following [Google’s desktop OAuth flow](https://developers.google.com/identity/protocols/oauth2/native-app).

## Microsoft Outlook

1. Create an application in [Microsoft Entra app registrations](https://entra.microsoft.com/).
2. Select account types that include the account you want to connect. To support personal Outlook accounts and work/school accounts, choose **accounts in any organizational directory and personal Microsoft accounts**.
3. Under Authentication, enable **Allow public client flows**. Add Microsoft Graph delegated `Mail.ReadWrite` permission if your registration requires explicit permission configuration. No client secret is needed.
4. Paste the application/client ID into Saturn’s Outlook setup and choose **Connect in browser**.
5. Enter the device code displayed in Saturn at Microsoft’s sign-in page, approve access, and return. Work accounts may require administrator consent or may disallow device sign-in.

Outlook uses [Microsoft’s device authorization flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code) and delegated mail access, not application-wide mailbox permissions.

## IMAP: other mail providers

Choose **IMAP**, then enter your provider’s IMAP hostname, TLS port (normally 993), username, and app password. Choose a mailbox (default `INBOX`). This supports providers that allow password/app-password IMAP authentication over TLS; it does not bypass provider restrictions. OAuth-only accounts should use the direct Gmail/Outlook connections. STARTTLS on port 143 and insecure connections are not supported.

The optional HTTPS webmail URL enables **Open webmail** and message clicks to open your full inbox. IMAP itself does not provide browser message URLs. Without this URL, headers and read/undo still work in Saturn.

Connecting verifies login and mailbox access before saving. The app password uses the same private local storage as OAuth tokens. Listing uses `BODY.PEEK` for sender/subject/date headers and does not mark messages read or download message bodies. Read/Undo uses UIDs and verifies UIDVALIDITY to prevent changes to the wrong message if a mailbox is recreated. IMAP is also beta until verified against your provider.

## What syncs

- **IMAP:** up to 20 unread message headers, refreshed every two minutes, with verified read/undo changes.
- **Gmail / Outlook:** up to 20 unread inbox messages; refresh every two minutes and on reopening when stale. Click a message to open it in the provider. Mark read and Undo are verified with the remote service before the list changes. This is an inbox preview, not a full email client.
- **Google Calendar:** one selected calendar, today plus seven days, with recurring occurrences and all-day/multi-day events. Dates and clock labels use that calendar’s timezone. Clicking an event opens the full Google Calendar day. No OmaCal install is required for this source.
- **HEY / OmaCal:** existing behavior is preserved. HEY uses its CLI and live watch; OmaCal supplies its own published calendar feed.
- **Local tasks:** stay on your machine and are never uploaded when switching to Todoist.

OAuth tokens and client settings stay in `${XDG_CONFIG_HOME:-~/.config}/saturn/connections/` with private directory and file permissions (700/600). They are not included in workspace exports, process arguments, the website or releases. **Disconnect** deletes the selected local connection file; revoke the app in Google/Microsoft account settings to remove server-side consent. Errors preserve your existing connection rather than replacing it with a failed sign-in.


## Messages: Blip and Beeper (including Slack)

### Blip texts

With Blip installed and its Mac bridge working, install the optional preview
extension from the Saturn directory:

```sh
python3 scripts/install-blip-preview.py
```

This patches only known Blip IPC/config anchors and backs up `BarWidget.qml`
under `$XDG_STATE_HOME/omaowl-backups` (default `~/.local/state/omaowl-backups`).
Unsupported versions are rejected before any change. The bridge source and tests
are in `scripts/blip-preview/`; regenerate its module with
`bun build scripts/blip-preview/pulse-preview.ts --target browser --format esm --outfile scripts/blip-preview/PulsePreview.mjs`.

Add `pulse_previews=on` to `~/.config/blip/bridge.conf`, then run
`omarchy restart shell`. This separate opt-in permits local processes to read
unread names, counts, timestamps and snippets via `previews` IPC. It does not
enable `automation` or sending. Per-conversation read actions have their own opt-in. Keep `automation=off` if
you do not need those capabilities. Set `pulse_previews=off` to stop exporting.
Blip upgrades may replace the local extension; reinstall it if Pulse reports
that the bridge is missing. The Mac must be awake and reachable. Offline previews
are labeled as potentially out of date.

### Beeper and Slack

1. In Beeper’s settings, enable **Desktop API**, using its default port 23373,
   and create/copy an access token.
2. In Pulse → **Connections**, paste the token into **Beeper Desktop API token**
   and click **Connect Beeper**. Keep Beeper running.
3. Connect Slack in Beeper to include those accounts. Pulse’s **Slack** filter
   opens conversations in Beeper, not a separate Slack installation.

The token is validated before saving in `${XDG_CONFIG_HOME:-~/.config}/saturn/beeper.json`
with mode 600. It travels through stdin, never command arguments. **Disconnect
Beeper** removes that local credential. API requests use only `127.0.0.1:23373`,
without proxies or redirects. Polling only lists chats; a click calls `/v1/focus`
with the selected chat ID. The ✓ button calls `/v1/chats/{chatID}/read` through the displayed message ID; no send endpoint is used.

Pulse scans up to 2,000 recent Beeper chats per refresh, follows pagination,
and reports when more remain. Rows show the latest message preview for each
unread conversation, which may be an outgoing message; they are not a list of
individual unread messages. Muted and archived unread chats are included.
The **All** view keeps Blip and Beeper separate, so a conversation connected
through both may appear twice.

API references: [Beeper Desktop API](https://developers.beeper.com/desktop-api/),
[list chats](https://developers.beeper.com/desktop-api-reference/resources/chats/methods/list/).


### Mark conversations read

Install/update the Blip bridge with `python3 scripts/install-blip-preview.py`,
add `pulse_mark_read=on` to `~/.config/blip/bridge.conf`, and restart the shell.
This separate option permits local processes to request a read mark for one known
conversation at its exact current preview timestamp. Sending stays disabled.
Pulse waits for Blip’s read watermark to be saved before removing the preview.
A newer preview causes the action to fail with a refresh prompt, rather than
marking a message you have not seen. No real conversations are marked during tests.

Blip’s existing `push_read=all` (default) clears the local Blip/Pulse unread state;
it only pushes to Apple on Blip’s mark-all gesture. With `push_read=thread`, Blip
also requests sync through Messages on the Mac. Pulse’s confirmation covers the
local read ledger, not delivery of an Apple read receipt. Offline or unconfirmed
requests show an error. This feature does not change `push_read`.

Beeper uses its [mark-read API](https://developers.beeper.com/desktop-api-reference/php/resources/chats/methods/mark_read)
with the displayed message ID so later arrivals remain unread. Missing message
IDs require opening the conversation in Beeper. There is no bulk-read action.
