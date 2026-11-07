import Foundation

// MARK: - Full legal text, v5
// The COMPLETE privacy policy and terms of service text from the
// live site, embedded natively so both documents read in full
// inside the app with no web view and no outside link.
// Source, fetched read-only from the laptop on 7 Nov 2026:
//   templates/privacy_policy.html (3,373 bytes)
//   templates/terms_of_service.html (3,377 bytes)
// HTML tags were stripped to plain text only. Wording, headings,
// order and structure are unchanged. Nothing was summarised,
// paraphrased or added.
// NOTE: the two site templates carry the same body text. The terms
// file on the site repeats the privacy policy sections word for
// word (only its title differs), so the terms document below is
// that same real text, not a rewritten version. If the site terms
// page is ever rewritten, this copy must be re-fetched from the
// template and replaced, never edited by hand to guess new terms.
// Counts (body text inside <main>, title included):
//   Privacy policy: 263 words, 1,899 characters
//   Terms of service: 264 words, 1,901 characters
//   Effective date on both: June 14, 2026

enum LegalBlock {
    case paragraph(String)
    case bullet(String)
}

struct LegalSection {
    let heading: String
    let blocks: [LegalBlock]
}

struct LegalDocument {
    let title: String
    let effectiveDate: String
    let sourceTemplate: String
    let sections: [LegalSection]
}

enum LegalText {
    static let privacyPolicy = LegalDocument(
        title: "Privacy Policy",
        effectiveDate: "June 14, 2026",
        sourceTemplate: "templates/privacy_policy.html",
        sections: [
            LegalSection(
                heading: "1. Information We Collect",
                blocks: [
                    .paragraph("To provide you with secure access to our shared subscription platform, we collect the following information:"),
                    .bullet("Account Details: Your full name, email address, and optionally your phone number. Your account authentication (passwords, social logins, and secure sessions) is securely handled by our identity provider, Clerk."),
                    .bullet("Payment Information: Transaction details necessary to verify and process your subscription requests via our approved payment providers."),
                    .bullet("Usage Data: Essential cookies for authentication and platform preference data (such as Dark/Light mode)."),
                ]
            ),
            LegalSection(
                heading: "2. How We Use Your Data",
                blocks: [
                    .paragraph("We use your information strictly for operational purposes:"),
                    .bullet("Verifying payments and fulfilling requested subscription slots."),
                    .bullet("Sending crucial account notifications, verification codes, password resets, and renewal reminders via email and WhatsApp."),
                    .bullet("Providing customer support and resolving access issues."),
                    .paragraph("We do not sell, rent, or trade your personal information to third parties."),
                ]
            ),
            LegalSection(
                heading: "3. \"Burn-After-Reading\" Security",
                blocks: [
                    .paragraph("For your protection and to maintain the integrity of our shared accounts, we employ a strict \"Burn-After-Reading\" protocol. Once you reveal your streaming credentials on your dashboard, the platform immediately deletes them from your active session memory. They are hidden upon refresh to prevent unauthorized over-the-shoulder viewing."),
                ]
            ),
            LegalSection(
                heading: "4. Account Security",
                blocks: [
                    .paragraph("Your authentication credentials are cryptographically protected and managed exclusively by Clerk, an industry-leading identity provider. Our administrators cannot see your password. However, you are responsible for maintaining the confidentiality of your login credentials."),
                ]
            ),
            LegalSection(
                heading: "5. Contact & Data Deletion",
                blocks: [
                    .paragraph("If you wish to have your account or data permanently deleted from our servers, please contact our administrative team via the WhatsApp support link provided in the site footer."),
                ]
            ),
        ]
    )

    static let termsOfService = LegalDocument(
        title: "Terms of Service",
        effectiveDate: "June 14, 2026",
        sourceTemplate: "templates/terms_of_service.html",
        sections: [
            LegalSection(
                heading: "1. Information We Collect",
                blocks: [
                    .paragraph("To provide you with secure access to our shared subscription platform, we collect the following information:"),
                    .bullet("Account Details: Your full name, email address, and optionally your phone number. Your account authentication (passwords, social logins, and secure sessions) is securely handled by our identity provider, Clerk."),
                    .bullet("Payment Information: Transaction details necessary to verify and process your subscription requests via our approved payment providers."),
                    .bullet("Usage Data: Essential cookies for authentication and platform preference data (such as Dark/Light mode)."),
                ]
            ),
            LegalSection(
                heading: "2. How We Use Your Data",
                blocks: [
                    .paragraph("We use your information strictly for operational purposes:"),
                    .bullet("Verifying payments and fulfilling requested subscription slots."),
                    .bullet("Sending crucial account notifications, verification codes, password resets, and renewal reminders via email and WhatsApp."),
                    .bullet("Providing customer support and resolving access issues."),
                    .paragraph("We do not sell, rent, or trade your personal information to third parties."),
                ]
            ),
            LegalSection(
                heading: "3. \"Burn-After-Reading\" Security",
                blocks: [
                    .paragraph("For your protection and to maintain the integrity of our shared accounts, we employ a strict \"Burn-After-Reading\" protocol. Once you reveal your streaming credentials on your dashboard, the platform immediately deletes them from your active session memory. They are hidden upon refresh to prevent unauthorized over-the-shoulder viewing."),
                ]
            ),
            LegalSection(
                heading: "4. Account Security",
                blocks: [
                    .paragraph("Your authentication credentials are cryptographically protected and managed exclusively by Clerk, an industry-leading identity provider. Our administrators cannot see your password. However, you are responsible for maintaining the confidentiality of your login credentials."),
                ]
            ),
            LegalSection(
                heading: "5. Contact & Data Deletion",
                blocks: [
                    .paragraph("If you wish to have your account or data permanently deleted from our servers, please contact our administrative team via the WhatsApp support link provided in the site footer."),
                ]
            ),
        ]
    )
}
