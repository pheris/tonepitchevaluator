import Foundation

// MARK: - Coaching feedback (structured output)

/// The structured coaching Claude returns for one scale run. Decoded directly
/// from the model's JSON response (constrained via `output_config.format`).
struct CoachingFeedback: Codable, Sendable {
    struct Tip: Codable, Sendable {
        /// Area of focus, e.g. "Embouchure", "Reed", "Assembly", "Intonation", "Tone", "Tempo".
        let area: String
        let tip: String
    }

    /// A real, well-known resource the coaching drew on.
    struct Reference: Codable, Sendable {
        let title: String
        let url: String
    }

    /// One punchy line on how close this sounds to a professional.
    let headline: String
    /// A concise 1–2 sentence top-level summary (the TL;DR).
    let summary: String
    /// Specific, genuine praise.
    let positives: [String]
    /// Actionable issues with concrete fixes.
    let issues: [Tip]
    /// Commentary on any notes that were consistently out of tune.
    let problemNoteComment: String
    /// Playful instrument guess (clarinet only).
    let clarinetGuess: String?
    /// Playful reed/strength guess (clarinet only).
    let reedGuess: String?
    /// Voice classification remark (voice only).
    let voiceType: String?
    /// Commentary on the singer's measured range (voice only).
    let rangeComment: String?
    /// A well-known singer from the user's locale with a comparable range,
    /// stated as a best-effort match (voice only).
    let singerMatch: String?
    /// Which professional player/style this is reminiscent of, if any.
    let styleComparison: String
    /// A warm closing note of encouragement.
    let encouragement: String
    /// Real, well-known resources the tips draw on (may be empty).
    let references: [Reference]

    /// References with dead-end links filtered out — in particular YouTube
    /// channel/user/handle pages (only actual watch/share links survive) — so a
    /// slipped channel link never reaches the UI.
    var safeReferences: [Reference] {
        references.filter { ref in
            guard let url = URL(string: ref.url), let host = url.host?.lowercased() else { return false }
            if host.contains("youtube.com") || host.contains("youtu.be") {
                let path = url.path.lowercased()
                let isVideo = host.contains("youtu.be") || path == "/watch" || path.hasPrefix("/shorts/")
                return isVideo
            }
            return true
        }
    }
}

// MARK: - Singer match

/// A best-effort match of the singer's measured range to a well-known singer
/// from their locale, returned as structured output.
struct SingerMatch: Codable, Sendable {
    /// The named singer (or an honest "not sure" message).
    let singer: String
    /// One sentence on why their range/tessitura is comparable.
    let reason: String
    /// A short confirmation/nuance on the voice-type classification.
    let voiceTypeNote: String
}

// MARK: - Errors

enum CoachError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case refusal
    case emptyResponse
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add your Anthropic API key in Settings to get AI coaching."
        case .http(let status, let message): return "Claude API error (\(status)): \(message)"
        case .refusal: return "Claude declined to analyze this recording."
        case .emptyResponse: return "Claude returned an empty response."
        case .decoding(let detail): return "Couldn't read Claude's response: \(detail)"
        }
    }
}

// MARK: - Client

/// Talks to the Claude Messages API over raw HTTPS (Swift has no official
/// Anthropic SDK). Sends the objective tone analysis and asks Claude for
/// grounded, warm, specific clarinet coaching as structured JSON.
struct ClaudeCoach {
    static let model = "claude-opus-4-8"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var apiKey: String

    func coach(on report: ToneReport) async throws -> CoachingFeedback {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw CoachError.missingAPIKey }

        let reportJSON = try Self.encodeReport(report)
        let body = Self.requestBody(reportJSON: reportJSON, instrument: report.instrument, region: report.region)

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoachError.http(status: -1, message: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CoachError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }

