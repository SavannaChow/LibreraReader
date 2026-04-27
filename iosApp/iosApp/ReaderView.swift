import SwiftUI
import WebKit
import PDFKit

struct ReaderSearchResult: Identifiable, Hashable {
    let id: UUID = UUID()
    let displayPage: String
    let snippet: String
    let progress: Double
    let exactScrollTop: Double?
    let pdfPageIndex: Int?
    let pdfPointX: Double?
    let pdfPointY: Double?
}

#if os(macOS)
typealias NativeView = NSView
protocol PlatformRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView
    func updateNSView(_ nsView: NSView, context: Context)
}
#else
typealias NativeView = UIView
protocol PlatformRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView
    func updateUIView(_ uiView: UIView, context: Context)
}
#endif

struct ReaderView: PlatformRepresentable {
    let url: URL
    let rootURL: URL
    let settings: ReaderSettings
    let initialScrollProgress: Double
    let jumpToProgress: Double?
    let jumpToken: UUID?
    let searchJumpResult: ReaderSearchResult?
    let searchJumpToken: UUID?
    let searchQuery: String
    let searchToken: UUID?
    let onSearchResults: ([ReaderSearchResult]) -> Void
    @Binding var scrollProgress: Double
    @Binding var selectedText: String
    
    private var isPDF: Bool {
        url.pathExtension.lowercased() == "pdf"
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ReaderView
        var hasLoadedContent = false
        var savedInitialProgress: Double = 0.0
        var lastAppliedJumpToken: UUID?
        var lastAppliedSearchToken: UUID?
        var lastAppliedSearchJumpToken: UUID?
        var pdfView: PDFView?
        var observers: [Any] = []
        #if os(macOS)
        var keyMonitor: Any?
        #endif
        
        init(_ parent: ReaderView) {
            self.parent = parent
            self.savedInitialProgress = parent.initialScrollProgress
        }
        
        deinit {
            for observer in observers {
                if let noteObserver = observer as? NSObjectProtocol {
                    NotificationCenter.default.removeObserver(noteObserver)
                }
            }
            #if os(macOS)
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
            #endif
        }
        
        // MARK: - WKWebView Delegate
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView Finished Loading")
            hasLoadedContent = true
            
            #if os(iOS)
            webView.evaluateJavaScript("window.focus();", completionHandler: nil)
            webView.becomeFirstResponder()
            webView.scrollView.decelerationRate = .normal
            #endif
            
            parent.applySettings(to: webView, preserveScroll: false)
            
            if savedInitialProgress > 0 {
                let js = """
                (function() {
                    var docHeight = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
                    var viewHeight = window.innerHeight;
                    var scrollTop = \(savedInitialProgress) * (docHeight - viewHeight);
                    window.scrollTo(0, Math.max(0, scrollTop));
                })();
                """
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            
            setupWebViewScrollTracking(webView)
            setupWebViewSelectionTracking(webView)
        }
        
        func setupWebViewScrollTracking(_ webView: WKWebView) {
            // Inject SmoothScroller and scroll tracking
            let js = """
            (function() {
                // Redirect console.log to Swift
                var oldLog = console.log;
                console.log = function(message) {
                    try {
                        window.webkit.messageHandlers.logHandler.postMessage(message);
                    } catch(e) {}
                    oldLog.apply(console, arguments);
                };
                
                console.log("Injecting SmoothScroller...");

                // Prevent multiple injections
                if (window.SmoothScroller) {
                     console.log("SmoothScroller already exists");
                     return;
                }

                class SmoothScroller {
                    constructor() {
                        console.log("SmoothScroller constructor started (Native Smooth)");
                        this.arrowStep = 200; // Pixels per arrow key press
                        
                        // Bind events
                        window.addEventListener('click', this.onClick.bind(this));
                        window.addEventListener('touchstart', this.onTouchStart.bind(this), { passive: false });
                        window.addEventListener('touchend', this.onTouchEnd.bind(this), { passive: false });
                        console.log("Event listeners bound (Native)");
                        
                        // Report progress to Swift
                        this.progressInterval = setInterval(this.reportProgress.bind(this), 200);
                        
                        // Expose to window for external control
                        window.smoothScrollBy = this.scrollBy.bind(this);
                        window.smoothScrollPageDown = this.scrollPageDown.bind(this);
                        window.smoothScrollPageUp = this.scrollPageUp.bind(this);
                        
                        // Also listen for key events directly in webview
                         window.addEventListener('keydown', (e) => {
                            switch(e.key) {
                                case 'ArrowUp':
                                    this.scrollBy(-this.arrowStep);
                                    e.preventDefault();
                                    break;
                                case 'ArrowDown':
                                    this.scrollBy(this.arrowStep);
                                    e.preventDefault();
                                    break;
                                case 'ArrowLeft':
                                    this.scrollPageUp();
                                    e.preventDefault();
                                    break;
                                case 'ArrowRight':
                                    this.scrollPageDown();
                                    e.preventDefault();
                                    break;
                            }
                        });
                    }
                    
                    onTouchStart(e) {
                         if (e.touches.length > 1) return;
                         this.startX = e.touches[0].clientX;
                         this.startY = e.touches[0].clientY;
                         this.startTime = Date.now();
                    }
                    
                    onTouchEnd(e) {
                        if (e.changedTouches.length === 0) return;
                        
                        const endX = e.changedTouches[0].clientX;
                        const endY = e.changedTouches[0].clientY;
                        
                        const diffX = Math.abs(endX - this.startX);
                        const diffY = Math.abs(endY - this.startY);
                        
                        // Check for tap (small movement)
                        if (diffX < 10 && diffY < 10) {
                            console.log("Tap detected (via touch) at: " + endX);
                            this.handleTap(endX, e);
                        }
                    }
                    
                    handleTap(x, e) {
                        if (e.target.closest('a')) {
                             console.log("Tap on link ignored");
                             return;
                        }
                         
                         const width = window.innerWidth;
                         
                         if (x < width * 0.2) {
                             console.log("Touch Tap: Page UP");
                             this.scrollPageUp();
                             if (e.cancelable) e.preventDefault(); 
                         } else if (x > width * 0.8) {
                             console.log("Touch Tap: Page DOWN");
                             this.scrollPageDown();
                             if (e.cancelable) e.preventDefault();
                         }
                    }
                    
                    onClick(e) {
                         // Keep logging just in case
                         console.log("Click detected at: " + e.clientX);
                    }
                    
                    scrollPageDown() {
                        let step = window.innerHeight * 0.9;
                        window.scrollBy({ top: step, behavior: 'smooth' });
                    }
                    
                    scrollPageUp() {
                        let step = window.innerHeight * 0.9;
                        window.scrollBy({ top: -step, behavior: 'smooth' });
                    }

                    scrollBy(amount) {
                         window.scrollBy({ top: amount, behavior: 'smooth' });
                    }

                    reportProgress() {
                        var scrollTop = window.pageYOffset || document.documentElement.scrollTop || 0;
                        var docHeight = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
                        var viewHeight = window.innerHeight;
                        var progress = docHeight > viewHeight ? scrollTop / (docHeight - viewHeight) : 0;
                        try {
                            window.webkit.messageHandlers.scrollHandler.postMessage(progress);
                        } catch(e) {}
                    }
                    
                    // Removed custom physics loop (onWheel, startAnimation, animate, etc.)
                }
                
                window.SmoothScroller = new SmoothScroller();
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
            
            #if os(macOS)
            // Add global key monitor for this webview
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak webView] event in
                    guard let self = self, let webView = webView, webView.window?.isKeyWindow == true else { return event }
                    
                    // Check if focus is inside the window but not necessarily on the webview
                    // If focusing some text input, ignore
                    // But general window focus should trigger scroll
                    
                    switch event.keyCode {
                    case 126: // Up
                        webView.evaluateJavaScript("window.smoothScrollBy && window.smoothScrollBy(-200)", completionHandler: nil)
                        return nil
                    case 125: // Down
                        webView.evaluateJavaScript("window.smoothScrollBy && window.smoothScrollBy(200)", completionHandler: nil)
                        return nil
                    case 123: // Left
                        webView.evaluateJavaScript("window.smoothScrollPageUp && window.smoothScrollPageUp()", completionHandler: nil)
                        return nil
                    case 124: // Right
                        webView.evaluateJavaScript("window.smoothScrollPageDown && window.smoothScrollPageDown()", completionHandler: nil)
                        return nil
                    default:
                        return event
                    }
                }
            }
            #endif
        }

        func setupWebViewSelectionTracking(_ webView: WKWebView) {
            let js = """
            (function() {
                if (window.__libreraSelectionTrackingInstalled) {
                    return;
                }
                window.__libreraSelectionTrackingInstalled = true;

                function reportSelection() {
                    var selection = window.getSelection ? window.getSelection().toString() : "";
                    try {
                        window.webkit.messageHandlers.selectionHandler.postMessage(selection.trim());
                    } catch (e) {}
                }

                document.addEventListener('selectionchange', function() {
                    window.setTimeout(reportSelection, 0);
                });
                document.addEventListener('mouseup', reportSelection);
                document.addEventListener('keyup', reportSelection);
                reportSelection();
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        // MARK: - PDFView Tracking
        
        func setupPDFScrollTracking(_ pdfView: PDFView) {
            self.pdfView = pdfView
            
            #if os(macOS)
            // Listen for scroll notifications from the inner scroll view
            if let scrollView = pdfView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            let observer = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: .main
                ) { [weak self] _ in
                    self?.updatePDFProgress()
                }
            observers.append(observer)

            let selectionObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewSelectionChanged,
                object: pdfView,
                queue: .main
            ) { [weak self, weak pdfView] _ in
                guard let self, let pdfView else { return }
                self.parent.selectedText = pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            observers.append(selectionObserver)
            }
            
            // Handle arrow keys for PDF
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, let pdfView = self.pdfView, pdfView.window?.isKeyWindow == true else { return event }
                
                var isInside = false
                var responder = pdfView.window?.firstResponder
                while responder != nil {
                    if responder === pdfView { isInside = true; break }
                    responder = (responder as? NSView)?.superview
                }
                if !isInside { return event }

                let jumpH = pdfView.visibleRect.width / 2
                let jumpV = pdfView.visibleRect.height / 2
                
                let isFlipped = (pdfView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView)?.subviews.first(where: { $0 is NSClipView })?.isFlipped ?? false
                let vDir: CGFloat = isFlipped ? 1.0 : -1.0
                
                switch event.keyCode {
                case 126: // Up
                    self.scrollPDF(by: CGPoint(x: 0, y: -vDir * jumpV))
                    return nil
                case 125: // Down
                    self.scrollPDF(by: CGPoint(x: 0, y: vDir * jumpV))
                    return nil
                case 123: // Left
                    self.scrollPDF(by: CGPoint(x: -jumpH, y: 0))
                    return nil
                case 124: // Right
                    self.scrollPDF(by: CGPoint(x: jumpH, y: 0))
                    return nil
                default:
                    return event
                }
            }
            #else
            // iOS PDF Scroll Tracking
            let pageObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                self?.updatePDFProgress()
            }
            observers.append(pageObserver)

            let selectionObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewSelectionChanged,
                object: pdfView,
                queue: .main
            ) { [weak self, weak pdfView] _ in
                guard let self, let pdfView else { return }
                self.parent.selectedText = pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            observers.append(selectionObserver)
            
            // For continuous scrolling on iOS, we use KVO on contentOffset
            if let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                let kvo = scrollView.observe(\.contentOffset, options: .new) { [weak self] _, _ in
                    self?.updatePDFProgress()
                }
                observers.append(kvo)
            }
            #endif
        }
        
        #if os(macOS)
        private func scrollPDF(by offset: CGPoint) {
            guard let scrollView = pdfView?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView else { return }
            let contentView = scrollView.contentView
            let currentOrigin = contentView.bounds.origin
            
            let docFrame = scrollView.documentView?.frame ?? .zero
            let viewSize = contentView.bounds.size
            
            var newOrigin = CGPoint(x: currentOrigin.x + offset.x, y: currentOrigin.y + offset.y)
            
            newOrigin.x = max(0, min(newOrigin.x, docFrame.width - viewSize.width))
            let minY = docFrame.minY
            let maxY = docFrame.maxY - viewSize.height
            newOrigin.y = max(minY, min(newOrigin.y, maxY))
            
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.25
            contentView.animator().scroll(to: newOrigin)
            NSAnimationContext.endGrouping()
            
            scrollView.reflectScrolledClipView(contentView)
        }
        #endif
        
        private func updatePDFProgress() {
            guard let pdfView = pdfView else { return }
            
            #if os(macOS)
            guard let scrollView = pdfView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView else { return }
            let visibleRect = scrollView.contentView.documentVisibleRect
            let docHeight = scrollView.documentView?.frame.height ?? 0
            let viewHeight = visibleRect.height
            let progress = docHeight > viewHeight ? 1.0 - (visibleRect.origin.y / (docHeight - viewHeight)) : 0
            #else
            // iOS/iPadOS
            guard let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView else {
                // Fallback to page-based progress
                if let document = pdfView.document {
                    let currentPage = pdfView.currentPage
                    let pageIndex = document.index(for: currentPage ?? document.page(at: 0)!)
                    let progress = Double(pageIndex) / Double(max(1, document.pageCount - 1))
                    DispatchQueue.main.async { self.parent.scrollProgress = progress }
                }
                return
            }
            let contentOffset = scrollView.contentOffset.y
            let contentHeight = scrollView.contentSize.height
            let viewHeight = scrollView.bounds.height
            let progress = contentHeight > viewHeight ? contentOffset / (contentHeight - viewHeight) : 0
            #endif
            
            DispatchQueue.main.async {
                self.parent.scrollProgress = min(1.0, max(0.0, progress))
            }
        }
        
        func restorePDFPosition(_ pdfView: PDFView) {
            guard savedInitialProgress > 0 else { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                #if os(macOS)
                if let scrollView = pdfView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
                    let docHeight = scrollView.documentView?.frame.height ?? 0
                    let viewHeight = scrollView.contentView.documentVisibleRect.height
                    let scrollTop = (1.0 - self.savedInitialProgress) * (docHeight - viewHeight)
                    scrollView.contentView.scroll(to: CGPoint(x: 0, y: scrollTop))
                }
                #else
                if let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                    let contentHeight = scrollView.contentSize.height
                    let viewHeight = scrollView.bounds.height
                    let scrollTop = self.savedInitialProgress * (contentHeight - viewHeight)
                    scrollView.setContentOffset(CGPoint(x: 0, y: scrollTop), animated: false)
                }
                #endif
            }
        }

        func applyJumpIfNeeded(in view: NativeView) {
            guard let jumpToken = parent.jumpToken, lastAppliedJumpToken != jumpToken else {
                return
            }
            lastAppliedJumpToken = jumpToken
            let targetProgress = min(1.0, max(0.0, parent.jumpToProgress ?? 0.0))

            if let pdfView = pdfView {
                scrollPDF(to: targetProgress, pdfView: pdfView)
            } else if let webView = view.subviews.first(where: { $0 is WKWebView }) as? WKWebView {
                scrollWebView(to: targetProgress, webView: webView)
            }
        }

        func applySearchJumpIfNeeded(in view: NativeView) {
            guard let searchJumpToken = parent.searchJumpToken, lastAppliedSearchJumpToken != searchJumpToken else {
                return
            }
            lastAppliedSearchJumpToken = searchJumpToken
            guard let result = parent.searchJumpResult else { return }

            if let pdfView = pdfView {
                scrollPDF(to: result, pdfView: pdfView)
            } else if let webView = view.subviews.first(where: { $0 is WKWebView }) as? WKWebView {
                scrollWebView(to: result, webView: webView)
            }
        }

        private func scrollPDF(to progress: Double, pdfView: PDFView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                #if os(macOS)
                if let scrollView = pdfView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
                    let docHeight = scrollView.documentView?.frame.height ?? 0
                    let viewHeight = scrollView.contentView.documentVisibleRect.height
                    let scrollTop = (1.0 - progress) * max(0, docHeight - viewHeight)
                    scrollView.contentView.animator().scroll(to: CGPoint(x: 0, y: scrollTop))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
                #else
                if let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                    let contentHeight = scrollView.contentSize.height
                    let viewHeight = scrollView.bounds.height
                    let scrollTop = progress * max(0, contentHeight - viewHeight)
                    scrollView.setContentOffset(CGPoint(x: 0, y: scrollTop), animated: true)
                }
                #endif
            }
        }

        private func scrollWebView(to progress: Double, webView: WKWebView) {
            let js = """
            (function() {
                var docHeight = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
                var viewHeight = window.innerHeight;
                var scrollTop = \(progress) * Math.max(0, docHeight - viewHeight);
                window.scrollTo({ top: scrollTop, behavior: 'smooth' });
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func scrollPDF(to result: ReaderSearchResult, pdfView: PDFView) {
            guard
                let document = pdfView.document,
                let pageIndex = result.pdfPageIndex,
                let page = document.page(at: pageIndex),
                let pointX = result.pdfPointX,
                let pointY = result.pdfPointY
            else {
                scrollPDF(to: result.progress, pdfView: pdfView)
                return
            }

            let point = CGPoint(x: pointX, y: pointY)
            let destination = PDFDestination(page: page, at: point)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                pdfView.go(to: destination)
            }
        }

        private func scrollWebView(to result: ReaderSearchResult, webView: WKWebView) {
            if let exactScrollTop = result.exactScrollTop {
                let js = """
                (function() {
                    window.scrollTo({ top: \(exactScrollTop), behavior: 'smooth' });
                })();
                """
                webView.evaluateJavaScript(js, completionHandler: nil)
            } else {
                scrollWebView(to: result.progress, webView: webView)
            }
        }

        func applySearchIfNeeded(in view: NativeView) {
            guard let searchToken = parent.searchToken, lastAppliedSearchToken != searchToken else {
                return
            }
            lastAppliedSearchToken = searchToken
            performSearch(query: parent.searchQuery, in: view)
        }

        private func performSearch(query: String, in view: NativeView) {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else {
                DispatchQueue.main.async {
                    self.parent.onSearchResults([])
                }
                return
            }

            if let pdfView = pdfView {
                let results = searchPDF(query: trimmedQuery, in: pdfView)
                DispatchQueue.main.async {
                    self.parent.onSearchResults(results)
                }
            } else if let webView = view.subviews.first(where: { $0 is WKWebView }) as? WKWebView {
                searchWebView(query: trimmedQuery, webView: webView)
            }
        }

        private func searchPDF(query: String, in pdfView: PDFView) -> [ReaderSearchResult] {
            guard let document = pdfView.document else { return [] }

            let needle = query.lowercased()
            var results: [ReaderSearchResult] = []

            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex), let pageText = page.string, !pageText.isEmpty else {
                    continue
                }

                let lowercasedText = pageText.lowercased()
                var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex

                while let foundRange = lowercasedText.range(of: needle, options: [], range: searchRange) {
                    let snippet = snippetAround(range: foundRange, in: pageText)
                    let progress = document.pageCount > 1 ? Double(pageIndex) / Double(document.pageCount - 1) : 0
                    let nsRange = NSRange(foundRange, in: pageText)
                    let selectionBounds = page.selection(for: nsRange)?.bounds(for: page)
                    let pageBounds = page.bounds(for: pdfView.displayBox)
                    let destinationPoint = selectionBounds.map {
                        CGPoint(
                            x: max(pageBounds.minX, $0.minX),
                            y: min(pageBounds.maxY, $0.maxY + 24)
                        )
                    }
                    results.append(
                        ReaderSearchResult(
                            displayPage: "Page \(pageIndex + 1)",
                            snippet: snippet,
                            progress: progress,
                            exactScrollTop: nil,
                            pdfPageIndex: pageIndex,
                            pdfPointX: destinationPoint.map { Double($0.x) },
                            pdfPointY: destinationPoint.map { Double($0.y) }
                        )
                    )

                    if results.count >= 200 {
                        return results
                    }

                    searchRange = foundRange.upperBound..<lowercasedText.endIndex
                }
            }

            return results
        }

        private func searchWebView(query: String, webView: WKWebView) {
            let escapedQuery = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")

            let js = """
            (function() {
                const query = "\(escapedQuery)".trim().toLowerCase();
                if (!query) { return []; }

                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                const results = [];
                const docHeight = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
                const viewHeight = Math.max(window.innerHeight, 1);
                const totalPages = Math.max(1, Math.ceil(docHeight / viewHeight));

                function clamp(value, min, max) {
                    return Math.min(max, Math.max(min, value));
                }

                function snippet(text, index, length) {
                    const start = Math.max(0, index - 40);
                    const end = Math.min(text.length, index + length + 60);
                    return text.slice(start, end).replace(/\\s+/g, " ").trim();
                }

                while (walker.nextNode()) {
                    const node = walker.currentNode;
                    const text = node.textContent || "";
                    const lower = text.toLowerCase();
                    let fromIndex = 0;

                    while (fromIndex < lower.length) {
                        const matchIndex = lower.indexOf(query, fromIndex);
                        if (matchIndex === -1) { break; }

                        const range = document.createRange();
                        range.setStart(node, matchIndex);
                        range.setEnd(node, matchIndex + query.length);

                        const rect = range.getBoundingClientRect();
                        const absoluteTop = rect.top + window.scrollY;
                        const progress = docHeight > viewHeight ? clamp(absoluteTop / Math.max(1, docHeight - viewHeight), 0, 1) : 0;
                        const exactScrollTop = Math.max(0, absoluteTop - (viewHeight * 0.2));
                        const pageNumber = clamp(Math.floor(absoluteTop / viewHeight) + 1, 1, totalPages);

                        results.push({
                            page: "Page " + pageNumber,
                            snippet: snippet(text, matchIndex, query.length),
                            progress: progress,
                            exactScrollTop: exactScrollTop
                        });

                        if (results.length >= 200) {
                            return results;
                        }

                        fromIndex = matchIndex + query.length;
                    }
                }

                return results;
            })();
            """

            webView.evaluateJavaScript(js) { [weak self] value, _ in
                guard let self else { return }
                let results = (value as? [[String: Any]])?.compactMap { item -> ReaderSearchResult? in
                    guard
                        let page = item["page"] as? String,
                        let snippet = item["snippet"] as? String,
                        let progress = item["progress"] as? Double
                    else {
                        return nil
                    }
                    return ReaderSearchResult(
                        displayPage: page,
                        snippet: snippet,
                        progress: progress,
                        exactScrollTop: item["exactScrollTop"] as? Double,
                        pdfPageIndex: nil,
                        pdfPointX: nil,
                        pdfPointY: nil
                    )
                } ?? []

                DispatchQueue.main.async {
                    self.parent.onSearchResults(results)
                }
            }
        }

        private func snippetAround(range: Range<String.Index>, in text: String) -> String {
            let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
            return text[start..<end].replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // Abstract creation to shared method
    private func createView(context: Context) -> NativeView {
        let container = NativeView()
        
        if isPDF {
            let pdfView = PDFView()
            pdfView.document = PDFDocument(url: url)
            pdfView.autoScales = true
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
            
            pdfView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(pdfView)
            
            NSLayoutConstraint.activate([
                pdfView.topAnchor.constraint(equalTo: container.topAnchor),
                pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                pdfView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
            
            context.coordinator.setupPDFScrollTracking(pdfView)
            context.coordinator.restorePDFPosition(pdfView)
            
        } else {
            let config = WKWebViewConfiguration()
            #if os(macOS)
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
            #endif
            
            let scrollHandler = ScrollMessageHandler { progress in
                DispatchQueue.main.async {
                    context.coordinator.parent.scrollProgress = progress
                }
            }
            config.userContentController.add(scrollHandler, name: "scrollHandler")
            config.userContentController.add(LogMessageHandler(), name: "logHandler")
            config.userContentController.add(SelectionMessageHandler { text in
                DispatchQueue.main.async {
                    context.coordinator.parent.selectedText = text
                }
            }, name: "selectionHandler")
            
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = context.coordinator
            
            #if os(iOS)
            webView.scrollView.decelerationRate = .normal
            #endif
            
            webView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(webView)
            
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: container.topAnchor),
                webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
            
            webView.loadFileURL(url, allowingReadAccessTo: rootURL)
        }
        
        return container
    }

    #if os(macOS)
    func makeNSView(context: Context) -> NSView { createView(context: context) }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        if !isPDF, let webView = nsView.subviews.first(where: { $0 is WKWebView }) as? WKWebView {
            applySettings(to: webView, preserveScroll: true)
        }
        context.coordinator.applyJumpIfNeeded(in: nsView)
        context.coordinator.applySearchJumpIfNeeded(in: nsView)
        context.coordinator.applySearchIfNeeded(in: nsView)
    }
    #else
    func makeUIView(context: Context) -> UIView { createView(context: context) }
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        if !isPDF, let webView = uiView.subviews.first(where: { $0 is WKWebView }) as? WKWebView {
            applySettings(to: webView, preserveScroll: true)
        }
        context.coordinator.applyJumpIfNeeded(in: uiView)
        context.coordinator.applySearchJumpIfNeeded(in: uiView)
        context.coordinator.applySearchIfNeeded(in: uiView)
    }
    #endif
    
    func applySettings(to webView: WKWebView, preserveScroll: Bool) {
        let js: String
        let hyphenValue = settings.hyphenationLanguage == .auto ? "auto" : "manual" // 'auto' relies on browser detection, but we want to force 'auto' style
        // Actually, we always want CSS 'hyphens: auto', but we change the 'lang' attribute to control which dictionary is used.
        // If 'auto' is selected, we might want to detect or leave it default. 
        // Best approach: Always set CSS hyphens: auto. Set lang attribute on <html>.
        
        let langCode: String
        switch settings.hyphenationLanguage {
        case .auto: langCode = "" // Empty string or don't set it to let browser detect or use default
        default: langCode = settings.hyphenationLanguage.rawValue
        }
        
        // Common JS to set variables
        let commonJS = """
            document.documentElement.style.setProperty('--font-size', '\(settings.fontSize)px');
            document.documentElement.style.setProperty('--font-family', '\(settings.cssFontFamily)');
            document.documentElement.style.setProperty('--bg-color', '\(settings.theme.backgroundColor)');
            document.documentElement.style.setProperty('--text-color', '\(settings.theme.textColor)');
            document.body.style.textAlign = '\(settings.textAlignment.cssValue)';
            
            // Hyphenation
            document.documentElement.lang = '\(langCode)';
            document.body.style.webkitHyphens = 'auto';
            document.body.style.hyphens = 'auto';
        """

        if preserveScroll {
            js = """
            (function() {
                var scrollTop = window.pageYOffset || document.documentElement.scrollTop || 0;
                var docHeight = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
                var viewHeight = window.innerHeight;
                var scrollPercent = docHeight > viewHeight ? scrollTop / (docHeight - viewHeight) : 0;
                
                \(commonJS)
                
                requestAnimationFrame(function() {
                    var newDocHeight = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
                    var newScrollTop = scrollPercent * (newDocHeight - viewHeight);
                    window.scrollTo(0, Math.max(0, newScrollTop));
                });
            })();
            """
        } else {
            js = commonJS
        }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

class ScrollMessageHandler: NSObject, WKScriptMessageHandler {
    let onScroll: (Double) -> Void
    init(onScroll: @escaping (Double) -> Void) { self.onScroll = onScroll }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let progress = message.body as? Double { onScroll(min(1.0, max(0.0, progress))) }
    }
}

class LogMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("JS Log: \(message.body)")
    }
}

class SelectionMessageHandler: NSObject, WKScriptMessageHandler {
    let onSelection: (String) -> Void
    init(onSelection: @escaping (String) -> Void) { self.onSelection = onSelection }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let text = message.body as? String {
            onSelection(text)
        }
    }
}
