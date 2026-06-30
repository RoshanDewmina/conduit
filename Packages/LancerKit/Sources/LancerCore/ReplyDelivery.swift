import Foundation

public enum ReplyDeliveryStatus: Sendable, Equatable {
    case idle
    case sending
    case delivered
    case failed(reason: String)
    case expiredBeforeDelivery
}
