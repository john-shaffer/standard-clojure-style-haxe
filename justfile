default:
    @just --list

# Build the CLI
build:
    nix build path:.

# Run all checks
check:
    nix flake check path:.

# Run the CLI end-to-end smoke tests, showing the log
cli-smoke-test:
    nix build path:.#cli-smoke-test-run --no-link --print-out-paths | xargs -I{} sh -c 'cat {}/log; exit "$(cat {}/status)"'

# Run the CLI unit tests, showing the log
cli-test:
    nix build path:.#cli-test-run --no-link --print-out-paths | xargs -I{} sh -c 'cat {}/log; exit "$(cat {}/status)"'

# Fuzz the formatter with mutated test inputs, showing the log
fuzz:
    nix build path:.#fuzz-run --no-link --print-out-paths | xargs -I{} sh -c 'cat {}/log; exit "$(cat {}/status)"'

# Run the tests, showing the log
test:
    nix build path:.#test-run --no-link --print-out-paths | xargs -I{} sh -c 'cat {}/log; exit "$(cat {}/status)"'

# Re-sync tests/upstream from the source repository
sync-tests *args:
    scripts/sync-tests.sh {{args}}
