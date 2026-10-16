//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

// Runs inside Safari when a page is shared to Laterwise
// (NSExtensionJavaScriptPreprocessingFile). The result arrives in the share
// extension under NSExtensionJavaScriptPreprocessingResultsKey and is parsed by
// `PageCapture(dictionary:)` — keep the keys in sync with Safari/Resources/content.js.
var NextmarkPageCapture = function () {};

NextmarkPageCapture.prototype = {
  run: function (args) {
    var result;
    try {
      result = nextmarkCapturePage();
    } catch (error) {
      // An unusual page must not leave the share sheet waiting: send what's certain.
      result = { url: document.URL, title: document.title };
    }
    args.completionFunction(result);
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

// Open Graph and product tags, and a price shown with schema.org microdata: what a
// shop page says about the product as the person saw it.
var NEXTMARK_META_KEYS = [
  "og:title", "og:description", "og:image", "og:site_name", "og:type",
  "product:price:amount", "product:price:currency", "og:price:amount", "og:price:currency",
  "product:brand", "product:availability"
];

// The price the page shows: kept the same as Extensions/Shared/ProductPrice.js.
// BEGIN laterwisePrice
function laterwisePrice() {
  var money = /(US\$|C\$|A\$|HK\$|S\$|NT\$|R\$|\$|€|£|¥|￥|₩|₹|RMB|CNY|USD|EUR|GBP|JPY)\s?\d[\d.,\s]*\d|\d[\d.,]*\s?(€|元|円|USD|EUR|kr|zł)|\d[\d.,]*\d/;
  var selectors = [
    // Amazon (desktop and mobile)
    "#corePriceDisplay_desktop_feature_div .a-price .a-offscreen",
    "#corePrice_feature_div .a-price .a-offscreen",
    "#corePrice_desktop .a-price .a-offscreen",
    "#corePrice_mobile_feature_div .a-price .a-offscreen",
    "#apex_desktop .a-price .a-offscreen",
    "#apex_offerDisplay_mobile .a-price .a-offscreen",
    "#priceblock_dealprice", "#priceblock_ourprice", "#price_inside_buybox", "#newBuyBoxPrice", "#kindle-price",
    // Target
    "[data-test='product-price']",
    // Shein
    ".productPrice .from", "#productMainPriceId", "[class*='productPrice__main']", ".product-intro__head-mainprice .original",
    ".product-intro__head-mainprice",
    "[class*='productPrice'] [class*='sale']", "[class*='product-intro__head-price']",
    // eBay, Walmart, Best Buy, AliExpress, Taobao and Tmall, JD, Zara, Uniqlo
    ".x-price-primary", "[data-testid='price-wrap'] [itemprop='price']", ".priceView-customer-price > span",
    ".product-price-current", "[class*='price--current']", "[class*='Price--priceText']", ".tm-price",
    ".summary-price .p-price", ".p-price .price", ".money-amount__main", ".fr-ec-price-text",
    // Microdata, anywhere
    "[itemprop='price']"
  ];
  function clean(text) {
    return (text || "").replace(/\s+/g, " ").trim();
  }
  function priced(element) {
    if (!element) return null;
    var text = clean(element.getAttribute("content") || element.textContent);
    return text.length <= 40 && /\d/.test(text) && money.test(text) ? text : null;
  }
  function currency() {
    var tag = document.querySelector("meta[property='product:price:currency'], meta[property='og:price:currency'], [itemprop='priceCurrency']");
    return tag ? clean(tag.getAttribute("content") || tag.textContent) || null : null;
  }
  for (var i = 0; i < selectors.length; i++) {
    var found = priced(document.querySelector(selectors[i]));
    if (found) return { price: found, currency: currency(), source: "selector" };
  }
  // The shop's own data in the page's scripts: Target, Shein and Walmart put the price
  // there before (or without) showing it. Kept the same as ProductPage.embeddedPatterns.
  var embedded = [
    { host: /(^|\.)target\.com$/, pattern: /"formatted_current_price"\s*:\s*"([^"]{1,40})"/, code: "USD" },
    { host: /(^|\.)target\.com$/, pattern: /"current_retail"\s*:\s*([\d.]{1,12})/, code: "USD" },
    { host: /(^|\.)shein\./, pattern: /"salePrice"\s*:\s*\{[^{}]{0,400}?"amountWithSymbol"\s*:\s*"([^"]{1,40})"/, code: null },
    { host: /(^|\.)walmart\./, pattern: /"currentPrice"\s*:\s*\{[^{}]{0,400}?"priceString"\s*:\s*"([^"]{1,40})"/, code: null }
  ];
  var scripts = document.querySelectorAll("script:not([src])");
  for (var k = 0; k < embedded.length; k++) {
    if (!embedded[k].host.test(location.hostname)) continue;
    for (var m = 0; m < scripts.length && m < 400; m++) {
      var match = embedded[k].pattern.exec(scripts[m].textContent || "");
      if (!match) continue;
      var value = clean(match[1].replace(/\\u([0-9a-fA-F]{4})/g, function (all, hex) {
        return String.fromCharCode(parseInt(hex, 16));
      }));
      if (/\d/.test(value)) return { price: value, currency: embedded[k].code || currency(), source: "selector" };
    }
  }
  // Otherwise the price a person would see: a currency amount near the top of the
  // page in the largest type, not struck through (that's the old price).
  var heading = document.querySelector("h1");
  var headingTop = heading ? heading.getBoundingClientRect().top + window.scrollY : 0;
  var symbol = /(US\$|C\$|A\$|HK\$|S\$|\$|€|£|¥|￥|₩|₹)\s?\d|\d\s?(€|元|円)/;
  var candidates = document.querySelectorAll("span, div, p, strong, b, ins, bdi, em, h2, h3");
  var best = null;
  var bestScore = 0;
  for (var j = 0; j < candidates.length && j < 6000; j++) {
    var element = candidates[j];
    if (element.children.length > 4) continue;
    var text = clean(element.textContent);
    if (text.length === 0 || text.length > 24 || !symbol.test(text)) continue;
    var rect = element.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) continue;
    var top = rect.top + window.scrollY;
    if (top > 2400) continue;
    var style = window.getComputedStyle(element);
    if (style.visibility === "hidden" || style.display === "none") continue;
    if ((style.textDecorationLine || style.textDecoration || "").indexOf("line-through") >= 0) continue;
    var size = parseFloat(style.fontSize) || 0;
    var score = size * (1 - Math.min(Math.abs(top - headingTop), 1600) / 3200) * (parseInt(style.fontWeight, 10) >= 600 ? 1.15 : 1);
    if (score > bestScore) {
      bestScore = score;
      best = text;
    }
  }
  return best ? { price: best, currency: currency(), source: "visible" } : null;
}
// END laterwisePrice

function nextmarkMeta() {
  var meta = {};
  NEXTMARK_META_KEYS.forEach(function (key) {
    var tag = document.querySelector('meta[property="' + key + '"], meta[name="' + key + '"]');
    var value = tag && tag.getAttribute("content");
    if (value) meta[key] = value.trim().slice(0, 1000);
  });
  var price = document.querySelector('[itemprop="price"]');
  if (price) {
    var amount = price.getAttribute("content") || price.textContent;
    if (amount) meta["itemprop:price"] = amount.trim().slice(0, 40);
  }
  var currency = document.querySelector('[itemprop="priceCurrency"]');
  if (currency) {
    var code = currency.getAttribute("content") || currency.textContent;
    if (code) meta["itemprop:priceCurrency"] = code.trim().slice(0, 10);
  }
  try {
    var shown = laterwisePrice();
    if (shown) {
      meta["laterwise:price"] = shown.price.slice(0, 40);
      if (shown.currency) meta["laterwise:currency"] = shown.currency.slice(0, 10);
      meta["laterwise:priceSource"] = shown.source;
    }
  } catch (error) {}
  return meta;
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
      .map(function (script) { return script.textContent.slice(0, 20000); }),
    meta: nextmarkMeta()
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
