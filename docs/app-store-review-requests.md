# App Store review requests (Mac and iPhone)

Both apps use SwiftUI StoreKit `requestReview` and the same installation-local policy. The active Mac note supplies the presentation environment rather than its hidden desktop coordinator. Automatic requests are disabled in Debug, XCTest, UI tests and previews; the voluntary About link remains available. No analytics, content logging, cloud state, custom survey, incentives or sentiment filtering are involved.

Eligibility starts when this feature is first used, including existing installations: at least seven elapsed days, activity on three distinct local calendar days, and ten distinct nonempty tasks completed through successful local user actions. Imported, restored and synced completions do not count. Repeated completion of an already-completed task does not count; explicitly unchecking removes its engagement ID. IDs are bounded to ten opaque UUIDs in `appReviewPolicy.v1` UserDefaults alongside dates, counters and the last requested marketing version.

A successful completion schedules one opportunity after 30 seconds, beyond the 20-second completion/undo animation, with at least 60 seconds in the current foreground session. Subsequent completions debounce it; undo, backgrounding, keyboard editing and subsequent editing cancel it. Presentation is skipped while editing or another sheet/modal is open. A skipped opportunity is never retried at launch or resume; another completion is required. Mac input also cancels the pending opportunity.

Each call consumes a local request budget even when Apple silently suppresses its prompt: one request per marketing version, at least 120 days apart, at most three in a rolling 365 days. Ten fresh task completions are needed after a call. Apple independently controls display, user opt-out and review submission; no callback indicates display or successful rating. These thresholds are product choices, not Apple-mandated conversion guarantees. Each installation has its own budget; Apple controls its account-level restrictions.

About, the Mac status-item menu and the Mac application menu offer a localized **Rate Tildone** link to the existing universal App Store record with `action=write-review`. Explicit user intent uses this link instead of the discretionary prompt API.

## Verification

`AppReviewPolicyTests` belongs to both hosted unit-test targets and covers first use, engagement, duplicate/uncompleted tasks, time boundaries, version/cooldown limits, annual limits, persistence and clock rollback. Build both Release apps to compile the automatic path. In Debug no automatic prompt should appear while completing tasks. For manual native-dialog QA use a local non-TestFlight Release build with an isolated test preference domain; don't count a development dialog as evidence of production display. TestFlight never displays the review prompt.

Sources: [Apple requesting reviews](https://developer.apple.com/documentation/storekit/requesting-app-store-reviews), [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews), [App Store ratings and reviews](https://developer.apple.com/app-store/ratings-and-reviews/).

The engagement/age/version conditions and cancellable delay also follow the firsthand [WeTransfer/RocketSim implementation account by Antoine van der Lee](https://www.avanderlee.com/swift/skstorereviewcontroller-app-ratings/). Apple's current native-API restrictions take precedence over that older article's custom-popup suggestion. [RevenueCat's 2026 review experience](https://www.revenuecat.com/blog/engineering/dont-prompt-ratings-during-onboarding/) reinforces waiting until after meaningful use instead of asking during onboarding. No conversion lift is assumed for Tildone.
