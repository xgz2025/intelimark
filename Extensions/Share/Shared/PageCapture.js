//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

// Runs inside Safari when a page is shared to Nextmark
// (NSExtensionJavaScriptPreprocessingFile). The result arrives in the share
// extension under NSExtensionJavaScriptPreprocessingResultsKey and is parsed by
// `PageCapture(dictionary:)` — keep the keys in sync with Safari/Resources/content.js.
var NextmarkPageCapture = function () {};

NextmarkPageCapture.prototype = {
  run: function (args) {
    args.completionFunction(nextmarkCapturePage());
  },
  finalize: function (args) {}
};

var NEXTMARK_MAX_EXACT = 2000;
var NEXTMARK_CONTEXT_LENGTH = 48;

// Text just before or after the selection, in whole words, for a text-fragment link.
function nextmarkTextAround(selection, before) {
  if (!selection.rangeCount) return null;
  var range = selection.getRangeAt(0);
  var node = before ? range.startContainer : range.endContainer;
  // Offsets count characters only in text nodes; in an element they count children.
  if (node.nodeType !== Node.TEXT_NODE) return null;
  var text = node.data;
  var snippet;
  if (before) {
    var start = Math.max(0, range.startOffset - NEXTMARK_CONTEXT_LENGTH);
    snippet = text.slice(start, range.startOffset);
    // Text fragments match whole words: drop one cut in half.
    if (start > 0 && /\S/.test(text[start - 1])) snippet = snippet.replace(/^\S*/, "");
  } else {
    var end = range.endOffset + NEXTMARK_CONTEXT_LENGTH;
    snippet = text.slice(range.endOffset, end);
    if (end < text.length && /\S/.test(text[end])) snippet = snippet.replace(/\S*$/, "");
  }
  snippet = snippet.trim();
  return snippet.length ? snippet : null;
}

function nextmarkCapturePage() {
  var selection = window.getSelection();
  var exact = selection ? selection.toString().trim() : "";
  // A long selection is cut at a word; the text after the cut isn't its suffix.
  var truncated = exact.length > NEXTMARK_MAX_EXACT;
  if (truncated) exact = exact.slice(0, NEXTMARK_MAX_EXACT).replace(/\s+\S*$/, "");
  var canonical = document.querySelector('link[rel="canonical"]');
  var result = {
    url: document.URL,
    title: document.title,
    lang: document.documentElement.lang || null,
    canonical: canonical ? canonical.href : null,
    excerpt: document.body ? document.body.innerText.slice(0, 4000) : null,
    jsonLD: Array.prototype.slice
      .call(document.querySelectorAll('script[type="application/ld+json"]'), 0, 5)
      .map(function (script) { return script.textContent.slice(0, 20000); })
  };
  if (exact) {
    result.selection = {
      exact: exact,
      prefix: nextmarkTextAround(selection, true),
      suffix: truncated ? null : nextmarkTextAround(selection, false)
    };
  }
  return result;
}

var ExtensionPreprocessingJS = new NextmarkPageCapture();
