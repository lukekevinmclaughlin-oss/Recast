import Foundation

/// Keeps monetisation and review prompts respectful and milestone-based.
@MainActor
final class EngagementManager: ObservableObject {
    static let shared = EngagementManager()

    @Published var showWelcome = false
    @Published var showPremiumReminder = false
    @Published var shouldRequestReview = false

    private let defaults = UserDefaults.standard
    private let day: TimeInterval = 86_400

    private init() {
        let launches = defaults.integer(forKey: "engagement.launchCount") + 1
        defaults.set(launches, forKey: "engagement.launchCount")
        showWelcome = !defaults.bool(forKey: "engagement.hasSeenWelcome")
    }

    func completeWelcome() {
        defaults.set(true, forKey: "engagement.hasSeenWelcome")
        showWelcome = false
    }

    func recordPaywallShown() {
        defaults.set(Date().timeIntervalSince1970, forKey: "engagement.lastPaywallAt")
    }

    func recordPaywallDismissed() {
        defaults.set(Date().timeIntervalSince1970, forKey: "engagement.lastPaywallAt")
    }

    func recordSuccessfulConversion(isPremium: Bool) {
        let count = defaults.integer(forKey: "engagement.successfulConversions") + 1
        defaults.set(count, forKey: "engagement.successfulConversions")
        let now = Date().timeIntervalSince1970
        let lastPaywall = defaults.double(forKey: "engagement.lastPaywallAt")
        let lastReminder = defaults.double(forKey: "engagement.lastPremiumReminderAt")
        let launches = defaults.integer(forKey: "engagement.launchCount")

        if !isPremium, count >= 3, now - lastReminder >= 7 * day, now - lastPaywall >= day {
            defaults.set(now, forKey: "engagement.lastPremiumReminderAt")
            showPremiumReminder = true
            return
        }

        let lastReview = defaults.double(forKey: "engagement.lastReviewRequestAt")
        if count >= 5, launches >= 3, now - lastReview >= 180 * day, now - lastPaywall >= day {
            defaults.set(now, forKey: "engagement.lastReviewRequestAt")
            shouldRequestReview = true
        }
    }
}
