import Foundation
import CoreData

class ErrorRecoveryManager {
    static func recover(from error: Error, in context: NSManagedObjectContext) {
        switch error {
        case let nsError as NSError where nsError.code == NSManagedObjectMergeError:
            context.rollback()
            context.refreshAllObjects()
        case let nsError as NSError where nsError.code == NSValidationErrorMinimum:
            context.rollback()
        default:
            context.rollback()
        }
    }
    
    static func handleNotificationError(_ error: Error) -> String {
        switch error {
        case let nsError as NSError:
            switch nsError.code {
            case 1:
                return "Notification permissions not granted"
            case 64:
                return "Too many notifications scheduled"
            default:
                return "Failed to schedule reminder"
            }
        default:
            return error.localizedDescription
        }
    }
}
