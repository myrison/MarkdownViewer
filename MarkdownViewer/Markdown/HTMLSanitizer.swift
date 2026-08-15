import Foundation

/// Sanitizes raw HTML coming from a Markdown source before it is injected into the
/// rendered page.
///
/// Markdown documents frequently contain angle-bracket placeholders (`<select>`,
/// `<id>`, `<Department>`) that the CommonMark parser reports as raw HTML. Passing
/// them through untouched lets the browser treat them as real elements: a stray
/// `<select>` swallows the entire remainder of the document, and unknown tags such
/// as `<id>` disappear from the output. Tags outside the allow list are therefore
/// escaped so they render as the literal text the author wrote, while ordinary
/// formatting HTML keeps working.
struct HTMLSanitizer {
    /// Elements that are safe to pass through to the rendered document.
    /// Deliberately excludes script/style/iframe/form controls and any raw-text
    /// element that could swallow the rest of the document.
    private static let allowedTags: Set<String> = [
        "a", "abbr", "b", "bdi", "bdo", "blockquote", "br", "caption", "cite",
        "code", "col", "colgroup", "dd", "del", "details", "dfn", "div", "dl",
        "dt", "em", "figcaption", "figure", "h1", "h2", "h3", "h4", "h5", "h6",
        "hr", "i", "img", "ins", "kbd", "li", "mark", "ol", "p", "picture",
        "pre", "q", "rp", "rt", "ruby", "s", "samp", "small", "span", "strong",
        "sub", "summary", "sup", "table", "tbody", "td", "tfoot", "th", "thead",
        "time", "tr", "u", "ul", "var", "wbr"
    ]

    /// Attributes whose values are URLs and therefore need scheme checking.
    private static let urlAttributes: Set<String> = ["href", "src", "srcset", "xlink:href", "action", "formaction", "data"]

    /// Renders `raw` in a form that cannot restructure the surrounding document.
    static func sanitize(_ raw: String) -> String {
        var output = ""
        var index = raw.startIndex

        while index < raw.endIndex {
            let character = raw[index]
            guard character == "<" else {
                output.append(character)
                index = raw.index(after: index)
                continue
            }

            if let comment = matchComment(in: raw, from: index) {
                // Comments are invisible either way; drop them so an unterminated
                // comment cannot hide the rest of the document.
                index = comment
                continue
            }

            if let tag = parseTag(in: raw, from: index) {
                if allowedTags.contains(tag.name) {
                    output += renderTag(tag)
                } else {
                    output += escapeText(String(raw[index..<tag.end]))
                }
                index = tag.end
                continue
            }

            output += "&lt;"
            index = raw.index(after: index)
        }

        return output
    }

    // MARK: - Tag parsing

    private struct Tag {
        var name: String
        var isClosing: Bool
        var isSelfClosing: Bool
        var attributes: [(name: String, value: String?)]
        var end: String.Index
    }

    /// Returns the index just past `-->` when `index` starts an HTML comment.
    private static func matchComment(in raw: String, from index: String.Index) -> String.Index? {
        guard raw[index...].hasPrefix("<!--") else { return nil }
        guard let range = raw.range(of: "-->", range: index..<raw.endIndex) else { return raw.endIndex }
        return range.upperBound
    }

    private static func parseTag(in raw: String, from start: String.Index) -> Tag? {
        var index = raw.index(after: start)
        guard index < raw.endIndex else { return nil }

        var isClosing = false
        if raw[index] == "/" {
            isClosing = true
            index = raw.index(after: index)
        }

        // Tag name: must start with a letter, as CommonMark requires.
        var name = ""
        guard index < raw.endIndex, raw[index].isLetter else { return nil }
        while index < raw.endIndex, raw[index].isLetter || raw[index].isNumber || raw[index] == "-" {
            name.append(raw[index])
            index = raw.index(after: index)
        }

        var attributes: [(name: String, value: String?)] = []
        var isSelfClosing = false

        while index < raw.endIndex {
            let character = raw[index]

            if character.isWhitespace {
                index = raw.index(after: index)
                continue
            }

            if character == ">" {
                return Tag(
                    name: name.lowercased(),
                    isClosing: isClosing,
                    isSelfClosing: isSelfClosing,
                    attributes: attributes,
                    end: raw.index(after: index)
                )
            }

            if character == "/" {
                isSelfClosing = true
                index = raw.index(after: index)
                continue
            }

            guard let attribute = parseAttribute(in: raw, from: &index) else { return nil }
            attributes.append(attribute)
        }

        // Unterminated tag: treat as literal text rather than guessing.
        return nil
    }

    private static func parseAttribute(in raw: String, from index: inout String.Index) -> (name: String, value: String?)? {
        var name = ""
        while index < raw.endIndex,
              !raw[index].isWhitespace,
              raw[index] != "=",
              raw[index] != ">",
              raw[index] != "/" {
            name.append(raw[index])
            index = raw.index(after: index)
        }
        guard !name.isEmpty else { return nil }

        // Skip whitespace before a possible '='.
        var lookahead = index
        while lookahead < raw.endIndex, raw[lookahead].isWhitespace {
            lookahead = raw.index(after: lookahead)
        }
        guard lookahead < raw.endIndex, raw[lookahead] == "=" else {
            return (name, nil)
        }

        index = raw.index(after: lookahead)
        while index < raw.endIndex, raw[index].isWhitespace {
            index = raw.index(after: index)
        }
        guard index < raw.endIndex else { return (name, "") }

        var value = ""
        let quote = raw[index]
        if quote == "\"" || quote == "'" {
            index = raw.index(after: index)
            while index < raw.endIndex, raw[index] != quote {
                value.append(raw[index])
                index = raw.index(after: index)
            }
            guard index < raw.endIndex else { return nil }
            index = raw.index(after: index)
        } else {
            while index < raw.endIndex, !raw[index].isWhitespace, raw[index] != ">" {
                value.append(raw[index])
                index = raw.index(after: index)
            }
        }

        return (name, value)
    }

    // MARK: - Tag rendering

    private static func renderTag(_ tag: Tag) -> String {
        if tag.isClosing {
            return "</\(tag.name)>"
        }

        var output = "<\(tag.name)"
        for attribute in tag.attributes {
            let name = attribute.name.lowercased()
            guard isAllowedAttribute(name, value: attribute.value) else { continue }
            if let value = attribute.value {
                output += " \(name)=\"\(escapeAttributeValue(value))\""
            } else {
                output += " \(name)"
            }
        }
        output += tag.isSelfClosing ? " />" : ">"
        return output
    }

    private static func isAllowedAttribute(_ name: String, value: String?) -> Bool {
        // Event handlers would run author-supplied script in the viewer.
        if name.hasPrefix("on") { return false }
        if urlAttributes.contains(name) {
            return isSafeURL(value ?? "")
        }
        return true
    }

    private static func isSafeURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return true }
        // A '/', '?' or '#' before the colon means it is a relative URL, not a scheme.
        if let separator = trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#")),
           separator.lowerBound < colonIndex {
            return true
        }
        let scheme = String(trimmed[trimmed.startIndex..<colonIndex])
        if scheme == "data" {
            return trimmed.hasPrefix("data:image/")
        }
        return ["http", "https", "mailto", "tel", "file"].contains(scheme)
    }

    // MARK: - Escaping

    private static func escapeText(_ string: String) -> String {
        var output = ""
        for character in string {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            default: output.append(character)
            }
        }
        return output
    }

    private static func escapeAttributeValue(_ string: String) -> String {
        escapeText(string).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
