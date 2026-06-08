#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

targets=(src tests)

echo "[validate] stylua --check --syntax Luau ${targets[*]}"
stylua --check --syntax Luau "${targets[@]}"

echo "[validate] selene --allow-warnings ${targets[*]}"
selene --allow-warnings "${targets[@]}"

echo "[validate] luau-lsp analyze (full src/tests)"
luau-lsp analyze \
	--platform roblox \
	--sourcemap sourcemap.json \
	--definitions '@roblox=types/roblox-definitions.d.luau' \
	"${targets[@]}"

echo "[validate] all checks passed"
