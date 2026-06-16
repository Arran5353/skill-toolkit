/// Lightweight, zero-dependency syntax tokenizer for code block highlighting.
///
/// Lossless guarantee: concatenating all returned token `.text` values in order
/// reproduces the original input string exactly.

public enum TokenKind: Equatable, Sendable {
    case plain, keyword, string, comment, number, type
}

public struct SyntaxToken: Equatable, Sendable {
    public let text: String
    public let kind: TokenKind
    public init(text: String, kind: TokenKind) {
        self.text = text
        self.kind = kind
    }
}

public struct SyntaxHighlighter {

    // MARK: - Keyword sets

    private static let swiftKeywords: Set<String> = [
        "as", "associatedtype", "break", "case", "catch", "class", "continue",
        "default", "defer", "deinit", "do", "else", "enum", "extension",
        "fallthrough", "false", "fileprivate", "final", "for", "func", "guard",
        "if", "import", "in", "indirect", "infix", "init", "inout", "internal",
        "is", "lazy", "let", "mutating", "nil", "nonmutating", "open",
        "operator", "optional", "override", "postfix", "precedencegroup",
        "prefix", "private", "protocol", "public", "required", "rethrows",
        "return", "self", "Self", "some", "static", "struct", "subscript",
        "super", "switch", "throw", "throws", "true", "try", "typealias",
        "unowned", "var", "weak", "where", "while", "async", "await", "actor",
        "isolated", "nonisolated", "distributed", "consume", "copy", "discard",
        "borrow", "borrowing", "consuming", "sending"
    ]

    private static let jsKeywords: Set<String> = [
        "abstract", "arguments", "async", "await", "boolean", "break", "byte",
        "case", "catch", "char", "class", "const", "continue", "debugger",
        "default", "delete", "do", "double", "else", "enum", "eval", "export",
        "extends", "false", "final", "finally", "float", "for", "from",
        "function", "goto", "if", "implements", "import", "in", "instanceof",
        "int", "interface", "let", "long", "native", "new", "null", "of",
        "package", "private", "protected", "public", "return", "short",
        "static", "super", "switch", "synchronized", "this", "throw", "throws",
        "transient", "true", "try", "type", "typeof", "undefined", "var",
        "void", "volatile", "while", "with", "yield"
    ]

    private static let pythonKeywords: Set<String> = [
        "False", "None", "True", "and", "as", "assert", "async", "await",
        "break", "class", "continue", "def", "del", "elif", "else", "except",
        "finally", "for", "from", "global", "if", "import", "in", "is",
        "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try",
        "while", "with", "yield"
    ]

    private static let bashKeywords: Set<String> = [
        "alias", "bg", "bind", "break", "builtin", "caller", "case", "cd",
        "command", "compgen", "complete", "compopt", "continue", "declare",
        "dirs", "disown", "do", "done", "echo", "elif", "else", "enable",
        "esac", "eval", "exec", "exit", "export", "false", "fc", "fg", "fi",
        "for", "function", "getopts", "hash", "help", "history", "if", "in",
        "jobs", "kill", "let", "local", "logout", "mapfile", "popd",
        "printf", "pushd", "pwd", "read", "readarray", "readonly", "return",
        "select", "set", "shift", "shopt", "source", "then", "time", "times",
        "trap", "true", "type", "typeset", "ulimit", "umask", "unalias",
        "unset", "until", "wait", "while"
    ]

    private static let jsonKeywords: Set<String> = ["true", "false", "null"]

    private static let genericKeywords: Set<String> =
        swiftKeywords
            .union(["function", "var", "let", "const", "return", "if", "else",
                    "for", "while", "class", "import", "from", "export",
                    "true", "false", "null", "nil", "void", "new", "this",
                    "super", "self", "static", "public", "private", "protected"])

    private static func keywords(for language: String?) -> Set<String> {
        switch language?.lowercased() {
        case "swift":                         return swiftKeywords
        case "js", "javascript", "ts", "typescript": return jsKeywords
        case "python", "py":                  return pythonKeywords
        case "bash", "sh", "shell", "zsh":   return bashKeywords
        case "json":                          return jsonKeywords
        default:                              return genericKeywords
        }
    }

    // MARK: - Tokenizer

