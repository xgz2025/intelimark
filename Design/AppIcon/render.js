// Usage: node render.js out_dir size [transparent] in1.svg in2.svg ...
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const [outDir, sizeStr, mode, ...inputs] = process.argv.slice(2);
  const size = parseInt(sizeStr, 10);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
  for (const inp of inputs) {
    const svg = fs.readFileSync(inp, 'utf8');
    await page.setContent(`<html><body style="margin:0;background:transparent"><img id="i" src="data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}" width="${size}" height="${size}" style="display:block"></body></html>`);
    await page.waitForFunction(() => document.getElementById('i').complete);
    const out = path.join(outDir, path.basename(inp, '.svg') + (size === 1024 ? '' : `-${size}`) + '.png');
    await page.screenshot({ path: out, omitBackground: mode === 'transparent', clip: { x: 0, y: 0, width: size, height: size } });
    console.log('wrote', out);
  }
  await browser.close();
})();
