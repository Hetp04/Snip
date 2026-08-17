import Foundation
import AppKit

/// Lightweight local code detector. Keeping this native avoids loading a large
/// JavaScript bundle for every copied item and prevents JavaScriptCore errors.
struct CodeLanguageDetector {
    static func detectLanguage(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }
        let sample = String(trimmed.prefix(5_000)).lowercased()

        let hasSwiftSyntax = sample.range(
            of: #"\b(?:import\s+(?:swift|swiftui|foundation|appkit|uikit)|func\s+[a-z_]\w*\s*\(|@(?:state|binding|published|mainactor|observable)|(?:let|var)\s+[a-z_]\w*\s*:\s*[a-z_]\w*|(?:struct|enum|protocol|extension)\s+[a-z_]\w*)"#,
            options: .regularExpression
        ) != nil
        if hasSwiftSyntax { return "Swift" }
        if sample.contains("<html") || sample.contains("<!doctype html") { return "HTML" }
        if sample.range(of: #"(?:^|[}\s])[a-z-]+\s*:\s*[^;{}]+;"#, options: .regularExpression) != nil { return "CSS" }
        if sample.contains("select ") && (sample.contains(" from ") || sample.contains("insert into ")) { return "SQL" }
        if sample.contains("def ") || sample.contains("import ") && sample.contains("print(") { return "Python" }
        // Do not classify prose as JavaScript just because it contains a word
        // such as "let". Require an actual declaration, function, arrow, or
        // module/console syntax.
        let hasJavaScriptSyntax = sample.range(
            of: #"\b(?:function\s+[a-z_$][\w$]*\s*\(|(?:const|let|var)\s+[a-z_$][\w$]*\s*=|[a-z_$][\w$]*\s*=>|console\.|(?:import|export)\s+(?:[\w*{]))"#,
            options: .regularExpression
        ) != nil
        if hasJavaScriptSyntax { return "JavaScript" }
        if sample.contains("#include") || sample.contains("std::") { return "C++" }
        if sample.contains("public class ") || sample.contains("system.out.") { return "Java" }
        if sample.hasPrefix("{") || sample.hasPrefix("[") {
            if (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil { return "JSON" }
        }
        if sample.contains("#!/bin/") || sample.contains("#!/usr/bin/env bash") { return "Bash" }
        // A final, conservative fallback covers editors that copy a language
        // we do not explicitly identify (for example Rust or Kotlin) without
        // ever mistaking ordinary multi-line prose for code.
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count > 1,
           sample.range(of: #"(?:[{};]|\b(?:return|throw|new)\b|=>)"#, options: .regularExpression) != nil,
           sample.range(of: #"(?:\(|=|:)"#, options: .regularExpression) != nil {
            return "Code"
        }
        return nil
    }
}

/// Applies a small, dependency-free syntax theme when an editor only places
/// plain text on the pasteboard. This is deliberately separate from clipboard
/// capture: copied text remains byte-for-byte unchanged and source-provided
/// RTF/HTML formatting still takes precedence.
enum CodeSyntaxHighlighter {
    static func highlightedText(
        _ text: String,
        language: String?,
        fontSize: CGFloat,
        fallbackColor: NSColor
    ) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: fallbackColor]
        )
        guard !text.isEmpty, language != nil else { return result }

        let fullRange = NSRange(text.startIndex..., in: text)
        let keywordColor = NSColor(calibratedRed: 0.53, green: 0.18, blue: 0.61, alpha: 1)
        let typeColor = NSColor(calibratedRed: 0.12, green: 0.37, blue: 0.72, alpha: 1)
        let literalColor = NSColor(calibratedRed: 0.72, green: 0.25, blue: 0.16, alpha: 1)
        let commentColor = NSColor(calibratedRed: 0.34, green: 0.43, blue: 0.32, alpha: 1)

        apply(#"\b(?:actor|as|async|await|break|case|catch|class|const|continue|default|defer|do|else|enum|export|extension|fallthrough|final|for|func|guard|if|import|in|init|internal|let|mutating|nil|nonisolated|open|operator|override|private|protocol|public|repeat|return|self|static|struct|subscript|super|switch|throw|throws|try|typealias|var|weak|where|while|with|yield)\b"#, color: keywordColor, in: result, range: fullRange)
        apply(#"\b(?:Any|AnyObject|Bool|Character|Data|Date|Double|Error|Float|Int|NS[A-Z]\w*|Optional|Result|Set|String|UInt|URL|UUID|Void|[A-Z][A-Za-z0-9_]*)\b"#, color: typeColor, in: result, range: fullRange)
        apply(#"\b(?:true|false|null|undefined)\b|\b\d+(?:\.\d+)?\b"#, color: literalColor, in: result, range: fullRange)

        // Apply strings and comments last so their contents do not get
        // recoloured as keywords or types.
        apply(#"(?s)/\*.*?\*/|//[^\n]*|(?m)^\s*#[^\n]*"#, color: commentColor, in: result, range: fullRange)
        apply(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: literalColor, in: result, range: fullRange)
        return result
    }

    private static func apply(_ pattern: String, color: NSColor, in text: NSMutableAttributedString, range: NSRange) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        for match in expression.matches(in: text.string, range: range) {
            text.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
