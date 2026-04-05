import AppKit
import ApplicationServices

extension AXUIElement {
    func attribute<T>(_ attr: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attr as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    var role: String? { attribute(kAXRoleAttribute) }
    var title: String? { attribute(kAXTitleAttribute) }
    var axDescription: String? { attribute(kAXDescriptionAttribute) }
    var identifier: String? { attribute("AXIdentifier") }
    var value: AnyObject? { attribute(kAXValueAttribute) }
    var children: [AXUIElement] { attribute(kAXChildrenAttribute) ?? [] }
    var windows: [AXUIElement] { attribute(kAXWindowsAttribute) ?? [] }

    var minValue: AnyObject? { attribute(kAXMinValueAttribute) }
    var maxValue: AnyObject? { attribute(kAXMaxValueAttribute) }

    func setValue(_ value: AnyObject) -> Bool {
        AXUIElementSetAttributeValue(self, kAXValueAttribute as CFString, value) == .success
    }

    func press() -> Bool {
        AXUIElementPerformAction(self, kAXPressAction as CFString) == .success
    }

    func menuBarItems() -> [AXUIElement] {
        guard let menuBars: [AXUIElement] = attribute(kAXExtrasMenuBarAttribute).map({ [$0] })
                ?? attribute("AXMenuBar").map({ [$0] }) else {
            return []
        }
        return menuBars.flatMap { $0.children }
    }

    func findChild(role: String? = nil, description: String? = nil, identifier: String? = nil, recursive: Bool = false) -> AXUIElement? {
        for child in children {
            if let role, child.role != role { continue }
            if let description, child.axDescription != description { continue }
            if let identifier, child.identifier != identifier { continue }
            return child
        }
        if recursive {
            for child in children {
                if let found = child.findChild(role: role, description: description, identifier: identifier, recursive: true) {
                    return found
                }
            }
        }
        return nil
    }

    func findChildren(role: String? = nil, identifierPrefix: String? = nil) -> [AXUIElement] {
        var results: [AXUIElement] = []
        for child in children {
            if let role, child.role != role { continue }
            if let prefix = identifierPrefix, !(child.identifier?.hasPrefix(prefix) ?? false) { continue }
            results.append(child)
        }
        return results
    }

    func findAllRecursive(role: String, maxDepth: Int = 10) -> [AXUIElement] {
        var results: [AXUIElement] = []
        findAllRecursiveHelper(role: role, depth: 0, maxDepth: maxDepth, results: &results)
        return results
    }

    private func findAllRecursiveHelper(role: String, depth: Int, maxDepth: Int, results: inout [AXUIElement]) {
        if self.role == role { results.append(self) }
        guard depth < maxDepth else { return }
        for child in children {
            child.findAllRecursiveHelper(role: role, depth: depth + 1, maxDepth: maxDepth, results: &results)
        }
    }

    func findAllCheckboxes(identifierPrefix: String) -> [(identifier: String, element: AXUIElement)] {
        var results: [(String, AXUIElement)] = []

        // Direct checkboxes
        for child in children {
            if child.role == "AXCheckBox",
               let id = child.identifier,
               id.hasPrefix(identifierPrefix) {
                results.append((id, child))
            }
        }

        // Checkboxes inside groups
        for child in children where child.role == "AXGroup" {
            for groupChild in child.children {
                if groupChild.role == "AXCheckBox",
                   let id = groupChild.identifier,
                   id.hasPrefix(identifierPrefix) {
                    results.append((id, groupChild))
                }
            }
        }

        return results
    }

    static func appElement(bundleIdentifier: String) -> AXUIElement? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let app = apps.first else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }
}
