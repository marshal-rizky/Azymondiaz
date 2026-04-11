#!/bin/bash
# Copies the authoritative server prompts into the iOS app bundle's
# Resources/prompts/ directory. Runs as an Xcode build phase so every
# iPA ships the latest snapshot (used in school fallback mode).
set -euo pipefail

SERVER_PROMPTS="${SRCROOT}/../server/prompts"
DEST="${SRCROOT}/NotesApp/Resources/prompts"

rm -rf "$DEST"
mkdir -p "$DEST"

if [ -d "$SERVER_PROMPTS" ]; then
  cp -R "$SERVER_PROMPTS/." "$DEST/"
  echo "Copied prompts from $SERVER_PROMPTS"
else
  # First build or server monorepo not checked out: write minimal stubs so
  # BakedPromptsTests still passes and the app does not crash in offline mode.
  echo "WARNING: $SERVER_PROMPTS not found — writing stub prompts"
  cat > "$DEST/transform_cleanup.txt" <<'EOF'
Clean up this handwriting into neat text. Preserve meaning exactly.
EOF
  cat > "$DEST/transform_typed_text.txt" <<'EOF'
Convert this handwriting into plain typed text, nothing else.
EOF
  cat > "$DEST/transform_math.txt" <<'EOF'
You are a careful math tutor. Read the handwritten problem, solve it,
and explain each step clearly in the user's language.
EOF
  cat > "$DEST/transform_physics.txt" <<'EOF'
You are a careful physics tutor. Interpret the handwritten problem or
diagram, identify the relevant concept, and walk through the solution.
EOF
  cat > "$DEST/transform_chemistry.txt" <<'EOF'
You are a careful chemistry tutor. Interpret the handwritten question
and answer clearly. Note any structural-formula ambiguities.
EOF
  cat > "$DEST/transform_explain.txt" <<'EOF'
Explain the content of this handwritten note at a high-school level
in the user's language.
EOF
  cat > "$DEST/transform_list.txt" <<'EOF'
Convert the content of this note into a clear bulleted list.
EOF
  cat > "$DEST/chat_system.txt" <<'EOF'
You are a helpful study assistant. Match the user's language.
Indonesian, English, or mixed is fine.
EOF
fi

echo "Prompts baked:"
ls "$DEST"
