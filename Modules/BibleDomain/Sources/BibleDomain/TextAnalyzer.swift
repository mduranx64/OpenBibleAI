//
//  TextAnalyzer.swift
//  BibleDomain
//

/// Turns verse text or a query into keyword-search tokens for one language:
/// words are case- and diacritic-folded (`BibleTextQuery.words`), common and
/// archaic stop words are dropped, and a light suffix stemmer folds number,
/// gender and common verb endings ("ciegos"/"ciega" → "cieg"). Languages
/// without rules keep every folded word.
public struct TextAnalyzer: Hashable, Sendable {
    private enum Language: Hashable, Sendable {
        case english
        case spanish
        case portuguese
        case other
    }

    private let language: Language

    public static let english = TextAnalyzer(language: .english)
    public static let spanish = TextAnalyzer(language: .spanish)
    public static let portuguese = TextAnalyzer(language: .portuguese)

    private init(language: Language) {
        self.language = language
    }

    /// The analyzer for a BCP-47 code such as "en", "es-419" or "pt-BR".
    public init(languageCode: String) {
        let base = languageCode.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? ""
        switch base {
        case "en": language = .english
        case "es": language = .spanish
        case "pt": language = .portuguese
        default: language = .other
        }
    }

    public func tokens(in text: String) -> [String] {
        let words = BibleTextQuery.words(in: text)
        switch language {
        case .english:
            return words.filter { !Self.englishStopWords.contains($0) }.map(Self.englishStem)
        case .spanish:
            return words.filter { !Self.spanishStopWords.contains($0) }.map(Self.spanishStem)
        case .portuguese:
            return words.filter { !Self.portugueseStopWords.contains($0) }.map(Self.portugueseStem)
        case .other:
            return words
        }
    }

    // MARK: - Stemmers

    private static func englishStem(_ word: String) -> String {
        var w = word
        func drop(_ suffix: String, minimumLength: Int) -> Bool {
            guard w.count >= minimumLength, w.hasSuffix(suffix) else { return false }
            w.removeLast(suffix.count)
            return true
        }

        if !(drop("eth", minimumLength: 5) || drop("est", minimumLength: 5)
             || drop("ing", minimumLength: 6) || drop("ed", minimumLength: 5)
             || drop("es", minimumLength: 5)) {
            if w.count > 3, w.hasSuffix("s"),
               !w.hasSuffix("ss"), !w.hasSuffix("us"), !w.hasSuffix("is") {
                w.removeLast()
            }
        }
        if w.count > 3, w.hasSuffix("e") { w.removeLast() }
        return w
    }

    private static func spanishStem(_ word: String) -> String {
        guard !spanishNames.contains(word) else { return word }
        var w = word
        if w.count >= 5, w.hasSuffix("es") {
            w.removeLast(2)
        } else if w.count > 3, w.hasSuffix("s") {
            w.removeLast()
        }
        return romanceEnding(w, suffixes: ["iendo", "ieron", "ando", "aron", "ado", "ada", "ido", "ida"])
    }

    private static func portugueseStem(_ word: String) -> String {
        guard !portugueseNames.contains(word) else { return word }
        var w = word
        if w.hasSuffix("oes") || w.hasSuffix("aes") {
            w.removeLast(3)
            w += "ao"
        } else if w.count >= 5, w.hasSuffix("ais") {
            w.removeLast(3)
            w += "al"
        } else if w.count >= 5, w.hasSuffix("es"), !w.hasSuffix("ees") {
            w.removeLast(2)
        } else if w.count > 3, w.hasSuffix("s") {
            w.removeLast()
        }
        return romanceEnding(w, suffixes: ["ando", "endo", "indo", "aram", "eram", "iram", "ado", "ada", "ido", "ida", "ou"])
    }

