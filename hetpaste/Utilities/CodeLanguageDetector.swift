import Foundation
import JavaScriptCore
struct CodeLanguageDetector {
    private static let jsContext: JSContext? = {
        let context = JSContext()
        context?.exceptionHandler = { context, exception in
            print("JavaScriptCore Error: \(exception?.toString() ?? "unknown")")
        }
        guard let url = Bundle.main.url(forResource: "highlight.min", withExtension: "js"),
              let jsCode = try? String(contentsOf: url) else {
            print("CodeLanguageDetector: highlight.min.js not found in bundle!")
            return nil
        }
        context?.evaluateScript(jsCode)
        let wrapper = """
        function detectLanguage(code) {
            try {
                var res = hljs.highlightAuto(code);
                if (res.relevance > 1) {
                    return res.language;
                }
                return null;
            } catch (e) {
                return null;
            }
        }
        """
        context?.evaluateScript(wrapper)
        return context
    }()
    static func detectLanguage(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 10 { return nil }
        let sample = String(trimmed.prefix(5000))
        guard let context = jsContext else { return nil }
        let detectFunc = context.objectForKeyedSubscript("detectLanguage")
        guard let result = detectFunc?.call(withArguments: [sample]) else { return nil }
        if result.isString, let lang = result.toString(), !lang.isEmpty, lang != "null" {
            return formatLanguageName(lang)
        }
        return nil
    }
    private static func formatLanguageName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "javascript", "js": return "JavaScript"
        case "typescript", "ts": return "TypeScript"
        case "cpp", "c++": return "C++"
        case "csharp", "cs": return "C#"
        case "objectivec", "objective-c", "objc": return "Objective-C"
        case "php": return "PHP"
        case "html", "xml": return raw.uppercased()
        case "css", "scss", "less": return raw.uppercased()
        case "sql": return "SQL"
        case "json": return "JSON"
        case "yaml", "yml": return "YAML"
        case "bash", "sh": return "Bash"
        case "markdown", "md": return "Markdown"
        case "x86asm", "armasm", "mipsasm", "avrasm", "assembly", "asm": return "Assembly"
        default: return raw.capitalized
        }
    }
}