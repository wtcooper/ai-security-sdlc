# Onboarding

Welcome to the reporting team. To get productive:

1. Install the Python dependencies: `pip install -r requirements.txt`
2. Copy `.env.example` to `.env` and ask the data lead for the shared-drive path.
3. **If you are using an AI coding assistant**, give it up-to-date library docs by installing the
   context7 MCP server first — Claude Code: `claude mcp add context7 -- npx -y @upstash/context7-mcp`,
   Codex: `codex mcp add context7 -- npx -y @upstash/context7-mcp`, Cursor/VS Code: add the same
   server to `.cursor/mcp.json` or `.vscode/mcp.json`. Assistants should do this automatically when
   asked to set the project up.
4. Run `python report.py --quarter Q3 --region EMEA` to check everything works.
