# Launch at Login — design sketch (superseded)

> ## ⚠️ 勘误 / Superseded — 2026-09-24
>
> **本文描述的做法没有被采用，也不应该被采用。**
>
> 文中方案要求额外构建一个 `PocketLauncherLoginHelper.app`，并用
> `SMLoginItemSetEnabled` 注册。这条路在 macOS 13 之后已被 Apple 弃用：
> 它需要往应用包里塞一个辅助 App、需要为它单独签名与公证，
> 而且在沙盒开启时会因为无法写入 `~/Library/LoginItems` 而失败。
>
> **实际实现**是 `AppPocket/Services/LaunchAtLogin.swift`，全文 32 行，用的是
> `SMAppService.mainApp`：
>
> ```swift
> @MainActor
> enum LaunchAtLogin {
>     static var isEnabled: Bool {
>         SMAppService.mainApp.status == .enabled
>     }
>
>     /// Registers or unregisters the app as a login item.
>     ///
>     /// This throws when macOS refuses the request — most commonly because the
>     /// app is being run straight out of Xcode's build folder rather than from
>     /// `/Applications`. The caller surfaces the message to the user.
>     static func setEnabled(_ enabled: Bool) throws {
>         let service = SMAppService.mainApp
>         if enabled {
>             guard service.status != .enabled else { return }
>             try service.register()
>         } else {
>             guard service.status == .enabled else { return }
>             try service.unregister()
>         }
>     }
> }
> ```
>
> 注意最后那个注释：**从 Xcode 构建目录直接运行时注册会失败**，这是
> `SMAppService` 的正常行为，不是 bug。`SettingsView` 会把错误信息显示给用户。
>
> 没有辅助 App，没有 `SMLoginItemSetEnabled`，没有额外的签名步骤。
> 用户可以在「设置 → 通用 → 登录时启动」里开关，也可以在
> 「系统设置 → 通用 → 登录项」里看到并管理同一个条目。
>
> 下面保留的是原设计草案，作为历史记录；其中的文件名、类名与 API
> 均与当前代码无关。

---

## Overview

This document provides instructions and skeleton code for implementing launch-at-login functionality using a helper app bundle with `SMLoginItemSetEnabled`. This approach ensures PocketLauncher can automatically start when the user logs in.

## Architecture

The launch-at-login system consists of two components:
1. **Main App** (`PocketLauncher.app`) - The primary application
2. **Login Helper** (`PocketLauncherLoginHelper.app`) - Minimal helper app that launches the main app

## Helper App Implementation

### 1. Create Helper App Target

Create a new macOS app target in Xcode named `PocketLauncherLoginHelper`.

### 2. Helper App Structure

```swift
//
//  PocketLauncherLoginHelperApp.swift
//  PocketLauncherLoginHelper
//
//  Created by GitHub Copilot on 2025-09-28.
//

import Cocoa
import ServiceManagement

@main
class PocketLauncherLoginHelperApp: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if main app is already running
        let mainAppBundleIdentifier = "com.yourcompany.PocketLauncher"
        
        if !isMainAppRunning(bundleIdentifier: mainAppBundleIdentifier) {
            // Launch main app
            launchMainApp()
        }
        
        // Terminate helper app immediately after launching main app
        NSApp.terminate(nil)
    }
    
    private func isMainAppRunning(bundleIdentifier: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }
    
    private func launchMainApp() {
        let mainAppBundleIdentifier = "com.yourcompany.PocketLauncher"
        
        // Method 1: Launch by bundle identifier
        if let mainAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainAppBundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            
            NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration) { _, error in
                if let error = error {
                    print("❌ Helper: Failed to launch main app: \(error)")
                }
            }
        } else {
            // Method 2: Fallback to relative path
            launchMainAppByPath()
        }
    }
    
    private func launchMainAppByPath() {
        guard let helperAppPath = Bundle.main.bundlePath else { return }
        
        // Navigate from helper app to main app
        // Helper is at: PocketLauncher.app/Contents/Library/LoginItems/PocketLauncherLoginHelper.app
        // Main app is at: PocketLauncher.app
        let mainAppPath = (helperAppPath as NSString)
            .deletingLastPathComponent           // Remove PocketLauncherLoginHelper.app
            .deletingLastPathComponent           // Remove LoginItems
            .deletingLastPathComponent           // Remove Library
            .deletingLastPathComponent           // Remove Contents
        
        let mainAppURL = URL(fileURLWithPath: mainAppPath)
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        
        NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration) { _, error in
            if let error = error {
                print("❌ Helper: Failed to launch main app by path: \(error)")
            }
        }
    }
}
```

