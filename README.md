# App Traffic Inspector

App Traffic Inspector is a native macOS network debugging tool for iOS development. It allows you to inspect HTTP/HTTPS network traffic from your iOS apps in real-time without proxy settings or certificates.

## Features
- Real-time network traffic monitoring from iOS apps
- Request/response inspection with syntax highlighting
- JSON formatting and visualization
- Device and project separation
- No proxy configuration or certificate installation required
- Bonjour-based automatic discovery
- **MCP (Model Context Protocol) server** — expose traffic and tools to Cursor, Claude Code, and other MCP clients

## Installation
1. Clone the repository
2. Open AppTrafficInspector.xcodeproj in Xcode
3. Build and run (⌘R)
4. Allow network connections when prompted

## Usage
Run an iOS app using the AppTrafficKit framework (coming soon) on the same network as your Mac running App Traffic Inspector. Network requests will automatically appear in the inspector.

---

## MCP Server — Add to your AI IDE

The app includes an MCP server (Streamable HTTP on port **43436**) so Cursor, Claude Code, and other clients can list projects/devices, inspect packets, search traffic, and get cURL commands. **The app must be running with “Enable MCP Server” turned on in Settings** before any client can connect.

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
- macOS 11.0 or later
- Xcode 13.0 or later (for building)

## License
Apache 2.0

## Attribution
Based on the original Bagel project by Yagiz Lab (https://github.com/yagiz/Bagel)
Licensed under Apache 2.0