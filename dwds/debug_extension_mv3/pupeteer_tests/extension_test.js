const puppeteer = require('puppeteer');

(async () => {
  const pathToExtension = require('path').join(__dirname, '../compiled');
  console.log('path to extension is', pathToExtension);
  const browser = await puppeteer.launch({
    headless: 'chrome',
    args: [
      `--disable-extensions-except=${pathToExtension}`,
      `--load-extension=${pathToExtension}`,
    ],
  });
  const backgroundSwTarget = await browser.waitForTarget(
    target => target.type() === 'service_worker'
  );
  const backgroundSw = await backgroundSwTarget.page();
  backgroundSw.
  // Test the background page as you would any other page.
  await browser.close();
})();