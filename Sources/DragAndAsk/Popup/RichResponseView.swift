import SwiftUI
import WebKit

/// Renders a model reply as HTML inside a WKWebView so we get full markdown,
/// tables, and LaTeX math (via marked + KaTeX). The web view re-reports its
/// content height to Swift whenever the body resizes, so resizing the popup
/// makes the bubble grow/shrink correctly instead of clipping content.
struct RichResponseView: View {
    let raw: String
    @State private var height: CGFloat = 24

    var body: some View {
        WebContent(raw: raw, height: $height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: max(height, 24))
    }
}

private struct WebContent: NSViewRepresentable {
    let raw: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Receive height updates from the page's ResizeObserver.
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "heightUpdate")
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsLinkPreview = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent(raw: raw), baseURL: URL(string: "https://cdn.jsdelivr.net"))
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "heightUpdate")
    }

    private func htmlContent(raw: String) -> String {
        let jsLiteral: String = {
            guard let data = try? JSONEncoder().encode(raw),
                  let str = String(data: data, encoding: .utf8)
            else { return "\"\"" }
            return str
        }()

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/marked@12.0.0/marked.min.js"></script>
        <style>
        :root { color-scheme: light dark; }
        html, body {
            margin: 0;
            padding: 0;
            overflow: hidden;   /* WebView height matches body; we never need to scroll the page itself */
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 14px;
            line-height: 1.55;
            color: #1d1d1f;
            background: transparent;
            word-wrap: break-word;
            overflow-wrap: anywhere;
            -webkit-text-size-adjust: 100%;
        }

        /* Thin auto-hiding scrollbars for the only elements that can overflow horizontally:
           code blocks, tables, KaTeX displays. Invisible by default, visible on hover. */
        ::-webkit-scrollbar { width: 6px; height: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: transparent; border-radius: 3px; transition: background 0.15s ease; }
        pre:hover::-webkit-scrollbar-thumb,
        table:hover::-webkit-scrollbar-thumb,
        .katex-display:hover::-webkit-scrollbar-thumb { background: rgba(128, 128, 128, 0.45); }
        @media (prefers-color-scheme: dark) {
            pre:hover::-webkit-scrollbar-thumb,
            table:hover::-webkit-scrollbar-thumb,
            .katex-display:hover::-webkit-scrollbar-thumb { background: rgba(220, 220, 220, 0.35); }
        }
        @media (prefers-color-scheme: dark) {
            body { color: #ececec; }
            th, td { border-color: #555 !important; }
            th { background: rgba(255,255,255,0.06) !important; }
            code, pre { background: rgba(255,255,255,0.10) !important; }
        }
        h1 { font-size: 1.35em; margin: 0.6em 0 0.4em; font-weight: 700; }
        h2 { font-size: 1.18em; margin: 0.6em 0 0.4em; font-weight: 700; }
        h3 { font-size: 1.05em; margin: 0.6em 0 0.4em; font-weight: 700; }
        p { margin: 0.4em 0; }
        strong { font-weight: 700; }
        ul, ol { padding-left: 1.5em; margin: 0.4em 0; }
        li { margin: 0.15em 0; }
        a { color: #0366d6; }
        code {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 0.92em;
            background: rgba(0,0,0,0.06);
            padding: 1px 5px;
            border-radius: 3px;
        }
        pre {
            background: rgba(0,0,0,0.06);
            padding: 8px 10px;
            border-radius: 6px;
            overflow-x: auto;
            margin: 0.5em 0;
        }
        pre code { background: none; padding: 0; }
        table {
            border-collapse: collapse;
            margin: 0.6em 0;
            font-size: 0.95em;
            max-width: 100%;
            display: block;
            overflow-x: auto;
        }
        th, td { border: 1px solid #ccc; padding: 5px 9px; text-align: left; vertical-align: top; }
        th { background: rgba(0,0,0,0.04); font-weight: 700; }
        .katex-display { margin: 0.5em 0; overflow-x: auto; overflow-y: hidden; }
        blockquote {
            border-left: 3px solid #ccc;
            padding-left: 10px;
            margin: 0.5em 0;
            color: #555;
        }
        hr { border: none; border-top: 1px solid #ccc; margin: 0.8em 0; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
        window.addEventListener('load', () => {
            const raw = \(jsLiteral);
            const blocks = [];

            let s = raw;
            s = s.replace(/\\$\\$([\\s\\S]+?)\\$\\$/g, (_, p) => {
                blocks.push({d:true, c:p}); return `@@M${blocks.length-1}@@`;
            });
            s = s.replace(/\\\\\\[([\\s\\S]+?)\\\\\\]/g, (_, p) => {
                blocks.push({d:true, c:p}); return `@@M${blocks.length-1}@@`;
            });
            s = s.replace(/\\$([^\\n\\$]+?)\\$/g, (_, p) => {
                blocks.push({d:false, c:p}); return `@@M${blocks.length-1}@@`;
            });
            s = s.replace(/\\\\\\(([\\s\\S]+?)\\\\\\)/g, (_, p) => {
                blocks.push({d:false, c:p}); return `@@M${blocks.length-1}@@`;
            });

            marked.setOptions({ gfm: true, breaks: false });
            let html = marked.parse(s);

            html = html.replace(/@@M(\\d+)@@/g, (m, idx) => {
                const b = blocks[parseInt(idx, 10)];
                if (!b) return m;
                try {
                    return katex.renderToString(b.c, { displayMode: b.d, throwOnError: false });
                } catch (e) {
                    return m;
                }
            });

            document.getElementById('content').innerHTML = html;

            // Report initial height, then keep reporting on every resize/reflow.
            const post = () => {
                const h = document.body.scrollHeight;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heightUpdate) {
                    window.webkit.messageHandlers.heightUpdate.postMessage(h);
                }
            };
            post();
            // ResizeObserver fires on every layout change (width changes when popup resizes).
            const ro = new ResizeObserver(() => post());
            ro.observe(document.body);
            // Some content (KaTeX, images) finalizes layout shortly after load; nudge a few times.
            setTimeout(post, 100);
            setTimeout(post, 400);
            setTimeout(post, 1000);
        });
        </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let heightBinding: Binding<CGFloat>
        init(height: Binding<CGFloat>) { self.heightBinding = height }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "heightUpdate" else { return }
            let raw: CGFloat
            if let n = message.body as? NSNumber {
                raw = CGFloat(n.doubleValue)
            } else if let d = message.body as? Double {
                raw = CGFloat(d)
            } else if let i = message.body as? Int {
                raw = CGFloat(i)
            } else {
                return
            }
            let final = max(raw + 6, 24)
            DispatchQueue.main.async {
                if abs(self.heightBinding.wrappedValue - final) > 1 {
                    self.heightBinding.wrappedValue = final
                }
            }
        }
    }
}
