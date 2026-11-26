# Pacemark privacy

Usage checks run on your Mac. Provider requests go directly to the provider. Pacemark has no analytics service. Sign-in takes place in the official client. For Claude, Pacemark reads the CLI's usage report and account metadata. It never reads Claude subscription credentials.

Copilot session logs can contain prompts and tool output. Pacemark decodes usage records and keeps no conversation text. Optional API spend reporting uses separate reporting keys stored in the macOS Keychain. Opting into subscription warm-up lets the official client send a short message that spends quota.

Account labels, readings and preferences stay on the Mac. Local development captures can include account names and usage. Review them before sharing. See [how each provider is read](docs/how-it-works.md).
