# Railway infrastructure

`railway.ts` manages the DO Card relay service and persistent volume. See
[deployment and cutover instructions](../RAILWAY.md).

Run from the agent-focus directory after installing dependencies:

```sh
npx @railway/cli config plan
npx @railway/cli config apply --yes
```

Review the plan before applying. Preserve the volume. Variables are unmanaged:
set secrets privately in Railway, never in this file.
