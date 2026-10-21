#!/usr/bin/env bash
# ============================================================================
# Atomic Red Team - Simulation Runner for macOS & Linux Terminal
# ============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$DIR/run_simulation.command" "$@"