    /// Drops the first matching verb ending (keeping at least three letters),
    /// otherwise a final gender vowel.
    private static func romanceEnding(_ word: String, suffixes: [String]) -> String {
        var w = word
        for suffix in suffixes where w.count - suffix.count >= 3 && w.hasSuffix(suffix) {
            w.removeLast(suffix.count)
            return w
        }
        if w.count >= 4, let last = w.last, "aeo".contains(last) {
            w.removeLast()
        }
        return w
    }

    // MARK: - Word lists (folded: lowercase, no diacritics)

    private static let englishStopWords: Set<String> = [
        "a", "about", "after", "again", "all", "also", "am", "an", "and", "any", "are",
        "art", "as", "at", "be", "because", "been", "before", "but", "by", "came", "can",
        "come", "did", "do", "does", "doth", "done", "even", "for", "from", "go", "had",
        "hast", "hath", "have", "he", "her", "here", "him", "his", "how", "i", "if", "in",
        "into", "is", "it", "its", "let", "may", "me", "mine", "my", "no", "nor", "not",
        "now", "o", "of", "on", "one", "or", "our", "out", "said", "saith", "say", "shall",
        "she", "should", "so", "than", "that", "the", "thee", "their", "them", "then",
        "there", "these", "they", "thine", "this", "those", "thou", "thus", "thy", "to",
        "unto", "up", "upon", "us", "was", "we", "went", "were", "what", "when", "where",
        "which", "who", "whom", "whose", "why", "will", "with", "would", "ye", "yet",
        "you", "your"
    ]

    private static let spanishStopWords: Set<String> = [
        "a", "al", "algo", "ante", "asi", "aun", "aunque", "cada", "como", "con", "contra",
        "cual", "cuando", "de", "del", "desde", "dice", "dicho", "dijo", "dijeron", "donde",
        "durante", "e", "el", "ella", "ellas", "ello", "ellos", "en", "entonces", "entre",
        "era", "eran", "es", "esa", "esas", "ese", "eso", "esos", "esta", "estaba", "estan",
        "estas", "este", "esto", "estos", "fue", "fueron", "ha", "habia", "han", "has",
        "hasta", "he", "hay", "la", "las", "le", "les", "lo", "los", "mas", "me", "mi",
        "mis", "muy", "nos", "nosotros", "ni", "no", "o", "os", "para", "pero", "por",
        "porque", "pues", "que", "quien", "se", "sea", "segun", "ser", "si", "sin", "sobre",
        "son", "su", "sus", "tambien", "te", "ti", "tu", "tus", "un", "una", "uno", "unos",
        "vosotros", "y", "ya", "yo"
    ]

    private static let portugueseStopWords: Set<String> = [
        "a", "ao", "aos", "aquela", "aquele", "aqueles", "as", "ate", "com", "como", "da",
        "das", "de", "dela", "dele", "deles", "depois", "disse", "disseram", "diz", "do",
        "dos", "e", "ela", "elas", "ele", "eles", "em", "entao", "entre", "era", "eram",
        "essa", "esse", "esta", "estava", "este", "estes", "eu", "foi", "foram", "ha",
        "isso", "isto", "ja", "lhe", "lhes", "mais", "mas", "me", "meu", "meus", "minha",
        "na", "nao", "nas", "nem", "no", "nos", "nossa", "nosso", "num", "numa", "o", "onde",
        "os", "ou", "para", "pela", "pelas", "pelo", "pelos", "pois", "por", "porque", "quando",
        "que", "quem", "se", "sem", "ser", "seu", "seus", "sobre", "sua", "suas", "tambem",
        "te", "teu", "tu", "tua", "um", "uma", "vos"
    ]

    /// Names that end like plurals and must not be stemmed.
    private static let spanishNames: Set<String> = [
        "dios", "jesus", "moises", "judas", "tomas", "lucas", "marcos", "nicodemo", "lazaro"
    ]

    private static let portugueseNames: Set<String> = [
        "deus", "jesus", "moises", "judas", "tomas", "lucas", "marcos", "lazaro"
    ]
}
