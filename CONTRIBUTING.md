# Contributing

Thanks for helping improve ServerWatch Community Edition.

## Getting started

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for prerequisites, local setup,
and the build/test commands. In short:

```bash
make check      # vet + Go tests + web build; run this before opening a PR
```

## Pull requests

- Keep each PR focused on one change and describe the problem it solves.
- Add or update tests for behavior changes. Tests must exercise real code paths;
  avoid mocks unless a dependency genuinely cannot be reached in a test.
- Update documentation (`README.md`, `docs/`) and `.env.example` when you add or
  change configuration.
- Match the existing code style; run `gofmt` and `pnpm lint`.

## Database migrations

Add the next numbered migration to both `database/migrations/` and
`server/internal/storage/migrations/` with identical contents. A guard test
fails the build if the copies diverge.

## Commit messages

Use a short imperative subject, for example `feat: add Telegram alerts` or
`fix: keep newest result during retention`. Explain the why in the body when it
is not obvious.

## Security

Do not include secrets, credentials, or private hostnames in issues, pull
requests, or logs. See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By taking
part, you agree to uphold it.
