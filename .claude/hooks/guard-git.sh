#!/bin/bash
COMMAND=$(jq -r '.tool_input.command' < /dev/stdin)

if echo "$COMMAND" | grep -qE 'git commit|git push'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "ask",
      "permissionDecisionReason": "Git commit/push requires explicit user approval"
    }
  }'
fi
