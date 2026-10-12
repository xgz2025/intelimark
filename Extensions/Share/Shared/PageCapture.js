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

function nextmarkTextAround(selection, before) {
  if (!selection.rangeCount) return null;
  var range = selection.getRangeAt(0);
  var node = before ? range.startContainer : range.endContainer;
  var text = node.textContent || "";
  var snippet = before
    ? text.slice(Math.max(0, range.startOffset - 48), range.startOffset)
    : text.slice(range.endOffset, range.endOffset + 48);
  snippet = snippet.trim();
  return snippet.length ? snippet : null;
}

function nextmarkCapturePage() {
  var selection = window.getSelection();
  var exact = selection ? selection.toString().trim() : "";
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
      exact: exact.slice(0, 2000),
      prefix: nextmarkTextAround(selection, true),
      suffix: nextmarkTextAround(selection, false)
    };
  }
  return result;
}

var ExtensionPreprocessingJS = new NextmarkPageCapture();
