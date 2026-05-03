# DO Card Shared Skill

This folder is the shared source of truth for the DO Card skill content.

Use it like this:

1. Edit files here in VS Code.
2. Keep `SKILL.md` as the main entry file.
3. Keep supporting context in `references/`.
4. After making changes, ask Claude or Codex to re-read the updated files.

Suggested layout:

```text
do-card-context-skill/
├── SKILL.md
├── README.md
└── references/
    ├── code-architecture.md
    ├── focus-report.md
    ├── freemium-rules.md
    └── marketing-brand.md
```

Notes:

- Both Claude and Codex can use the same files, but neither tool gets live updates automatically.
- If one assistant changes the skill, the other should re-open the updated files before continuing.
- Keep this folder as the canonical copy so the app context stays aligned across tools.