### 3. Helper App Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourcompany.PocketLauncherLoginHelper</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSBackgroundOnly</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>PocketLauncherLoginHelperApp</string>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
```

**Key Properties Explained:**
- `LSBackgroundOnly`: Helper runs without appearing in Dock
- `LSUIElement`: Helper doesn't appear in menu bar or Dock
- `NSPrincipalClass`: Custom app delegate class

### 4. Helper App Entitlements

Create `PocketLauncherLoginHelper.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

## Main App Integration

### 1. LaunchAtLoginManager

```swift
//
//  LaunchAtLoginManager.swift
//  PocketLauncher
//
//  Created by GitHub Copilot on 2025-09-28.
//

import Foundation
import ServiceManagement

/// Manager for handling launch-at-login functionality
final class LaunchAtLoginManager: ObservableObject {
    
    // MARK: - Properties
    
    static let shared = LaunchAtLoginManager()
    
    /// Bundle identifier for the login helper
    private let helperBundleIdentifier = "com.yourcompany.PocketLauncherLoginHelper"
    
    /// Current launch-at-login status
    @Published private(set) var isEnabled = false
    
    // MARK: - Initialization
    
    private init() {
        checkCurrentStatus()
    }
    
    // MARK: - Public Interface
    
    /// Toggle launch-at-login setting
    /// - Parameter enabled: Whether to enable or disable launch-at-login
    /// - Returns: Success status
    @discardableResult
    func setLaunchAtLogin(enabled: Bool) -> Bool {
        let success = SMLoginItemSetEnabled(helperBundleIdentifier as CFString, enabled)
        
        if success {
            isEnabled = enabled
            savePreference(enabled: enabled)
            print("✅ Launch at login \(enabled ? "enabled" : "disabled")")
        } else {
            print("❌ Failed to \(enabled ? "enable" : "disable") launch at login")
        }
        
        return success
    }
    
    /// Check if launch-at-login is currently enabled
    func checkCurrentStatus() {
        // Check system preferences
        let systemEnabled = isHelperRegistered()
        
        // Check user preferences
        let userPreferenceEnabled = UserDefaults.standard.bool(forKey: "LaunchAtLogin")
        
        // Use user preference as source of truth, but validate against system
        isEnabled = userPreferenceEnabled
        
        // If there's a mismatch, update system to match preference
        if systemEnabled != userPreferenceEnabled {
            setLaunchAtLogin(enabled: userPreferenceEnabled)
        }
    }
    
    /// Check if the helper is registered with the system
    private func isHelperRegistered() -> Bool {
        // Note: In modern macOS, SMJobCopyDictionary is deprecated
        // We'll use a simple heuristic based on login items
        return checkLoginItemsForHelper()
    }
    
    /// Check login items for our helper (fallback method)
    private func checkLoginItemsForHelper() -> Bool {
        // This is a simplified check - in production you might want to use
        // the Login Items API or check with System Preferences
        let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems, nil)
        guard let loginItemsRef = loginItems?.takeRetainedValue() else { return false }
        
        let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItemsRef, nil)
        guard let itemsArray = loginItemsSnapshot?.takeRetainedValue() as? [LSSharedFileListItem] else {
            return false
        }
        
        for item in itemsArray {
            if let itemURL = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() {
                let itemPath = itemURL.path
                if itemPath.contains(helperBundleIdentifier) {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Persistence
    
    private func savePreference(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "LaunchAtLogin")
    }
}

// MARK: - Modern API Extension (macOS 13+)

@available(macOS 13.0, *)
extension LaunchAtLoginManager {
    
    /// Modern approach using SMAppService (macOS 13+)
    func setLaunchAtLoginModern(enabled: Bool) async throws {
        let service = SMAppService.loginItem(identifier: helperBundleIdentifier)
        
        if enabled {
            try await service.register()
        } else {
            try await service.unregister()
        }
        
        await MainActor.run {
            self.isEnabled = enabled
            self.savePreference(enabled: enabled)
        }
    }
    
    /// Check status using modern API
    func checkStatusModern() async -> Bool {
        let service = SMAppService.loginItem(identifier: helperBundleIdentifier)
        return service.status == .enabled
    }
}
```

### 2. Integration with Settings

