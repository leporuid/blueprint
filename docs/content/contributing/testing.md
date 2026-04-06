# Testing

Blueprint uses [nix-unit](https://github.com/nix-community/nix-unit) for testing its library functions.

## Running Tests

To run all tests:

```bash
nix flake check
```

This will run:
- Library unit tests (`lib-tests`)
- Package builds
- DevShell builds
- System configuration checks (if applicable)

To run only the library tests:

```bash
nix build .#checks.x86_64-linux.lib-tests
```

Or for a different system:

```bash
nix build .#checks.aarch64-linux.lib-tests
nix build .#checks.x86_64-darwin.lib-tests
```

## Test Structure

Tests are defined in `lib/default.nix` in the `tests` attribute set. Each test follows the nix-unit format:

```nix
tests = {
  testName = {
    expr = <expression-to-test>;
    expected = <expected-result>;
  };
};
```

## Test Coverage

The test suite covers:

### Core Utility Functions

1. **filterPlatforms** - Platform compatibility filtering
   - Empty/no meta.platforms
   - Matching platforms
   - Non-matching platforms
   - Mixed package sets

2. **withPrefix** - Attribute key prefixing
   - Empty sets
   - Single/multiple attributes
   - Empty prefix
   - Complex values

3. **entriesPath** - Path extraction from entries
   - Empty sets
   - Single/multiple entries

4. **optionalPathAttrs** - Conditional path attributes
   - Non-existent paths
   - Existing paths

5. **tryImport** - Safe import with fallback
   - Non-existent paths
   - Existing paths with arguments

6. **importDir** - Directory/file discovery
   - Empty directories
   - Real filesystem operations
   - File precedence rules
   - Type detection

7. **importTomlFilesAt** - TOML file discovery
   - Empty directories
   - Real filesystem operations
   - Filename mapping

8. **mkEachSystem** - Per-system attribute generation
   - Single system
   - Multiple systems
   - eachSystem function behavior

## Test Fixtures

Test fixtures are located in `lib/test-fixtures/`:

- `nix-files/` - For testing `importDir`
- `toml-files/` - For testing `importTomlFilesAt`

See `lib/test-fixtures/README.md` for details.

## Writing New Tests

When adding new functionality to blueprint, add corresponding tests:

1. Add test cases to the `tests` attribute in `lib/default.nix`
2. Follow the nix-unit format: `{ expr = ...; expected = ...; }`
3. Name tests descriptively: `test<FunctionName><Scenario>`
4. Test edge cases: empty inputs, non-existent paths, type mismatches
5. Add fixtures to `lib/test-fixtures/` if testing filesystem operations

### Example Test

```nix
testFilterPlatformsMatchingPlatform = {
  expr = filterPlatforms "x86_64-linux" {
    foo = { meta.platforms = [ "x86_64-linux" "aarch64-linux" ]; };
  };
  expected = {
    foo = { meta.platforms = [ "x86_64-linux" "aarch64-linux" ]; };
  };
};
```

## Continuous Integration

Tests automatically run in CI on:
- Pull requests
- Pushes to main branch
- Release tags

The CI checks all supported systems defined in the flake.

## Test Performance

Library tests are fast (< 1 second) as they don't build derivations. They only evaluate Nix expressions and compare results.

For slower integration tests that build actual packages or systems, use the `checks/` directory instead of lib tests.
