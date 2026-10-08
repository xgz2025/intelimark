// Answers capture requests from background.js with the same keys as
// Share/Shared/PageCapture.js, so `PageCapture(dictionary:)` parses both.
// Next (PRD C7): a "Mark" button on selection and re-rendering saved highlights.
(() => {
  function textAround(selection, before) {
    if (!selection.rangeCount) return null;
    const range = selection.getRangeAt(0);
    const node = before ? range.startContainer : range.endContainer;
    const text = node.textContent || "";
    const snippet = (before
      ? text.slice(Math.max(0, range.startOffset - 48), range.startOffset)
      : text.slice(range.endOffset, range.endOffset + 48)).trim();
    return snippet.length ? snippet : null;
  }

  function capturePage() {
    const selection = window.getSelection();
    const exact = selection ? selection.toString().trim() : "";
    const canonical = document.querySelector('link[rel="canonical"]');
    const result = {
      url: document.URL,
      title: document.title,
      lang: document.documentElement.lang || null,
      canonical: canonical ? canonical.href : null,
      excerpt: document.body ? document.body.innerText.slice(0, 4000) : null,
      jsonLD: Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
        .slice(0, 5)
        .map((script) => script.textContent.slice(0, 20000))
    };
    if (exact) {
      result.selection = {
        exact: exact.slice(0, 2000),
        prefix: textAround(selection, true),
        suffix: textAround(selection, false)
      };
    }
    return result;
  }

  browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message && message.type === "capture") {
      sendResponse(capturePage());
    }
  });
})();
