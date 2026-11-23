# Data and security

Saturn runs as an unsandboxed native plugin in the user's Omarchy shell. Review the code before installing.

- Local workspace data stays in `$XDG_DATA_HOME/saturn` (default `~/.local/share/saturn`). It is excluded from source and website builds.
- Tasks are local only. There is no task-service credential, and task data never leaves the local workspace.
- HEY uses your separately installed CLI's existing authentication. Reading the list does not mark mail read. A swipe or checkmark explicitly changes that message's seen state; Undo reverses it.
- Calendar data comes from OmaCal's local feed; this plugin does not change calendar entries.
- The landing page uses sample data, no analytics, no third-party scripts, and no connected accounts. Preview text is kept in the tab only.

Report a vulnerability privately through the repository's GitHub security reporting feature if available. Do not put tokens, credentials, or personal workspace files in public issues.
