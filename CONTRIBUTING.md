# Development

Saturn is QML/JavaScript plus Python standard-library helpers. The landing page is static HTML, CSS and JavaScript.

Run `npm run check`, `npm test`, and `npm run build:site`. Node is a developer/website dependency, not an installed plugin dependency. On Omarchy, also run `omarchy plugin validate .` and parse QML with the installed `qmlformat` tool. Use a temporary HOME and XDG directories for integration tests; never use real Todoist or mail credentials in fixtures.

Changes to the installed plugin can reload the desktop shell. Develop in a separate checkout, back up the installed copy, and preserve the user's workspace and credentials outside the checkout. The current plugin identifier is `k0d3d.saturn`; the previous `kosta.omaowl` id and the `omapulse`/`omaowl` commands are deprecated aliases kept for one release.

Do not include personal tasks, calendar entries, mail, logs, tokens, or local configuration in commits or screenshots. Public screenshots and website previews must use sample data.

The source is publicly viewable but not currently offered under an open-source license. Third-party assets retain their own licenses; Barlow includes its SIL Open Font License in `site/assets/`.
