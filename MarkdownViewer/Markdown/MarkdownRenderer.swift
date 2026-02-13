import Foundation
import Markdown

struct OutlineItem: Identifiable {
    let id = UUID()
    let title: String
    let level: Int
    let anchorID: String
}

struct RenderedMarkdown {
    let html: String
    let outline: [OutlineItem]
}

struct HeadingSlugger {
    private var counts: [String: Int] = [:]

    mutating func slug(for title: String) -> String {
        let base = slugify(title)
        let key = base.isEmpty ? "section" : base
        let count = counts[key, default: 0]
        counts[key] = count + 1
        if count == 0 {
            return key
        }
        return "\(key)-\(count)"
    }

    private func slugify(_ title: String) -> String {
        let lowercased = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = ""
        var needsHyphen = false

        for scalar in lowercased.unicodeScalars {
            guard scalar.isASCII else {
                needsHyphen = true
                continue
            }
            let value = scalar.value
            let isLetter = value >= 97 && value <= 122
            let isDigit = value >= 48 && value <= 57
            if isLetter || isDigit {
                if needsHyphen && !result.isEmpty {
                    result.append("-")
                }
                needsHyphen = false
                result.append(Character(scalar))
            } else {
                needsHyphen = true
            }
        }

        return result
    }
}

struct MarkdownRenderer: MarkupWalker {
    var result = ""
    var outline: [OutlineItem] = []
    var slugger = HeadingSlugger()

    mutating func render(_ document: Document) -> RenderedMarkdown {
        result = ""
        outline = []
        slugger = HeadingSlugger()
        for child in document.children {
            visit(child)
        }
        return RenderedMarkdown(html: result, outline: outline)
    }

    mutating func visit(_ markup: any Markup) {
        switch markup {
        case let heading as Heading:
            let title = heading.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let anchorID = slugger.slug(for: title)
            if !title.isEmpty {
                outline.append(OutlineItem(title: title, level: heading.level, anchorID: anchorID))
            }
            result += "<h\(heading.level) id=\"\(anchorID)\">"
            for child in heading.children { visit(child) }
            result += "</h\(heading.level)>\n"
        case let paragraph as Paragraph:
            result += "<p>"
            for child in paragraph.children { visit(child) }
            result += "</p>\n"
        case let text as Markdown.Text:
            result += escapeHTML(text.string)
        case let emphasis as Emphasis:
            result += "<em>"
            for child in emphasis.children { visit(child) }
            result += "</em>"
        case let strong as Strong:
            result += "<strong>"
            for child in strong.children { visit(child) }
            result += "</strong>"
        case let code as InlineCode:
            result += "<code>\(escapeHTML(code.code))</code>"
        case let codeBlock as CodeBlock:
            let lang = codeBlock.language ?? ""
            result += "<pre><code class=\"language-\(lang)\">\(escapeHTML(codeBlock.code))</code></pre>\n"
        case let link as Markdown.Link:
            result += "<a href=\"\(link.destination ?? "")\">"
            for child in link.children { visit(child) }
            result += "</a>"
        case let image as Markdown.Image:
            let alt = image.plainText
            result += "<img src=\"\(image.source ?? "")\" alt=\"\(escapeHTML(alt))\">"
        case let list as UnorderedList:
            result += "<ul>\n"
            for child in list.children { visit(child) }
            result += "</ul>\n"
        case let list as OrderedList:
            result += "<ol>\n"
            for child in list.children { visit(child) }
            result += "</ol>\n"
        case let item as ListItem:
            result += "<li>"
            for child in item.children { visit(child) }
            result += "</li>\n"
        case let quote as BlockQuote:
            if let alertType = detectAlertType(in: quote) {
                let typeLower = alertType.lowercased()
                result += "<div class=\"markdown-alert markdown-alert-\(typeLower)\">\n"
                result += "<p class=\"markdown-alert-title\">\(alertIcon(for: alertType))\(alertTitle(for: alertType))</p>\n"
                var isFirst = true
                for child in quote.children {
                    if isFirst, let paragraph = child as? Paragraph {
                        isFirst = false
                        visitAlertFirstParagraph(paragraph)
                    } else {
                        visit(child)
                    }
                }
                result += "</div>\n"
            } else {
                result += "<blockquote>\n"
                for child in quote.children { visit(child) }
                result += "</blockquote>\n"
            }
        case is ThematicBreak:
            result += "<hr>\n"
        case is SoftBreak:
            result += " "
        case is LineBreak:
            result += "<br>\n"
        case let table as Markdown.Table:
            result += "<table>\n"
            let head = table.head
            result += "<thead><tr>\n"
            for cell in head.cells {
                result += "<th>"
                for child in cell.children { visit(child) }
                result += "</th>\n"
            }
            result += "</tr></thead>\n"
            result += "<tbody>\n"
            for row in table.body.rows {
                result += "<tr>\n"
                for cell in row.cells {
                    result += "<td>"
                    for child in cell.children { visit(child) }
                    result += "</td>\n"
                }
                result += "</tr>\n"
            }
            result += "</tbody></table>\n"
        case let strikethrough as Strikethrough:
            result += "<del>"
            for child in strikethrough.children { visit(child) }
            result += "</del>"
        case let inlineHTML as InlineHTML:
            result += escapeHTML(inlineHTML.rawHTML)
        case let htmlBlock as HTMLBlock:
            result += escapeHTML(htmlBlock.rawHTML)
            result += "\n"
        default:
            for child in markup.children {
                visit(child)
            }
        }
    }

