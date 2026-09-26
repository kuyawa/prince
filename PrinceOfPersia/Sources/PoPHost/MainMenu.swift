import AppKit

/// A minimal menu bar. Without one, AppKit gives a SwiftPM executable no way to
/// quit and no keyboard shortcuts.
@MainActor
public enum MainMenu {
    public static func build(controller: WindowController) -> NSMenu {
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
