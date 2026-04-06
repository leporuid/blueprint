# Test Fixtures

This directory contains test fixtures used by the nix-unit tests in `lib/default.nix`.

## Structure

- `nix-files/` - Contains `.nix` files and directories for testing `importDir` function
  - `foo.nix` - Test file
  - `bar.nix` - Test file
  - `subdir/` - Test directory with `default.nix`
  - `ignored.txt` - Non-Nix file that should be ignored

- `toml-files/` - Contains `.toml` files for testing `importTomlFilesAt` function
  - `devshell.toml` - Test TOML file
  - `other.toml` - Another test TOML file

## Purpose

These fixtures allow testing of real filesystem operations without depending on external files. The tests verify:

1. **importDir** correctly identifies and loads `.nix` files
2. **importDir** handles directories with `default.nix`
3. **importDir** ignores non-Nix files
4. **importDir** applies precedence rules (files over directories)
5. **importTomlFilesAt** correctly identifies and loads `.toml` files
6. **importTomlFilesAt** properly maps filenames to attribute names

## Running Tests

To run all tests including these filesystem-based tests:

```bash
nix flake check
```

To run only the lib tests:

```bash
nix build .#checks.x86_64-linux.lib-tests
```

Or for a different system:

```bash
nix build .#checks.aarch64-linux.lib-tests
```
