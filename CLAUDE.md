# CLAUDE.md

Project guidance for Claude Code lives in **[AGENTS.md](AGENTS.md)** — single source of truth
for both Claude Code and other agents.

@AGENTS.md

**Most important:** do not reintroduce Claude subscription-OAuth / Keychain-token reuse to
read Claude usage. It's prohibited and server-side-blocked by Anthropic. Claude usage comes
only from driving the official `claude` CLI's `/usage` panel. See AGENTS.md for the full
rationale and architecture.
