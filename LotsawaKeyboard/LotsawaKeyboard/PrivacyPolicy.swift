import Foundation

/// Privacy Policy for Lotsawa Keyboard
/// This can be displayed in-app and linked from the App Store
public struct PrivacyPolicy {
    public static let lastUpdated = "January 2025"

    public static let text = """
    LOTSAWA KEYBOARD PRIVACY POLICY
    Last Updated: \(lastUpdated)

    1. OVERVIEW
    Lotsawa Keyboard ("the App") is a Tibetan transliteration keyboard for iOS. We are committed to protecting your privacy. This policy explains our data practices.

    2. DATA COLLECTION
    Lotsawa Keyboard does NOT collect, store, or transmit any personal data. Specifically:

    - NO keystroke logging: We do not record what you type
    - NO analytics: We do not track your usage patterns
    - NO network transmission: The keyboard operates entirely offline
    - NO cloud storage: All processing happens locally on your device
    - NO third-party services: We do not integrate with any external services

    3. LOCAL DATA STORAGE
    The App stores the following data ONLY on your device:
    - Your preference settings (input mode, haptic feedback)
    - The built-in Tibetan dictionary (pre-installed, not downloaded)

    This data never leaves your device.

    4. KEYBOARD EXTENSION PERMISSIONS
    Lotsawa Keyboard is configured with "RequestsOpenAccess: false", meaning:
    - The keyboard cannot access the network
    - The keyboard cannot share data with the container app
    - The keyboard operates in a sandboxed environment

    5. CHILDREN'S PRIVACY
    The App does not collect any data from anyone, including children under 13.

    6. CHANGES TO THIS POLICY
    We may update this policy. Changes will be reflected in the "Last Updated" date.

    7. CONTACT
    For privacy questions, please contact us through the App Store.

    8. YOUR RIGHTS
    Since we collect no personal data, there is no personal data to access, correct, or delete.
    """

    public static let summary = """
    Lotsawa Keyboard is a privacy-first keyboard:
    - Works completely offline
    - No data collection
    - No network access
    - No tracking
    """
}
