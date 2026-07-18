# Contributing

## Reporting issues

For bugs, feature requests, or new adapter requests, [pick an issue template](https://github.com/rootlyhq/chat-sdk/issues/new/choose). Each one asks for the information we need to triage the report.

For security vulnerabilities, see [SECURITY.md](./SECURITY.md). Do not file a public issue.

## Development setup

```bash
git clone git@github.com:rootlyhq/chat-sdk.git
cd chat-sdk
mise install        # installs Ruby 4.0.6
bundle install
bundle exec rake spec
```

## Running tests

```bash
# All gems
bundle exec rake spec

# Single gem
bundle exec rspec chat_sdk/spec
bundle exec rspec chat_sdk-slack/spec

# Redis specs (requires local Redis)
REDIS_URL=redis://localhost:6379 bundle exec rspec chat_sdk-state-redis/spec
```

## Linting

```bash
bundle exec rubocop        # check
bundle exec rubocop -A      # autocorrect
```

## Building your own adapter

See [Building Adapters](../docs/contributing/building-adapters.md) for a walkthrough of the `Adapter::Base` interface, testing with shared contract examples, and packaging.

### Gem conventions

**Adapter gems (`chat_sdk-<name>`)** must:

- Live in a top-level directory named `chat_sdk-<name>`
- Require `chat_sdk` and set up a Zeitwerk loader
- Export an `Adapter` class extending `ChatSDK::Adapter::Base`
- Declare capabilities via the `capabilities` class method
- Pass the shared adapter contract specs (`it_behaves_like "a chat_sdk platform adapter"`)

**State gems (`chat_sdk-state-<name>`)** must:

- Export a class extending `ChatSDK::State::Base`
- Pass the shared state contract specs (`it_behaves_like "a chat_sdk state adapter"`)

## Commit messages

We follow [Conventional Commits](https://www.conventionalcommits.org/) — `feat:`, `fix:`, `docs:`, `chore:`, etc., optionally with a scope (e.g., `fix(slack): ...`).

## Releasing

All gems share a single version in `chat_sdk/lib/chat_sdk/version.rb`. To release:

1. Bump `ChatSDK::VERSION`
2. Commit: `chore(release): v0.x.x`
3. Tag: `git tag v0.x.x`
4. Push: `git push origin master --tags`

The release workflow builds all gems, runs specs, and publishes to RubyGems via OIDC.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](../LICENSE).
