# Coverage Test Environment

Use the existing devcontainer image plus `compose.coverage.yaml` to run component test suites with stable middleware and native tool dependencies.

## Start Services

```bash
docker compose -f .devcontainer/compose.yaml -f compose.coverage.yaml up -d postgres mysql redis memcached
```

## Bootstrap JavaScript Dependencies

Run this after a fresh checkout or when `yarn.lock` changes:

```bash
docker compose -f .devcontainer/compose.yaml -f compose.coverage.yaml run --rm rails bash -i -c 'yarn install --frozen-lockfile'
```

## Run One Component

```bash
docker compose -f .devcontainer/compose.yaml -f compose.coverage.yaml run --rm rails tools/coverage/component_test actioncable
```

`railties` has isolation tests that mutate global process state and temporary app directories. Running the whole suite in one `bin/test` process can make those tests interfere with each other, so the wrapper runs `railties` one test file at a time when no explicit test paths are passed:

```bash
docker compose -f .devcontainer/compose.yaml -f compose.coverage.yaml run --rm rails tools/coverage/component_test railties
```

Pass normal `bin/test` arguments after the component name:

```bash
docker compose -f .devcontainer/compose.yaml -f compose.coverage.yaml run --rm rails tools/coverage/component_test railties test/test_unit/test_parser_test.rb
```

## Notes

- Branch coverage is enabled by `tools/component_simplecov.rb`.
- SimpleCov is loaded through `RUBYOPT`, so coverage does not add lines to test files that assert source locations.
- Active Record defaults to `ARCONN=sqlite3_mem`.
- Coverage output is written to `coverage/<component>/`.
