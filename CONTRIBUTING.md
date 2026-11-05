# Contributing

Thanks for helping.

## Workflow

1. Fork the repo and branch from `dev`.
2. Make the change, with tests where they fit.
3. Open a pull request against `dev`.

`main` only moves when `dev` is merged into it.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org), short and lowercase:

```
feat(cli): add patches rollback command
fix(react-native): keep events when the network is down
docs: explain channels
```

Types: `feat`, `fix`, `docs`, `chore`, `ci`, `refactor`, `test`. Scopes: `cli`, `server`, `console`, `react-native`, `engine`, `examples`.

## Run it

| Part | Commands |
|---|---|
| CLI | `cd cli && dart pub get && dart analyze && dart test packages/ota_cli` |
| Server | `cd server && pnpm install && pnpm exec tsc --noEmit -p tsconfig.build.json` |
| Console | `cd console && pnpm install && pnpm exec tsc --noEmit && pnpm exec eslint src` |
| SDK | `cd react-native && npm install && npm run typecheck` |

The CLI rebuilds itself when a commit touches `cli/`. While editing, delete `cli/bin/cache/ota.stamp` to force a rebuild.

## End-to-end tests

Start the dev server, then:

```bash
scripts/run_react_native_loop.sh android
scripts/run_react_native_loop.sh ios
scripts/run_flutter_android_loop.sh
```

If you change the SDK's update logic, run the React Native loop on both platforms. CI can't run them, so say in your pull request that you did.

## Reporting bugs

Open an issue with your platform, framework version and CLI output. Report security problems privately, as [SECURITY.md](SECURITY.md) describes.
