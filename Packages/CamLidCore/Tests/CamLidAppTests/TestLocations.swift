import Foundation
import CamLidCore

extension StateLocations {
    /// The folders of a test copy: inside `root`, and counted as a QA copy, so no test reaches the owner's folders or
    /// the installed helper. `history` and `control` default to the folders a QA copy uses.
    static func test(root: URL, history: URL? = nil, control: URL? = nil) -> StateLocations {
        StateLocations(history: history ?? root.appendingPathComponent("history", isDirectory: true),
                       control: control ?? root.appendingPathComponent("control", isDirectory: true),
                       home: root.appendingPathComponent("home", isDirectory: true), qaRoot: root)
    }
}