    /// Tokenizes `code` for the given language hint (nil/unknown => generic).
    /// Concatenating token.text in order MUST reproduce `code` exactly (lossless).
    public static func tokenize(_ code: String, language: String?) -> [SyntaxToken] {
        let kws = keywords(for: language)
        let useHashComments = isHashCommentLanguage(language)
        var tokens: [SyntaxToken] = []
        let scalars = Array(code.unicodeScalars)
        var i = scalars.startIndex  // using Int index into the array
        let end = scalars.endIndex

        // Accumulates plain text; flushed before every classified token
        var plainBuf: [Unicode.Scalar] = []

        func flushPlain() {
            if !plainBuf.isEmpty {
                tokens.append(SyntaxToken(text: String(String.UnicodeScalarView(plainBuf)), kind: .plain))
                plainBuf.removeAll()
            }
        }

        func advance() { i = scalars.index(after: i) }

        func peek(_ offset: Int = 0) -> Unicode.Scalar? {
            let idx = scalars.index(i, offsetBy: offset, limitedBy: scalars.index(before: end)) ?? end
            return idx < end ? scalars[idx] : nil
        }

        func scalar() -> Unicode.Scalar { scalars[i] }

        // Returns true if current position starts with the given 2-char sequence
        func startsWith2(_ a: Unicode.Scalar, _ b: Unicode.Scalar) -> Bool {
            guard i < end, scalars[i] == a else { return false }
            let next = scalars.index(after: i)
            return next < end && scalars[next] == b
        }

        while i < end {
            let c = scalar()

            // ---- Block comment /* ... */
            if startsWith2("/", "*") {
                flushPlain()
                var buf: [Unicode.Scalar] = []
                buf.append(c); advance()
                buf.append(scalar()); advance()
                while i < end {
                    if startsWith2("*", "/") {
                        buf.append(scalar()); advance()
                        buf.append(scalar()); advance()
                        break
                    }
                    buf.append(scalar()); advance()
                }
                tokens.append(SyntaxToken(text: String(String.UnicodeScalarView(buf)), kind: .comment))
                continue
            }

            // ---- Line comment //...
            if startsWith2("/", "/") {
                flushPlain()
                var buf: [Unicode.Scalar] = []
                while i < end && scalar() != "\n" {
                    buf.append(scalar()); advance()
                }
                tokens.append(SyntaxToken(text: String(String.UnicodeScalarView(buf)), kind: .comment))
                continue
            }

            // ---- Hash comment #... (bash/python/yaml etc.)
            if useHashComments && c == "#" {
                flushPlain()
                var buf: [Unicode.Scalar] = []
                while i < end && scalar() != "\n" {
                    buf.append(scalar()); advance()
                }
                tokens.append(SyntaxToken(text: String(String.UnicodeScalarView(buf)), kind: .comment))
                continue
            }

            // ---- String literals: " ' `
            if c == "\"" || c == "'" || c == "`" {
                let quote = c
                flushPlain()
                var buf: [Unicode.Scalar] = []
                buf.append(c); advance()
                while i < end {
                    let ch = scalar()
                    if ch == "\\" && quote != "`" {
                        // escaped character — consume both
                        buf.append(ch); advance()
                        if i < end { buf.append(scalar()); advance() }
                    } else if ch == quote || ch == "\n" {
                        if ch == quote { buf.append(ch); advance() }
                        break
                    } else {
                        buf.append(ch); advance()
                    }
                }
                tokens.append(SyntaxToken(text: String(String.UnicodeScalarView(buf)), kind: .string))
                continue
            }

            // ---- Numbers: integer, float, hex (0x...)
            if isDigit(c) || (c == "." && peek(1) != nil && isDigit(peek(1)!)) {
                flushPlain()
                var buf: [Unicode.Scalar] = []
                // hex?
                if c == "0" && (peek(1) == "x" || peek(1) == "X") {
                    buf.append(c); advance()
                    buf.append(scalar()); advance()
                    while i < end && isHexDigit(scalar()) { buf.append(scalar()); advance() }
                } else {
                    while i < end && isDigit(scalar()) { buf.append(scalar()); advance() }
                    if i < end && scalar() == "." {
                        // peek ahead: must be digit after dot to be a float
                        let next = scalars.index(after: i)
                        if next < end && isDigit(scalars[next]) {
                            buf.append(scalar()); advance()
                            while i < end && isDigit(scalar()) { buf.append(scalar()); advance() }
                        }
                    }
                    // optional exponent e/E
                    if i < end && (scalar() == "e" || scalar() == "E") {
                        let saved = i
                        var expBuf: [Unicode.Scalar] = [scalar()]
                        advance()
                        if i < end && (scalar() == "+" || scalar() == "-") {
                            expBuf.append(scalar()); advance()
                        }
                        if i < end && isDigit(scalar()) {
                            buf += expBuf
                            while i < end && isDigit(scalar()) { buf.append(scalar()); advance() }
                        } else {
                            i = saved // rewind — not a valid exponent
                        }
                    }
                }
                tokens.append(SyntaxToken(text: String(String.UnicodeScalarView(buf)), kind: .number))
                continue
            }

            // ---- Words: keywords, types, or plain identifiers
            if isWordStart(c) {
                var buf: [Unicode.Scalar] = []
                while i < end && isWordContinue(scalar()) {
                    buf.append(scalar()); advance()
                }
                let word = String(String.UnicodeScalarView(buf))
                let kind: TokenKind
                if kws.contains(word) {
                    kind = .keyword
                } else if isCapitalized(word) {
                    kind = .type
                } else {
                    kind = .plain
                }
                flushPlain()
                tokens.append(SyntaxToken(text: word, kind: kind))
                continue
            }

            // ---- Anything else: accumulate as plain
            plainBuf.append(c)
            advance()
        }

        flushPlain()
        return tokens
    }

    // MARK: - Character helpers

    private static func isDigit(_ s: Unicode.Scalar) -> Bool {
        s.value >= 48 && s.value <= 57  // '0'...'9'
    }

    private static func isHexDigit(_ s: Unicode.Scalar) -> Bool {
        isDigit(s)
            || (s.value >= 65 && s.value <= 70)   // 'A'...'F'
            || (s.value >= 97 && s.value <= 102)   // 'a'...'f'
    }

    private static func isWordStart(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (v >= 65 && v <= 90)    // A-Z
            || (v >= 97 && v <= 122)   // a-z
            || v == 95                 // _
    }

    private static func isWordContinue(_ s: Unicode.Scalar) -> Bool {
        isWordStart(s) || isDigit(s)
    }

    private static func isCapitalized(_ word: String) -> Bool {
        guard let first = word.unicodeScalars.first else { return false }
        let v = first.value
        return v >= 65 && v <= 90  // A-Z
    }

    private static func isHashCommentLanguage(_ language: String?) -> Bool {
        switch language?.lowercased() {
        case "bash", "sh", "shell", "zsh", "python", "py", "ruby", "rb",
             "yaml", "yml", "toml", "r", "perl", "pl":
            return true
        default:
            return false
        }
    }
}
