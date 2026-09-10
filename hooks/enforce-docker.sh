#!/bin/bash
#
# Hook to enforce Docker usage for all Python, pytest, npm, and npx commands
# Per CLAUDE.md: "Always use Docker for running the application, tests, and any development tasks"
#

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# If we can't parse the command, allow it
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Allow commands that already use docker-compose or docker exec
if echo "$COMMAND" | grep -qE '(docker-compose|docker exec|docker compose)'; then
    exit 0
fi

# Block direct python/python3/.venv/bin/python execution
if echo "$COMMAND" | grep -qE '^(python|python3|\.venv/bin/python|pip|pip3)'; then
    echo "BLOCKED: Direct Python execution not allowed." >&2
    echo "Use: docker-compose exec -T backend python <args>" >&2
    echo "See: .claude/CLAUDE.md for Docker usage rules" >&2
    exit 2
fi

# Block direct pytest execution
if echo "$COMMAND" | grep -qE '^(pytest|\.venv/bin/pytest)'; then
    echo "BLOCKED: Direct pytest execution not allowed." >&2
    echo "Use: docker-compose exec -T backend pytest <args>" >&2
    echo "See: .claude/CLAUDE.md for Docker usage rules" >&2
    exit 2
fi

# Block direct npm run dev / npx playwright
if echo "$COMMAND" | grep -qE '^(npm run dev|npx playwright test)'; then
    echo "BLOCKED: Direct npm/npx execution not allowed." >&2
    echo "Use: docker-compose exec -T frontend npx <args>" >&2
    echo "See: .claude/CLAUDE.md for Docker usage rules" >&2
    exit 2
fi

# Allow other commands
exit 0
