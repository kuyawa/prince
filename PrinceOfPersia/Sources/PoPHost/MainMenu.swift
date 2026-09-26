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

        return mainMenu
    }
}
