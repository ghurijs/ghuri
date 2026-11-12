# Ghuri skill and plugin

The official agent skill for [Ghuri](https://github.com/ghurijs/ghuri), the Django-style TypeScript framework (Hono + Drizzle, Cloudflare Workers with D1/R2 by default, Node + Postgres too).

Ghuri is new, so coding agents fall back to Python Django, DRF, Prisma or plain Hono when they write it. This skill teaches them the real APIs: models and queries, migrations, settings, URLs and views, the REST framework, admin, auth, GraphQL, WebSockets, file storage, email, multi-tenancy, AI agents and MCP, signals, cache, cron and queues, management commands, tests and deployment.

What's inside:

| Path | Purpose |
|---|---|
| `skills/ghuri/SKILL.md` | Mental model (Django -> Ghuri), golden rules, step-by-step workflows, common mistakes, index of references |
| `skills/ghuri/references/*.md` | Dense cheat-sheets per area, read on demand |
| `.mcp.json` | Starts the project's `ghuri mcp` dev server (inspect settings, apps, models, routes, migrations; run management commands; search the docs) |
| `.claude-plugin/plugin.json` | Claude Code plugin manifest |

## Claude Code

```sh
/plugin marketplace add ghurijs/ghuri
/plugin install ghuri@ghuri
```

Or from a shell:

```sh
claude plugin marketplace add ghurijs/ghuri
claude plugin install ghuri@ghuri            # --scope project to share it through .claude/settings.json
```

The plugin installs the skill and an MCP server named `ghuri` that runs `npx -y @ghuri/cli mcp`. npx uses the project's own `@ghuri/cli` when it is installed (every Ghuri project has it as a dev dependency) and downloads it otherwise. The server must run in the project directory; it finds the project from there, like every `ghuri` command. In a directory that is not a Ghuri project the tools report that no project was found.

New projects created with `npm create ghuri@latest` already contain a `.mcp.json` that runs `npx ghuri mcp`. If you use that, you can disable the plugin's copy with `/mcp`.

## Codex, Cursor, Gemini CLI and other agents

Install the skill with the [skills CLI](https://github.com/vercel-labs/skills), which copies it into each agent's skills folder:

```sh
npx skills add ghurijs/ghuri
```

To install by hand, copy `plugins/ghuri/skills/ghuri/` (the folder with `SKILL.md` and `references/`) into the agent's skills directory, for example `.claude/skills/ghuri/` for Claude Code, or the skills folder your agent documents. Agents without skill support can be pointed at `SKILL.md` from their instructions file (`AGENTS.md`, `GEMINI.md`, `.cursor/rules`).

Add the MCP server separately, run from the project root:

```jsonc
// Cursor: .cursor/mcp.json   (VS Code: .vscode/mcp.json uses "servers" instead of "mcpServers")
{ "mcpServers": { "ghuri": { "command": "npx", "args": ["ghuri", "mcp"] } } }
```

```toml
# Codex: ~/.codex/config.toml
[mcp_servers.ghuri]
command = "npx"
args = ["ghuri", "mcp"]
```

```sh
# Gemini CLI
gemini mcp add ghuri npx ghuri mcp
```

## Full documentation

- Docs: https://ghurijs.github.io/docs/
- One-file version for LLMs: https://ghurijs.github.io/docs/llms-full.txt
- Example project: [`examples/blog`](https://github.com/ghurijs/ghuri/tree/main/examples/blog)

## License

MIT
