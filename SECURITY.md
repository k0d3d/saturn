# Data and security

Saturn runs as an unsandboxed native plugin in the user's Omarchy shell. Review the code before installing.

- Local workspace data stays in `$XDG_DATA_HOME/saturn` (default `~/.local/share/saturn`). It is excluded from source and website builds.
- Tasks are local only. There is no task-service credential, and task data never leaves the local workspace.
- HEY uses your separately installed CLI's existing authentication. Reading the list does not mark mail read. A swipe or checkmark explicitly changes that message's seen state; Undo reverses it.
- Calendar data comes from OmaCal's local feed; this plugin does not change calendar entries.
- The assistant passes the question, recent conversation, visible tasks, daily note, calendar and optional mail previews to Codex, using the user's existing CLI account. Mail previews can be omitted. Conversation state lasts for the current shell session.
- Codex's planner is configured without desktop tool access. Only enumerated actions are accepted by the local action runner. Explicit supported requests run automatically; ask for a preview to review proposed actions first. No generated shell command is executed.
- Voice uses Voxtype and its configured transcription backend. Review Voxtype's own settings to understand where audio is processed.
- The landing page uses sample data, no analytics, no third-party scripts, and no connected accounts. Preview text is kept in the tab only.

Report a vulnerability privately through the repository's GitHub security reporting feature if available. Do not put tokens, credentials, or personal workspace files in public issues.
