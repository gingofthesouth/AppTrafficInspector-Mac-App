# App Traffic Inspector

App Traffic Inspector is a native macOS network debugging tool for iOS development. It allows you to inspect HTTP/HTTPS network traffic from your iOS apps in real-time without proxy settings or certificates.

## Features
- Real-time network traffic monitoring from iOS apps
- Request/response inspection with syntax highlighting
- JSON formatting and visualization
- Device and project separation
- No proxy configuration or certificate installation required
- Bonjour-based automatic discovery

## Installation
1. Clone the repository
2. Open AppTrafficInspector.xcodeproj in Xcode
3. Build and run (⌘R)
4. Allow network connections when prompted

## Usage
Run an iOS app using the AppTrafficKit framework (coming soon) on the same network as your Mac running App Traffic Inspector. Network requests will automatically appear in the inspector.

## System Requirements
- macOS 11.0 or later
- Xcode 13.0 or later (for building)

## License
Apache 2.0

## Attribution
Based on the original Bagel project by Yagiz Lab (https://github.com/yagiz/Bagel)
Licensed under Apache 2.0