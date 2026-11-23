# Choose your connections

Open **Connections** in Saturn (or run `saturn connections`). Selections are saved and shared by the compact and full-screen workspaces. Switching providers preserves your local tasks, notes and existing logins. One mail provider and one calendar source are displayed at a time.

| Panel | Choices | Setup |
| --- | --- | --- |
| Tasks | Local only | Stored on this computer; no account needed |
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

## CalDAV: cPanel calendars

Choose **CalDAV (cPanel)** under Calendar, then **CalDAV (cPanel)** under Account setup. Enter the HTTPS CalDAV endpoint from your cPanel account (often `https://mail.example.com/caldav/`), your calendar username and an app password. The connection is verified before the credentials are saved in `~/.config/saturn/connections/caldav.json` (mode 600). Only HTTPS endpoints are accepted.

Saturn reads the next eight days of events and writes new or locally edited
events back with CalDAV `PUT`. Archiving an event only hides it locally; remote
deletion is intentionally disabled until safe ownership and conflict checks
are available. Calendar events are not mirrored into the Markdown vault.
Server responses are size-bounded and titles are rendered as plain text.

Google Calendar two-way writes require reconnecting once after upgrading to 0.8 so the app receives the `calendar.events` scope instead of the older read-only scope.

## What syncs

- **IMAP:** up to 20 unread message headers, refreshed every two minutes, with verified read/undo changes.
- **Gmail / Outlook:** up to 20 unread inbox messages; refresh every two minutes and on reopening when stale. Click a message to open it in the provider. Mark read and Undo are verified with the remote service before the list changes. This is an inbox preview, not a full email client.
- **Google Calendar:** one selected calendar, today plus seven days, with recurring occurrences and all-day/multi-day events. Reconnect once to grant write access; local events are pushed back. Clicking an event opens the full Google Calendar day.
- **CalDAV:** the next eight days from your cPanel calendar, with local events written back. Conflicts stay local and are listed in the workspace.
- **HEY / OmaCal:** existing behavior is preserved. HEY uses its CLI and live watch; OmaCal supplies its own published calendar feed.
- **Local tasks:** stay on your machine. Due dates, completion and archiving are stored in the local workspace.

OAuth tokens and client settings stay in `${XDG_CONFIG_HOME:-~/.config}/saturn/connections/` with private directory and file permissions (700/600). They are not included in workspace exports, process arguments, the website or releases. **Disconnect** deletes the selected local connection file; revoke the app in Google/Microsoft account settings to remove server-side consent. Errors preserve your existing connection rather than replacing it with a failed sign-in.
