# App Traffic Inspector

App Traffic Inspector is a native macOS network debugging tool for iOS development. It allows you to inspect HTTP/HTTPS network traffic from your iOS apps in real-time without proxy settings or certificates.

## Features
- Real-time network traffic monitoring from iOS apps
- Request/response inspection with syntax highlighting
- JSON formatting and visualization
- Media previews for what is sent and received: images, video/audio, PDF, multipart uploads (per-part previews), URL-encoded forms, base64 media embedded in JSON, and a hex view for other binary bodies
- Binary-safe cURL export that includes the request body (bodies that are not text are written to files and referenced with `@file`)
- One-click Replay of any captured request with a side-by-side comparison against the original
- Native macOS 26 Liquid Glass interface
- Device and project separation
- Bounded per-device retention: 1,000 transactions and 250 MiB of decoded request/response bodies
- No proxy configuration or certificate installation required
- Bonjour-based automatic discovery, advertised on the main interface, any USB Personal Hotspot interface (`172.20.10.x`) and peer-to-peer Wi-Fi (AWDL, toggle in Settings), so iPhones on guest networks that block mDNS can still connect
- **MCP (Model Context Protocol) server** — expose redacted transaction data and tools to local MCP clients

## Installation
1. Clone the repository
2. Open AppTrafficInspector.xcodeproj in Xcode
3. Build and run (⌘R)
4. Allow network connections when prompted

## Usage
Run an iOS app using the AppTrafficKit framework (coming soon) on the same network as your Mac running App Traffic Inspector. Network requests will automatically appear in the inspector.

### Inspect uploads and downloads
Select a transaction to open its details. Media requests (multipart, image, video, audio) are marked with a paperclip in the list and open on **Req Body**; media responses open on **Resp Body**.

- **Multipart uploads** list each part. Text parts are shown inline, media parts are previewed, and any part can be saved.
- **Form bodies** (`application/x-www-form-urlencoded`) are shown as a field table.
- **JSON with embedded base64 media** shows previews above the formatted JSON.
- **Other binary bodies** are shown as a hex dump with a Save button.
- If the iOS framework truncated a body before sending it, or a body is smaller than its `Content-Length`, the body tab shows a notice. Previews of truncated bodies are incomplete, cURL output starts with a `# Warning` line, and Replay asks for confirmation before sending the incomplete body.

### Copy as cURL
**cURL** in the detail bar copies a command that includes the method, headers (including `Cookie`), and body:

- Text bodies are inlined with `--data-raw`.
- Multipart bodies are rebuilt with `-F`/`--form-string`, and `Content-Type`/`Content-Length` are left for curl to set.
- Binary bodies and file parts are written to `<export folder>/transaction-<id>/` and referenced with `--data-binary @file` or `-F name=@file`.

The export folder defaults to `~/Downloads/AppTrafficInspector`. Change it, reveal it, or clear exported files under **Settings → Body Export**. MCP `get_packet_curl` output stays text-only and adds a note when a binary body is omitted.

### Replay
**Replay** (⌘R) sends the captured request again from this Mac and adds the result as a new transaction marked **Replay**, which opens on a **Compare** tab showing status, duration, size, header differences, and both response bodies side by side.

- The request is sent with its captured headers, including `Cookie` and `Authorization`. Cookies are not stored, nothing is cached, and redirects are not followed.
- Methods other than GET, HEAD, OPTIONS, and TRACE ask for confirmation once per launch, because they can change server data.
- Replaying a replay sends the original request again.
- Only `http` and `https` URLs can be replayed.

### iOS framework compatibility
AppTrafficInspectorKit caps each captured body (8 MiB by default) and marks truncated bodies, which this app reports. Requests made with background `URLSession`s are not captured.

---

## MCP Server — Add to your AI IDE

The app includes a loopback-only MCP server (Streamable HTTP on port **43436**) so Cursor, Claude Code, and other local clients can list projects/devices, inspect transactions, search traffic, and get shell-safe cURL commands. **The app must be running with “Enable MCP Server” turned on in Settings** before any client can connect.

### Add to Cursor

**Option 1: One-click install (recommended)**  
Click the link below. Cursor will prompt to add the server; approve to install.

**[Add App Traffic Inspector to Cursor](cursor://anysphere.cursor-deeplink/mcp/install?name=app-traffic-inspector&config=eyJ1cmwiOiJodHRwOi8vMTI3LjAuMC4xOjQzNDM2L21jcCJ9)**

**Option 2: Manual config**  
Add the server to Cursor’s MCP config:

- **Project-level:** `.cursor/mcp.json` in your repo (this project already includes it).
- **Global (all projects):** `~/.cursor/mcp.json` on macOS/Linux, or `%USERPROFILE%\.cursor\mcp.json` on Windows.

```json
{
  "mcpServers": {
    "app-traffic-inspector": {
      "url": "http://127.0.0.1:43436/mcp"
    }
  }
}
```

Restart Cursor (or reload the window) after changing the config.

### Add to Claude Code

In your Claude Code MCP config (e.g. `~/.config/claude/claude_desktop_config.json` on macOS or the path shown in Claude Code settings), add:

```json
{
  "mcpServers": {
    "app-traffic-inspector": {
      "url": "http://127.0.0.1:43436/mcp"
    }
  }
}
```

Restart Claude Code after editing the config.

### Add to Claude Desktop

1. Open **Claude Desktop → Settings → Developer → Edit Config** (or edit the config file directly).
2. **Config path:**  
   - **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`  
   - **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
3. Add the server under `mcpServers`. If your Claude Desktop build supports a `url` field for MCP, use:

```json
{
  "mcpServers": {
    "app-traffic-inspector": {
      "url": "http://127.0.0.1:43436/mcp"
    }
  }
}
```

If your version only supports `command`-based MCP, you can run a small bridge that forwards to the app (e.g. a script that proxies stdio to `http://127.0.0.1:43436/mcp`), or use a community proxy tool. Restart Claude Desktop after saving.

### Add to other clients (Windsurf, Codex, etc.)

Any MCP client that supports **Streamable HTTP** can connect to:

- **URL:** `http://127.0.0.1:43436/mcp`
- **Method:** POST for JSON-RPC; GET for SSE (optional, for live traffic events).

Add a server entry with `"url": "http://127.0.0.1:43436/mcp"` in that client’s MCP configuration. Refer to the client’s docs for the exact config file location and schema.

---

## System Requirements
- macOS 26.0 or later
- Xcode 26.0 or later (for building)

## Build and test

```bash
# Build
xcodebuild -project AppTrafficInspector.xcodeproj \
  -scheme AppTrafficInspector \
  -destination 'platform=macOS' build

# Run the 39 unit tests without requiring a local development certificate
xcodebuild -project AppTrafficInspector.xcodeproj \
  -scheme AppTrafficInspector \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:AppTrafficInspectorTests test

# Build, launch, and run the 14 MCP acceptance checks
./Scripts/run_acceptance_tests.sh

# Run the deterministic media, multipart cURL, and replay UI journeys (requires signing)
xcodebuild -project AppTrafficInspector.xcodeproj \
  -scheme AppTrafficInspector \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:AppTrafficInspectorUITests/MediaTransactionJourneyTests test
```

The first UI-test run can require approval under **System Settings → Privacy & Security → Automation**. A timeout while enabling automation mode indicates missing host permission rather than an app assertion failure.

## License
Apache 2.0

## Attribution
Based on the original Bagel project by Yagiz Lab (https://github.com/yagiz/Bagel)
Licensed under Apache 2.0