/// Defines all of the Analytics Operations we'll be performing. This allows us to swap the actual Wrapper in our
/// Unit Testing target.
///
public protocol AnalyticsProvider {

    /// Track a spcific event without any associated properties
    ///
    /// - Parameter eventName: the event name
    ///
    func track(_ eventName: String)


    /// Track a spcific event with associated properties
    ///
    /// - Parameters:
    ///   - eventName: the event name
    ///   - properties: a collection of properties
    ///
    func track(_ eventName: String, withProperties properties: [AnyHashable : Any]?)    
}
