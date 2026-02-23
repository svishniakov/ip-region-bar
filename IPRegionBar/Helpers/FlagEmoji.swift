import Foundation

enum FlagEmoji {
    static func from(countryCode: String) -> String {
        guard countryCode.count == 2 else { return "🌐" }
        let base: UInt32 = 127_397

        return countryCode.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(base + $0.value)
        }.map(String.init).joined()
    }
}