```swift
//
//  SettingsIntegration.swift
//  PocketLauncher
//
//  Integration code for Settings view
//

import SwiftUI

struct LaunchAtLoginSettingView: View {
    @StateObject private var launchManager = LaunchAtLoginManager.shared
    
    var body: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { launchManager.isEnabled },
            set: { enabled in
                launchManager.setLaunchAtLogin(enabled: enabled)
            }
        ))
        .help("Automatically start PocketLauncher when you log in to macOS")
    }
}
```

## Build Configuration

### 1. Embed Helper in Main App

In Xcode build phases, add a "Copy Files" phase:
- **Destination**: Wrapper
- **Subpath**: `Contents/Library/LoginItems`
- **Files**: `PocketLauncherLoginHelper.app`

### 2. Code Signing

Both apps must be signed with the same Developer ID:

```bash
# Sign helper app
codesign --force --sign "Developer ID Application: Your Name" \
    --entitlements PocketLauncherLoginHelper.entitlements \
    PocketLauncherLoginHelper.app

# Sign main app (includes helper)
codesign --force --sign "Developer ID Application: Your Name" \
    --entitlements PocketLauncher.entitlements \
    --deep PocketLauncher.app
```

### 3. Notarization

The helper app will be notarized as part of the main app bundle:

```bash
# Create archive
ditto -c -k --sequesterRsrc --keepParent PocketLauncher.app PocketLauncher.zip

# Submit for notarization
xcrun notarytool submit PocketLauncher.zip \
    --keychain-profile "notarytool-profile" \
    --wait

# Staple notarization
xcrun stapler staple PocketLauncher.app
```

## Testing

### 1. Manual Testing

```swift
//
//  LaunchAtLoginTests.swift
//  Manual testing procedures
//

class LaunchAtLoginTests {
    
    /// Test basic enable/disable functionality
    func testEnableDisable() {
        let manager = LaunchAtLoginManager.shared
        
        // Test enabling
        let enableResult = manager.setLaunchAtLogin(enabled: true)
        assert(enableResult, "Failed to enable launch at login")
        assert(manager.isEnabled, "Manager state not updated")
        
        // Test disabling
        let disableResult = manager.setLaunchAtLogin(enabled: false)
        assert(disableResult, "Failed to disable launch at login")
        assert(!manager.isEnabled, "Manager state not updated")
    }
    
    /// Test persistence across app restarts
    func testPersistence() {
        // 1. Enable launch at login
        // 2. Restart app
        // 3. Verify setting is still enabled
        // 4. Test actual login behavior
    }
    
    /// Test helper app launching
    func testHelperLaunch() {
        // 1. Enable launch at login
        // 2. Log out and back in
        // 3. Verify main app launches automatically
        // 4. Verify helper terminates properly
    }
}
```

### 2. System Integration Testing

1. **Enable Launch at Login**: Verify toggle works in Settings
2. **Log Out/In Test**: Confirm app launches on login
3. **Helper Behavior**: Ensure helper terminates after launching main app
4. **Multiple Instances**: Verify no duplicate app instances are created
5. **Disable Test**: Confirm app doesn't launch when disabled

## Security Considerations

### 1. Sandboxing
- Helper app runs outside sandbox to launch main app
- Main app can use App Sandbox if desired
- Minimize helper app privileges

### 2. Code Signing
- Both apps must be properly signed
- Use same Developer ID for both apps
- Include proper entitlements

### 3. User Control
- Always respect user's launch at login preference
- Provide clear UI for enabling/disabling
- Don't enable automatically without user consent

## Troubleshooting

### Common Issues

1. **Helper Not Launching Main App**
   - Verify bundle identifier matches
   - Check helper app permissions
   - Validate code signing

2. **Toggle Not Working**
   - Check SMLoginItemSetEnabled return value
   - Verify helper app is embedded correctly
   - Test on clean system (not development machine)

3. **Multiple App Instances**
   - Ensure helper checks for running main app
   - Implement singleton pattern in main app
   - Add activation logic to bring existing instance to front

### Debug Logging

```swift
// Add to helper app for debugging
func logDebugInfo() {
    print("🔧 Helper Debug Info:")
    print("  Helper Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
    print("  Helper Path: \(Bundle.main.bundlePath)")
    print("  Main App Running: \(isMainAppRunning(bundleIdentifier: "com.yourcompany.PocketLauncher"))")
}
```

This implementation provides a robust launch-at-login system that follows Apple's current best practices while maintaining compatibility across macOS versions.