import AppKit

/// A minimal menu bar. Without one, AppKit gives a SwiftPM executable no way to
/// quit and no keyboard shortcuts.
@MainActor
public enum MainMenu {
    public static func build(controller: WindowController) -> NSMenu {
        // The template is written before the menu is built, so "Edit Key Bindings" always has
        // something to open.
        KeyBindings.writeTemplateIfMissing()

        let mainMenu = NSMenu()

        // Application menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Prince of Persia",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Prince of Persia",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Prince of Persia",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Game menu — the two things a player reaches for that are not the arrow keys.
        let gameItem = NSMenuItem()
        let gameMenu = NSMenu(title: "Game")
        gameMenu.addItem(withTitle: "New Game (from Level 1)",
                         action: #selector(WindowController.startNewGame(_:)),
                         keyEquivalent: "n")
        gameMenu.items.last?.target = controller
        gameMenu.addItem(withTitle: "Restart Level",
                         action: #selector(WindowController.restartLevel(_:)),
                         keyEquivalent: "r")
        gameMenu.items.last?.target = controller
        gameItem.submenu = gameMenu
        mainMenu.addItem(gameItem)

        // Options menu — where the key bindings live.
        let optionsItem = NSMenuItem()
        let optionsMenu = NSMenu(title: "Options")
        optionsMenu.addItem(withTitle: "Edit Key Bindings…",
                            action: #selector(WindowController.revealKeyBindings(_:)),
                            keyEquivalent: "k")
        optionsMenu.items.last?.target = controller
        optionsMenu.addItem(withTitle: "Reset Key Bindings to Default",
                            action: #selector(WindowController.resetKeyBindings(_:)),
                            keyEquivalent: "")
        optionsMenu.items.last?.target = controller
        optionsItem.submenu = optionsMenu
        mainMenu.addItem(optionsItem)

        // View menu — the scale switch, as Cmd-1 through Cmd-6.
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        for scale in WindowScale.fitting {
            let size = WindowScale.windowSize(for: scale)
            let item = NSMenuItem(
                title: "\(scale)x   \(Int(size.width)) x \(Int(size.height))",
                action: #selector(WindowController.selectScale(_:)),
                keyEquivalent: "\(scale)"
            )
            item.keyEquivalentModifierMask = [.command]
            item.tag = scale
            item.target = controller
            viewMenu.addItem(item)
        }
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        // Window menu — which is what gives Cmd-W and Cmd-M somewhere to live. Without it the
        // only way to close the window is the red button, and the delegate that quits on the last
        // window closing would be almost unreachable.
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        // Telling AppKit it owns this menu is what makes it list the windows below the items.
        NSApplication.shared.windowsMenu = windowMenu

        return mainMenu
    }
}
