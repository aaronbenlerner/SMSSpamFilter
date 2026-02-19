import IdentityLookup
import Foundation

final class MessageFilterExtension: ILMessageFilterExtension {}

// MARK: - ILMessageFilterQueryHandling

extension MessageFilterExtension: ILMessageFilterQueryHandling {

    func handle(
        _ queryRequest: ILMessageFilterQueryRequest,
        context: ILMessageFilterExtensionContext,
        completion: @escaping (ILMessageFilterQueryResponse) -> Void
    ) {
        let response = ILMessageFilterQueryResponse()

        guard let body = queryRequest.messageBody, !body.isEmpty else {
            response.action = .allow
            completion(response)
            return
        }

        let cleaned = Self.preprocess(body)
        let spamProb = Self.classifier.classify(cleaned)
        let threshold = loadThreshold()

        if spamProb >= threshold {
            response.action = .junk
        } else {
            response.action = .allow
        }

        updateStats(wasSpam: response.action == .junk)

        NSLog(
            "[SMSSpamFilter] body_len=%d spam_prob=%.4f threshold=%.2f action=%@",
            body.count, spamProb, threshold,
            response.action == .junk ? "junk" : "allow"
        )

        completion(response)
    }

    // MARK: - Shared UserDefaults (App Groups)

    private static let suiteName = "group.com.aaron.SMSSpamFilter"
    private static let thresholdKey = "spamThreshold"
    private static let totalFilteredKey = "totalFiltered"
    private static let spamBlockedKey = "spamBlocked"

    private func loadThreshold() -> Double {
        let defaults = UserDefaults(suiteName: Self.suiteName)
        let value = defaults?.double(forKey: Self.thresholdKey) ?? 0.0
        return value > 0.01 ? value : 0.60
    }

    private func updateStats(wasSpam: Bool) {
        guard let defaults = UserDefaults(suiteName: Self.suiteName) else { return }
        let total = defaults.integer(forKey: Self.totalFilteredKey)
        defaults.set(total + 1, forKey: Self.totalFilteredKey)
        if wasSpam {
            let blocked = defaults.integer(forKey: Self.spamBlockedKey)
            defaults.set(blocked + 1, forKey: Self.spamBlockedKey)
        }
    }

    // MARK: - Preprocessing (must match Python's preprocess())

    static func preprocess(_ text: String) -> String {
        var result = text.lowercased()
        result = result.unicodeScalars.map { scalar in
            CharacterSet.punctuationCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        result = result.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return result
    }

    // MARK: - Lazy-loaded classifier

    private static let classifier = SpamClassifier()
}

// MARK: - Native TF-IDF + Logistic Regression classifier

final class SpamClassifier {

    private let vocabulary: [String: Int]   // token → feature index
    private let idfWeights: [Double]        // indexed by feature
    private let lrCoefficients: [Double]    // indexed by feature
    private let lrIntercept: Double
    private let featureCount: Int

    init() {
        // Load model weights from bundled JSON
        guard let url = Bundle.main.url(forResource: "SMSSpamClassifier", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vocab = json["vocabulary"] as? [String: Int],
              let idf = json["idf_weights"] as? [Double],
              let coef = json["lr_coefficients"] as? [Double],
              let intercept = json["lr_intercept"] as? Double
        else {
            NSLog("[SMSSpamFilter] ERROR: Failed to load SMSSpamClassifier.json")
            vocabulary = [:]
            idfWeights = []
            lrCoefficients = []
            lrIntercept = 0
            featureCount = 0
            return
        }

        vocabulary = vocab
        idfWeights = idf
        lrCoefficients = coef
        lrIntercept = intercept
        featureCount = coef.count
    }

    /// Returns spam probability in [0, 1].
    func classify(_ text: String) -> Double {
        guard featureCount > 0 else { return 0.0 }  // fail-open if model didn't load

        // 1. Tokenize into unigrams and bigrams
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        var tokenCounts: [Int: Double] = [:]  // feature index → raw count

        // Unigrams
        for word in words {
            if let idx = vocabulary[word] {
                tokenCounts[idx, default: 0] += 1
            }
        }

        // Bigrams
        if words.count >= 2 {
            for i in 0..<(words.count - 1) {
                let bigram = "\(words[i]) \(words[i + 1])"
                if let idx = vocabulary[bigram] {
                    tokenCounts[idx, default: 0] += 1
                }
            }
        }

        guard !tokenCounts.isEmpty else { return 0.0 }

        // 2. Compute TF-IDF: tf(t) * idf(t)
        //    sklearn TfidfVectorizer uses raw term frequency (not normalized by doc length)
        var tfidfVector: [Int: Double] = [:]
        for (idx, count) in tokenCounts {
            tfidfVector[idx] = count * idfWeights[idx]
        }

        // 3. L2 normalize (sklearn default: norm='l2')
        var l2Norm = 0.0
        for (_, val) in tfidfVector {
            l2Norm += val * val
        }
        l2Norm = sqrt(l2Norm)

        if l2Norm > 0 {
            for idx in tfidfVector.keys {
                tfidfVector[idx]! /= l2Norm
            }
        }

        // 4. Dot product with LR coefficients + intercept
        var logit = lrIntercept
        for (idx, val) in tfidfVector {
            logit += val * lrCoefficients[idx]
        }

        // 5. Sigmoid
        let prob = 1.0 / (1.0 + exp(-logit))
        return prob
    }
}
