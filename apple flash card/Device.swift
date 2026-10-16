import UIKit

enum Device {
    /// iPhone has no Apple Pencil, so it gets the study experience only: no card editor.
    static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
}
