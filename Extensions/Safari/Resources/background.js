//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

// Adds "Save to Nextmark" to Safari's right-click menu (macOS) and forwards the
// page capture from content.js to the native handler.
const MENU_ID = "nextmark-save";

browser.runtime.onInstalled.addListener(() => {
  if (!browser.contextMenus) return; // iOS Safari has no context menus API
  browser.contextMenus.create({
    id: MENU_ID,
    title: "Save to Nextmark",
    contexts: ["page", "selection", "link", "image"]
  });
});

if (browser.contextMenus) {
  browser.contextMenus.onClicked.addListener(async (info, tab) => {
    if (info.menuItemId !== MENU_ID || !tab) return;
    let page = {};
    try {
      page = (await browser.tabs.sendMessage(tab.id, { type: "capture" })) || {};
    } catch (error) {
      // Pages where content scripts can't run (e.g. the start page): fall back to tab info.
    }
    const payload = Object.assign({ url: tab.url, title: tab.title }, page, { type: "save" });
    if (info.linkUrl) payload.url = info.linkUrl;
    await browser.runtime.sendNativeMessage("application.id", payload);
  });
}
