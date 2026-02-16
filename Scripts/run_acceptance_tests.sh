#!/usr/bin/env bash
#
# Build App Traffic Inspector, launch it, wait for MCP server, run mcp_acceptance_test.swift, then quit app.
# Usage: ./Scripts/run_acceptance_tests.sh
#

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="${SCHEME:-AppTrafficInspector}"
PRODUCT_NAME="App Traffic Inspector"
MCP_URL="http://127.0.0.1:43436/mcp"

cd "$PROJECT_DIR"

echo "Building $SCHEME..."
xcodebuild -scheme "$SCHEME" -configuration Debug -destination 'platform=macOS' build -quiet

BUILT="$(xcodebuild -scheme "$SCHEME" -configuration Debug -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk -F= '/BUILT_PRODUCTS_DIR/ { gsub(/^[ \t]+/,"",$2); print $2; exit }')"
if [[ -n "$BUILT" && -d "$BUILT" ]]; then
  APP_PATH="$BUILT/$PRODUCT_NAME.app"
else
  APP_PATH=""
  for d in "$HOME/Library/Developer/Xcode/DerivedData/AppTrafficInspector-"*/Build/Products/Debug; do
    if [[ -d "$d/$PRODUCT_NAME.app" ]]; then APP_PATH="$d/$PRODUCT_NAME.app"; break; fi
  done
fi
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Could not find built app. Try building from Xcode first."
  exit 1
fi

# Ensure MCP server will start when app launches (UserDefaults mcpServerEnabled)
defaults write nz.ging.AppTrafficInspector mcpServerEnabled -bool true 2>/dev/null || true

# Quit any running instance so a fresh launch picks up defaults and starts MCP
osascript -e "quit app \"$PRODUCT_NAME\"" 2>/dev/null || true
sleep 1

echo "Launching app..."
open "$APP_PATH"
APP_PID=""
for i in {1..30}; do
  APP_PID=$(pgrep -f "$PRODUCT_NAME.app" 2>/dev/null | head -1)
  [[ -n "$APP_PID" ]] && break
  sleep 0.5
done
if [[ -z "$APP_PID" ]]; then
  echo "App did not start in time."
  exit 1
fi

echo "Waiting for MCP server at $MCP_URL (up to 30s)..."
for i in {1..30}; do
  if curl -s -o /dev/null -w "%{http_code}" --max-time 2 -X POST "$MCP_URL" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' 2>/dev/null | grep -q 200; then
    echo "MCP server ready."
    break
  fi
  sleep 1
done
sleep 1

echo "Running acceptance test script..."
if swift "$SCRIPT_DIR/mcp_acceptance_test.swift"; then
  echo "Acceptance tests passed."
else
  echo "Acceptance tests failed."
  kill "$APP_PID" 2>/dev/null || true
  exit 1
fi

echo "Stopping app..."
osascript -e "quit app \"$PRODUCT_NAME\"" 2>/dev/null || kill "$APP_PID" 2>/dev/null || true
exit 0
