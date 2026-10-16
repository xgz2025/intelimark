//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

// Answers capture requests from background.js with the same keys as
// Share/Shared/PageCapture.js, so `PageCapture(dictionary:)` parses both.
// Next (PRD C7): a "Mark" button on selection and re-rendering saved highlights.
(() => {
  const maxExact = 2000;
  const contextLength = 48;

  // Text just before or after the selection, in whole words, for a text-fragment link.
  function textAround(selection, before) {
    if (!selection.rangeCount) return null;
    const range = selection.getRangeAt(0);
    const node = before ? range.startContainer : range.endContainer;
    // Offsets count characters only in text nodes; in an element they count children.
    if (node.nodeType !== Node.TEXT_NODE) return null;
    const text = node.data;
    let snippet;
    if (before) {
      const start = Math.max(0, range.startOffset - contextLength);
      snippet = text.slice(start, range.startOffset);
      // Text fragments match whole words: drop one cut in half.
      if (start > 0 && /\S/.test(text[start - 1])) snippet = snippet.replace(/^\S*/, "");
    } else {
      const end = range.endOffset + contextLength;
      snippet = text.slice(range.endOffset, end);
      if (end < text.length && /\S/.test(text[end])) snippet = snippet.replace(/\S*$/, "");
    }
    snippet = snippet.trim();
    return snippet.length ? snippet : null;
  }

  // Open Graph and product tags, and a price shown with schema.org microdata: what a
  // shop page says about the product as the person saw it. Same keys as PageCapture.js.
  const metaKeys = [
    "og:title", "og:description", "og:image", "og:site_name", "og:type",
    "product:price:amount", "product:price:currency", "og:price:amount", "og:price:currency",
    "product:brand", "product:availability"
  ];

  function pageMeta() {
    const meta = {};
    for (const key of metaKeys) {
      const tag = document.querySelector(`meta[property="${key}"], meta[name="${key}"]`);
      const value = tag && tag.getAttribute("content");
      if (value) meta[key] = value.trim().slice(0, 1000);
    }
    const price = document.querySelector('[itemprop="price"]');
    const amount = price && (price.getAttribute("content") || price.textContent);
    if (amount) meta["itemprop:price"] = amount.trim().slice(0, 40);
    const currency = document.querySelector('[itemprop="priceCurrency"]');
    const code = currency && (currency.getAttribute("content") || currency.textContent);
    if (code) meta["itemprop:priceCurrency"] = code.trim().slice(0, 10);
    return meta;
  }

  function capturePage() {
    const selection = window.getSelection();
    let exact = selection ? selection.toString().trim() : "";
    // A long selection is cut at a word; the text after the cut isn't its suffix.
    const truncated = exact.length > maxExact;
    if (truncated) exact = exact.slice(0, maxExact).replace(/\s+\S*$/, "");
    const canonical = document.querySelector('link[rel="canonical"]');
    const result = {
      url: document.URL,
      title: document.title,
      lang: document.documentElement.lang || null,
      canonical: canonical ? canonical.href : null,
      excerpt: document.body ? document.body.innerText.slice(0, 4000) : null,
      jsonLD: Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
        .slice(0, 5)
        .map((script) => script.textContent.slice(0, 20000)),
      meta: pageMeta()
    };
    if (exact) {
      result.selection = {
        exact: exact,
        prefix: textAround(selection, true),
        suffix: truncated ? null : textAround(selection, false)
      };
    }
    return result;
  }

  // A brief note in the corner of the page: saved, or not.
  function showResult(ok) {
    const note = document.createElement("div");
    note.textContent = ok ? "Saved to Laterwise" : "Couldn't save to Laterwise";
    note.setAttribute("role", "status");
    note.style.cssText = "position:fixed;z-index:2147483647;right:16px;bottom:16px;padding:10px 14px;" +
      "border-radius:10px;font:600 13px -apple-system,system-ui,sans-serif;color:#fff;" +
      "background:" + (ok ? "rgba(30,30,30,.88)" : "rgba(190,40,40,.92)") + ";box-shadow:0 4px 16px rgba(0,0,0,.25)";
    (document.body || document.documentElement).appendChild(note);
    setTimeout(() => note.remove(), 2200);
  }

  browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (!message) return;
    if (message.type === "capture") {
      try {
        sendResponse(capturePage());
      } catch (error) {
        sendResponse({ url: document.URL, title: document.title });
      }
    } else if (message.type === "saved") {
      showResult(Boolean(message.ok));
    }
  });
})();
