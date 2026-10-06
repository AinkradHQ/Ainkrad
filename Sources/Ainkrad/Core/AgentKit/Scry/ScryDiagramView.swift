import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI
import WebKit

/// Which concrete branch `ScryDiagramView` will render for a given element.
/// A pure, synchronous seam over the kind/body dispatch logic so the routing
/// itself is unit-testable without spinning up WebKit.
enum ScryDiagramRoute: Equatable {
    case diagram(source: String)
    case diagramFallback
    case chart(bars: [ScryChartBar])
    case chartFallback
}

enum ScryDiagramRouting {
    static func route(for element: ScryElement) -> ScryDiagramRoute {
        switch element.kind {
        case .chart:
            let bars = ScryChartParse.bars(from: element.body)
            return bars.isEmpty ? .chartFallback : .chart(bars: bars)
        default:
            let source = element.body.trimmingCharacters(in: .whitespacesAndNewlines)
            return source.isEmpty ? .diagramFallback : .diagram(source: source)
        }
    }
}

/// Routes `.diagram` (mermaid, rendered via `WKWebView`) and `.chart`
/// (native shape-drawn bars) scry elements. This is the ONE approved web
/// surface in the app — every other element on the canvas, and every part
/// of this view besides the mermaid host itself, is native SwiftUI per the
/// Cardinal HUD design language. Malformed data for either kind degrades to
/// a preformatted `AinkradCodeBlock` fallback card — never a crash, and
/// never takes any other scry element down with it.
@MainActor
struct ScryDiagramView: View {
    @Environment(\.ainkradSkin) private var skin
    let element: ScryElement
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        switch ScryDiagramRouting.route(for: element) {
        case .diagram(let source):
            MermaidDiagramHost(source: source)
        case .diagramFallback:
            fallback(caption: "Diagram preview pending", language: "mermaid")
        case .chart(let bars):
            ScryChartView(bars: bars)
        case .chartFallback:
            fallback(caption: "Chart data unavailable", language: "csv")
        }
    }

    private func fallback(caption: String, language: String) -> some View {
        VStack(alignment: .leading, spacing: skin.spacing.xs) {
            Text(caption).font(AinkradFont.display(11)).foregroundStyle(theme.foreground.opacity(skin.opacity.o50))
            AinkradCodeBlock(element.body, language: language)
        }
    }
}

/// Owns the mermaid render-error state: while rendering (or once it
/// succeeds) it shows the `WKWebView`; on a reported failure it swaps to a
/// native inline error card and never shows the web view again for this
/// element instance.
private struct MermaidDiagramHost: View {
    let source: String
    @Environment(\.ainkradTheme) private var theme
    @State private var renderError: String?

    var body: some View {
        Group {
            if let renderError {
                ScryErrorCard(message: renderError, label: "Diagram render error")
            } else {
                MermaidWebView(source: source, theme: theme) { error in
                    renderError = error
                }
            }
        }
        // A later `scry_render` can correct a previously-bad diagram body
        // in place (stable element id, new `source`). Without this, once
        // `renderError` is set the `Group` above permanently pins the error
        // branch and the web view is never shown again for this element
        // instance, even though `MermaidWebView.updateNSView` would happily
        // reload the corrected source. Reset on every source change so a
        // fix has a chance to render; if the NEW source also fails,
        // `onError` re-populates `renderError` from the fresh load.
        .onChange(of: source) { _, _ in
            renderError = nil
        }
    }
}

/// `NSViewRepresentable` hosting a `WKWebView` that renders `source` as a
/// mermaid diagram, dark-themed to match the HUD's accent/foreground
/// theme colours. The bundled `mermaid.min.js` (Resources/) is inlined into the
/// loaded HTML so no on-disk file access is needed at render time. Any
/// parse/render failure — thrown synchronously by `mermaid.parse`, rejected
/// by the `mermaid.render` promise, or an uncaught JS error — is posted back
/// through a `WKScriptMessageHandler` bridge and surfaced via `onError`;
/// this view never lets a bad diagram body crash the host app.
private struct MermaidWebView: NSViewRepresentable {
    let source: String
    let theme: HostThemeTokens
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onError: onError) }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "mermaidBridge")
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = NSColor(theme.surfaceElevated)
        load(into: webView, context: context)
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // Conventional WKWebView teardown: drop the JS bridge so the
        // controller doesn't retain the coordinator past this view's life,
        // and stop any in-flight load.
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.stopLoading()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // `updateNSView` fires on every SwiftUI update pass of this view,
        // including ones driven by unrelated state changes on the canvas
        // (e.g. `onContinuousHover`-driven parallax on mouse move) — the
        // `NSViewRepresentable` itself is reused across those passes, it is
        // NOT recreated per update. Only reload the ~3.4MB mermaid HTML when
        // the diagram source or theme actually changed since the last load;
        // otherwise this would reload (and visibly flash) on every mouse move.
        guard
            context.coordinator.lastLoaded?.source != source
                || context.coordinator.lastLoaded?.theme != theme
        else {
            return
        }
        load(into: webView, context: context)
    }

    private func load(into webView: WKWebView, context: Context) {
        guard let jsURL = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
            let js = try? String(contentsOf: jsURL, encoding: .utf8)
        else {
            onError("mermaid.min.js resource not found in app bundle")
            return
        }
        context.coordinator.lastLoaded = (source, theme)
        webView.loadHTMLString(Self.html(js: js, source: source, theme: theme), baseURL: nil)
    }

    private static func html(js: String, source: String, theme: HostThemeTokens) -> String {
        let escapedSource =
            source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
        let bg = theme.surfaceElevated.hexString ?? "1A2233"
        let fg = theme.foreground.hexString ?? "E2E8F0"
        let primary = theme.accentPrimary.hexString ?? "2563EB"
        let secondary = theme.accentSecondary.hexString ?? "22D3EE"
        return """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <style>
              html, body { margin: 0; padding: 0; background: #\(bg); overflow: auto; }
              #diagram { display: flex; align-items: center; justify-content: center; padding: 8px; }
              #diagram svg { max-width: 100%; height: auto; }
            </style>
            </head>
            <body>
            <div id="diagram"></div>
            <script>\(js)</script>
            <script>
            (function () {
              function reportError(err) {
                var message = (err && err.message) ? err.message : String(err);
                if (window.webkit && window.webkit.messageHandlers.mermaidBridge) {
                  window.webkit.messageHandlers.mermaidBridge.postMessage(message);
                }
              }
              window.onerror = function (message) { reportError(message); return true; };
              try {
                window.mermaid.initialize({
                  startOnLoad: false,
                  theme: "dark",
                  themeVariables: {
                    background: "#\(bg)",
                    primaryColor: "#\(primary)",
                    primaryTextColor: "#\(fg)",
                    primaryBorderColor: "#\(secondary)",
                    lineColor: "#\(secondary)",
                    textColor: "#\(fg)"
                  }
                });
                var source = `\(escapedSource)`;
                window.mermaid.render("ainkradMermaidDiagram", source)
                  .then(function (result) {
                    document.getElementById("diagram").innerHTML = result.svg;
                  })
                  .catch(function (err) { reportError(err); });
              } catch (err) {
                reportError(err);
              }
            })();
            </script>
            </body>
            </html>
            """
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onError: (String) -> Void
        /// The `(source, theme)` pair last loaded into the web view, used
        /// by `updateNSView` to skip a reload when neither changed.
        var lastLoaded: (source: String, theme: HostThemeTokens)?
        init(onError: @escaping (String) -> Void) { self.onError = onError }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            onError((message.body as? String) ?? "unknown mermaid render error")
        }
    }
}
