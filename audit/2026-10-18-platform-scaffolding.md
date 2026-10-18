# Platform Scaffolding Audit — 2026-10-18

Unused desktop and web platform scaffolding. The app targets Android and iOS only.

1. linux/CMakeLists.txt:1-128, Flutter template scaffolding for Linux; CI never builds it
2. macos/Runner/AppDelegate.swift:1-12, Flutter template scaffolding for macOS; CI never builds it
3. windows/CMakeLists.txt:1-108, Flutter template scaffolding for Windows; CI never builds it
4. web/index.html:1-37, Flutter template scaffolding for web; CI never builds it
5. .metadata:24-36, lists linux, macos, web and windows platforms that are never built