        return try Self.parse(CoachingFeedback.self, from: data)
    }

    /// Ask Claude for a best-effort singer from the user's locale whose range is
    /// comparable to the measured `profile`. Lighter than full coaching.
    func matchSinger(profile: VoiceProfile) async throws -> SingerMatch {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw CoachError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.singerRequestBody(profile: profile))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoachError.http(status: -1, message: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CoachError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return try Self.parse(SingerMatch.self, from: data)
    }

    private static func singerRequestBody(profile: VoiceProfile) -> [String: Any] {
        let prompt = """
        You match amateur singers to well-known professional singers by vocal range. Name ONE real, \
        well-known singer from the region "\(profile.regionName)" whose tessitura/vocal range is \
        comparable to the measured range below. Present it as a playful best-effort match, not a \
        verdict. Only name a singer you are genuinely confident exists and is from or strongly \
        associated with that region; if you are not confident, say so plainly in the `singer` field.
        """
        let userText = """
        My measured vocal range is \(profile.lowName) to \(profile.highName) \
        (\(profile.rangeSemitones) semitones), roughly classified as \(profile.voiceType.rawValue). \
        My region is \(profile.regionName). Which well-known singer from my region do I match?
        """
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "singer": ["type": "string"],
                "reason": ["type": "string"],
                "voiceTypeNote": ["type": "string"],
            ],
            "required": ["singer", "reason", "voiceTypeNote"],
        ]
        return [
            "model": model,
            "max_tokens": 600,
            "system": prompt,
            "messages": [["role": "user", "content": userText]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]],
        ]
    }

    // MARK: Request construction

    /// Clarinet system prompt — a warm, honest teacher who reasons only from the
    /// measured data and plays along with the "guess the gear" game.
    private static let clarinetPrompt = """
    You are an expert clarinet teacher with decades of orchestral and pedagogical experience. \
    A student has played a two-octave scale and the app measured their intonation (in cents, \
    written reference — positive is sharp), tempo accuracy, tone descriptors, and per-register \
    tendencies. All pitches are written for a B♭ clarinet.

    Give feedback that is specific, encouraging, and genuinely useful. Ground every claim in the \
    numbers you are given — never invent measurements. If the data is sparse (few evaluated notes), \
    say so and keep claims modest. Lead with what the student did well, then give concrete, \
    physical fixes for real issues (embouchure, air support, reed strength, voicing, instrument \
    assembly, pad leaks). When a specific written note is consistently off, name it and explain the \
    common cause for the clarinet (e.g. throat tones run stuffy and sharp; altissimo needs faster air). \
    Have fun with the instrument and reed guesses (`clarinetGuess`, `reedGuess`), but make clear they \
    are playful inferences from tone color, not certainties. End on something motivating.

    Be concise. Put the single most important takeaway in `summary` as 1–2 short sentences (a TL;DR \
    the student reads first). Keep `headline` punchy, each `positives`/`issues` item to one sentence, \
    and limit `issues` to the 2–3 that matter most. Do not pad.

    For `references`, only list established, real resources (method books or well-known pedagogy sites) \
    and link to a STABLE page you are confident exists — an official homepage or a specific, real video \
    with a watch URL. NEVER link to a YouTube channel or `/user/` page, and never invent a URL. If you \
    are not certain a link is live and correct, omit it. When in doubt, return an empty `references` array.
    """

    /// Voice system prompt — an expert vocal coach who also offers a best-effort
    /// local singer match for the measured range.
    private static let voicePrompt = """
    You are an expert vocal coach and voice teacher with decades of experience across classical and \
    contemporary styles. A singer has sung a two-octave scale and the app measured their intonation \
    (in cents, concert pitch — positive is sharp), tempo accuracy, tone descriptors (breathiness, \
    warmth, brightness, vibrato rate and extent, steadiness), per-zone tendencies, and — if they ran \
    the range finder — their measured vocal range and a rough voice-type classification.

    Give feedback that is specific, encouraging, and genuinely useful. Ground every claim in the \
    numbers you are given — never invent measurements. If the data is sparse (few evaluated notes) or \
    the range was not measured, say so and keep claims modest. Lead with what the singer did well, then \
    give concrete, physical fixes for real issues (breath support, onset, placement/resonance, vowel \
    shaping, managing the passaggio, straight-tone vs. vibrato). When a specific note is consistently \
    off, name it and explain a likely cause. In `voiceType` comment briefly on their classification \
    (make clear it is a rough inference), and in `rangeComment` discuss their measured range.

    For `singerMatch`, name ONE well-known singer from the user's locale (region: "\("%REGION%")") whose \
    tessitura/vocal range is comparable, and say in one sentence why. Only name a real, well-known \
    singer you are confident exists and is from or strongly associated with that region; present it as \
    a playful best-effort match, not a verdict. If you are not confident, say so plainly in the field.

    Be concise. Put the single most important takeaway in `summary` as 1–2 short sentences (a TL;DR the \
    singer reads first). Keep `headline` punchy, each `positives`/`issues` item to one sentence, and \
    limit `issues` to the 2–3 that matter most. Do not pad.

    For `references`, only list established, real resources and link to a STABLE page you are confident \
    exists — an official homepage or a specific, real video with a watch URL. NEVER link to a YouTube \
    channel or `/user/` page, and never invent a URL. If you are not certain a link is live and correct, \
    omit it. When in doubt, return an empty `references` array.
    """

    private static func systemPrompt(for instrument: InstrumentKind, region: String) -> String {
        switch instrument {
        case .clarinet: return clarinetPrompt
        case .voice: return voicePrompt.replacingOccurrences(of: "%REGION%", with: region.isEmpty ? "unspecified" : region)
        }
    }

    private static func requestBody(reportJSON: String, instrument: InstrumentKind, region: String) -> [String: Any] {
        return [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt(for: instrument, region: region),
            "messages": [
                [
                    "role": "user",
                    "content": """
                    Here is the measured analysis of my scale run as JSON. Please coach me.

                    \(reportJSON)
                    """,
                ]
            ],
            "output_config": ["format": ["type": "json_schema", "schema": outputSchema(for: instrument)]],
        ]
    }

    /// JSON schema that constrains Claude's reply to a `CoachingFeedback`. The
    /// instrument-specific "fun" fields are swapped in per instrument so the
    /// model is required to fill exactly the ones we render.
    private static func outputSchema(for instrument: InstrumentKind) -> [String: Any] {
        var properties: [String: Any] = [
            "headline": ["type": "string"],
            "summary": ["type": "string"],
            "positives": ["type": "array", "items": ["type": "string"]],
            "issues": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "area": ["type": "string"],
                        "tip": ["type": "string"],
                    ],
                    "required": ["area", "tip"],
                ],
            ],
            "problemNoteComment": ["type": "string"],
            "styleComparison": ["type": "string"],
            "encouragement": ["type": "string"],
            "references": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "title": ["type": "string"],
                        "url": ["type": "string"],
                    ],
                    "required": ["title", "url"],
                ],
            ],
        ]

        var required = ["headline", "summary", "positives", "issues", "problemNoteComment",
                        "styleComparison", "encouragement", "references"]

        switch instrument {
        case .clarinet:
            properties["clarinetGuess"] = ["type": "string"]
            properties["reedGuess"] = ["type": "string"]
            required += ["clarinetGuess", "reedGuess"]
        case .voice:
            properties["voiceType"] = ["type": "string"]
            properties["rangeComment"] = ["type": "string"]
            properties["singerMatch"] = ["type": "string"]
            required += ["voiceType", "rangeComment", "singerMatch"]
        }

        return [
            "type": "object",
            "additionalProperties": false,
            "properties": properties,
            "required": required,
        ]
    }

    // MARK: Encoding / decoding

    private static func encodeReport(_ report: ToneReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        return String(decoding: data, as: UTF8.self)
    }

    private static func parse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoachError.decoding("Response was not a JSON object")
        }
        if let stop = root["stop_reason"] as? String, stop == "refusal" {
            throw CoachError.refusal
        }
        guard let content = root["content"] as? [[String: Any]] else {
            throw CoachError.emptyResponse
        }
        guard let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let textData = text.data(using: .utf8) else {
            throw CoachError.emptyResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: textData)
        } catch {
            throw CoachError.decoding(error.localizedDescription)
        }
    }

    private static func errorMessage(from data: Data) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(decoding: data, as: UTF8.self)
    }
}