    // MARK: - GitHub-style alert helpers

    private func detectAlertType(in quote: BlockQuote) -> String? {
        guard let firstParagraph = quote.children.first(where: { $0 is Paragraph }) as? Paragraph,
              let firstText = firstParagraph.children.first(where: { $0 is Markdown.Text }) as? Markdown.Text else {
            return nil
        }
        let text = firstText.string.trimmingCharacters(in: .whitespaces)
        let alertTypes = ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"]
        for type in alertTypes {
            if text == "[!\(type)]" {
                return type
            }
        }
        return nil
    }

    private mutating func visitAlertFirstParagraph(_ paragraph: Paragraph) {
        let children = Array(paragraph.children)
        var startIndex = 0
        // Skip the [!TYPE] text node
        if let first = children.first as? Markdown.Text,
           first.string.trimmingCharacters(in: .whitespaces).hasPrefix("[!") {
            startIndex = 1
            // Also skip a following SoftBreak
            if startIndex < children.count, children[startIndex] is SoftBreak {
                startIndex += 1
            }
        }
        let remaining = children[startIndex...]
        if !remaining.isEmpty {
            result += "<p>"
            for child in remaining { visit(child) }
            result += "</p>\n"
        }
    }

    private func alertTitle(for type: String) -> String {
        switch type {
        case "NOTE": return "Note"
        case "TIP": return "Tip"
        case "IMPORTANT": return "Important"
        case "WARNING": return "Warning"
        case "CAUTION": return "Caution"
        default: return type.capitalized
        }
    }

    private func alertIcon(for type: String) -> String {
        let path: String
        switch type {
        case "NOTE":
            path = "M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"
        case "TIP":
            path = "M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.084-.1-.173-.205-.268-.32C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319-.207.245-.383.453-.541.681-.208.3-.33.565-.37.847a.751.751 0 0 1-1.485-.212c.084-.593.337-1.078.621-1.489.203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5ZM6 15.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1-.75-.75Z"
        case "IMPORTANT":
            path = "M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm7 2.25v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 9a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"
        case "WARNING":
            path = "M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"
        case "CAUTION":
            path = "M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"
        default:
            path = ""
        }
        return "<svg viewBox=\"0 0 16 16\" width=\"16\" height=\"16\" aria-hidden=\"true\"><path d=\"\(path)\"></path></svg>"
    }

    // MARK: - HTML escaping

    private func escapeHTML(_ string: String) -> String {
        var result = ""
        var index = string.startIndex

        while index < string.endIndex {
            let character = string[index]
            switch character {
            case "&":
                if let semiIndex = string[index...].firstIndex(of: ";") {
                    let entity = string[index...semiIndex]
                    if isHTMLEntity(entity) {
                        result.append(contentsOf: entity)
                        index = string.index(after: semiIndex)
                        continue
                    }
                }
                result.append("&amp;")
            case "<":
                result.append("&lt;")
            case ">":
                result.append("&gt;")
            case "\"":
                result.append("&quot;")
            default:
                result.append(character)
            }
            index = string.index(after: index)
        }

        return result
    }

    private func isHTMLEntity(_ entity: Substring) -> Bool {
        guard entity.first == "&", entity.last == ";" else { return false }
        let name = entity.dropFirst().dropLast()
        guard !name.isEmpty else { return false }

        if name.first == "#" {
            let number = name.dropFirst()
            guard !number.isEmpty else { return false }
            if number.first == "x" || number.first == "X" {
                return number.dropFirst().unicodeScalars.allSatisfy { scalar in
                    let value = scalar.value
                    return (value >= 48 && value <= 57)
                        || (value >= 65 && value <= 70)
                        || (value >= 97 && value <= 102)
                }
            }
            return number.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
        }

        return name.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }
}
