//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

// "Save to Laterwise": the toolbar button (macOS, and the extensions menu on iPhone
// and iPad) and the right-click menu (macOS). Forwards the page capture from
// content.js to the native handler.
const MENU_ID = "nextmark-save";

// Inline images (data:, blob:) and browser pages (favorites:) can't be opened again later.
function isSavable(url) {
  return typeof url === "string" && /^(https?|file):/i.test(url);
}

// Saves through the native handler; tells the page how it went, where it can.
async function save(tabID, payload) {
  let ok = false;
  try {
    const reply = await browser.runtime.sendNativeMessage("application.id", payload);
    ok = Boolean(reply && reply.ok);
  } catch (error) {
    ok = false;
  }
  try {
    await browser.tabs.sendMessage(tabID, { type: "saved", ok });
  } catch (error) {
    // No content script on this page: nothing to show it on.
  }
}

browser.runtime.onInstalled.addListener(() => {
  if (!browser.contextMenus) return; // iOS Safari has no context menus API
  browser.contextMenus.create({
    id: MENU_ID,
    title: "Save to Laterwise",
    contexts: ["page", "selection", "link", "image"]
  });
});

if (browser.contextMenus) {
  browser.contextMenus.onClicked.addListener(async (info, tab) => {
    if (info.menuItemId !== MENU_ID || !tab) return;
    // A right-clicked link or image is saved on its own: the page around it isn't
    // its context, and its title, text and structured data would be wrong for it.
    const target = [info.linkUrl, info.srcUrl].find(isSavable);
    if (target) {
      const label = info.linkText || undefined;
      await save(tab.id, { type: "save", url: target, title: label });
      return;
    }
    await savePage(tab, info.selectionText);
  });
}

// The page, with its selection as a highlight.
async function savePage(tab, selectionText) {
  let page = {};
  try {
    page = (await browser.tabs.sendMessage(tab.id, { type: "capture" })) || {};
  } catch (error) {
    // Pages where content scripts can't run (e.g. the start page): fall back to tab info.
  }
  const payload = Object.assign({ url: tab.url, title: tab.title }, page, { type: "save" });
  // Text selected inside a frame the content script doesn't run in.
  if (!payload.selection && selectionText) {
    payload.selection = { exact: selectionText.trim().slice(0, 2000) };
  }
  if (!isSavable(payload.url)) {
    if (!payload.selection) return;  // a browser page with nothing selected: nothing to keep
    delete payload.url;
  }
  await save(tab.id, payload);
}

if (browser.action) {
  browser.action.onClicked.addListener(async (tab) => {
    if (tab) await savePage(tab, null);
  });
}
