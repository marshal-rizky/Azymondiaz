import SwiftUI
import WebKit

/// Renders markdown + LaTeX math using KaTeX + marked (loaded from CDN).
/// Requires internet (same as all AI features). Shows raw text as fallback
/// while scripts are loading.
struct MathWebView: UIViewRepresentable {
    let content: String

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = true
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // JSONEncoder handles bare String correctly (produces a quoted JSON string).
        // JSONSerialization requires NSArray/NSDictionary at top level and throws
        // an NSException for plain strings — which Swift's try? does NOT catch → crash.
        guard let jsonData = try? JSONEncoder().encode(content),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
        webView.loadHTMLString(Self.html(jsonStr), baseURL: URL(string: "https://cdn.jsdelivr.net"))
    }

    private static func html(_ jsonContent: String) -> String {
        """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/marked@9.1.6/marked.min.js"></script>
        <style>
        html,body{background:transparent;margin:0}
        body{font-family:-apple-system,sans-serif;font-size:16px;
             padding:8px 12px;word-wrap:break-word;visibility:hidden;
             color:#F0EDE6}
        pre{background:#1C1C1E;padding:8px;border-radius:6px;overflow-x:auto;
            border:1px solid #2A2A2E}
        code{font-family:menlo,monospace;font-size:.88em;background:#1C1C1E;
             padding:1px 4px;border-radius:3px;color:#C9A84C}
        pre code{background:none;padding:0;color:#F0EDE6}
        .katex-display{overflow-x:auto;overflow-y:hidden}
        .katex{color:#F0EDE6}
        </style></head>
        <body><div id="c"></div>
        <script>
        const c=document.getElementById('c');
        c.innerHTML=marked.parse(\(jsonContent));
        renderMathInElement(c,{
          delimiters:[
            {left:'$$',right:'$$',display:true},
            {left:'$',right:'$',display:false},
            {left:'\\\\[',right:'\\\\]',display:true},
            {left:'\\\\(',right:'\\\\)',display:false}
          ],
          throwOnError:false
        });
        document.body.style.visibility='visible';
        </script></body></html>
        """
    }
}
