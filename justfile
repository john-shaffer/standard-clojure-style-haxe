default:
    @just --list

# Build the CLI
build:
    nix build path:.

# Run all checks
check:
    nix flake check path:.

# Run the tests, showing the log
test:
    nix build path:.#test-run --no-link --print-out-paths | xargs -I{} sh -c 'cat {}/log; exit "$(cat {}/status)"'

# Re-sync tests/upstream from the source repository
sync-tests *args:
    scripts/sync-tests.sh {{args}}
