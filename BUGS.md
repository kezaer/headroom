# Known limitations

- Copilot readings can lag activity in other clients until the CLI records usage again.
- OpenCode can report a locked database if two clients start together. The next scheduled read can recover.
- Antigravity's signed-out browser guard depends on the CLI finding the browser opener through its process environment.
- Offscreen renders cannot verify native menu bar window sizing or system glass. Check both appearances in the live popover.

Report a reproducible problem in [Pacemark issues](https://github.com/kezaer/pacemark/issues).
