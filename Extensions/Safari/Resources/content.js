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
    ".productPrice .from", ".product-intro__head-mainprice .original", ".product-intro__head-mainprice",
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
    try {
      const shown = laterwisePrice();
      if (shown) {
        meta["laterwise:price"] = shown.price.slice(0, 40);
        if (shown.currency) meta["laterwise:currency"] = shown.currency.slice(0, 10);
        meta["laterwise:priceSource"] = shown.source;
      }
    } catch (error) {}
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
