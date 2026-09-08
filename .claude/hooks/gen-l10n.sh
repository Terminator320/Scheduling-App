#!/bin/bash
# PostToolUse hook for Edit|Write: after an ARB file changes, regenerate the
# l10n outputs and surface failures / EN-FR drift back to the model.
# Silent (and fast: exits before flutter starts) for all non-ARB edits.

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

case "$FILE_PATH" in
  *lib[/\\]l10n[/\\]app_en.arb|*lib[/\\]l10n[/\\]app_fr.arb) ;;
  *) exit 0 ;;
esac

OUT=$(flutter gen-l10n 2>&1)
if [ $? -ne 0 ]; then
  echo "flutter gen-l10n FAILED after ARB edit (bare key missing @key metadata? EN/FR out of lockstep?):" >&2
  echo "$OUT" | tail -30 >&2
  exit 2
fi

# Surface untranslated-message drift (EN keys with no FR translation).
UNTRANS="lib/l10n/.gen/untranslated.json"
if [ -f "$UNTRANS" ] && grep -q '"' "$UNTRANS"; then
  CONTENT=$(tr -d '\r' < "$UNTRANS" | head -c 2000)
  jq -n --arg ctx "flutter gen-l10n succeeded, but EN/FR ARB drift exists in $UNTRANS: $CONTENT" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
fi

exit 0
