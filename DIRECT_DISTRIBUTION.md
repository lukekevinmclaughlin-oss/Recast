# Recast Direct edition

The App Store and website editions share core conversion code but have separate commercial builds.

- `Release` keeps StoreKit subscriptions for the Mac App Store.
- `Direct` defines `DIRECT_DISTRIBUTION`, uses bundle ID `com.lukemclaughlin.recast.direct`, compiles out StoreKit and subscription UI, and grants permanent access to every feature.
- `scripts/build-direct.sh` produces a universal Developer ID-signed DMG, notarizes it with Apple, staples the ticket, checks Gatekeeper and records its SHA-256 checksum.

Never publish a website installer unless every gate in the script passes.
