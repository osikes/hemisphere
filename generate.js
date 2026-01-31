const puppeteer = require('puppeteer');
const path = require('path');
const { execSync } = require('child_process');
const fs = require('fs');

async function getScreenResolution() {
  // Get the main display resolution on macOS
  try {
    const result = execSync(
      `system_profiler SPDisplaysDataType | grep Resolution | head -1 | awk '{print $2, $4}'`,
      { encoding: 'utf-8' }
    );
    const [width, height] = result.trim().split(' ').map(Number);
    if (width && height) {
      return { width, height };
    }
  } catch (e) {
    console.log('Could not detect resolution, using default');
  }
  // Fallback to common resolution
  return { width: 2560, height: 1440 };
}

async function setWallpaper(imagePath) {
  const dbPath = `${process.env.HOME}/Library/Application Support/Dock/desktoppicture.db`;

  try {
    // Ensure our wallpaper is in the data table
    execSync(`sqlite3 "${dbPath}" "INSERT OR IGNORE INTO data (value) VALUES ('${imagePath}');"`, { stdio: 'pipe' });

    // Get the data ROWID for our wallpaper
    const dataId = execSync(`sqlite3 "${dbPath}" "SELECT ROWID FROM data WHERE value='${imagePath}' LIMIT 1;"`, { encoding: 'utf-8' }).trim();

    // Update ALL preferences with key=1 (image path) to point to our wallpaper
    execSync(`sqlite3 "${dbPath}" "UPDATE preferences SET data_id=${dataId} WHERE key=1;"`, { stdio: 'pipe' });

    // Restart Dock to apply changes
    execSync('killall Dock');
    console.log('Wallpaper set on all spaces via database update');
  } catch (dbError) {
    console.log('Database method failed:', dbError.message);
    console.log('Trying AppleScript fallback...');

    // Fallback to AppleScript (only sets current space)
    const script = `
      tell application "System Events"
        tell every desktop
          set picture to "${imagePath}"
        end tell
      end tell
    `;
    execSync(`osascript -e '${script}'`);
  }
}

async function main() {
  const noSet = process.argv.includes('--no-set');

  // Get style from command line (--style=dark, --style=light, --style=satellite)
  const styleArg = process.argv.find(arg => arg.startsWith('--style='));
  const style = styleArg ? styleArg.split('=')[1] : 'satellite';

  console.log(`Generating weather wallpaper (style: ${style})...`);

  const resolution = await getScreenResolution();
  console.log(`Screen resolution: ${resolution.width}x${resolution.height}`);

  const browser = await puppeteer.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-cache',
      '--disk-cache-size=0'
    ]
  });

  const page = await browser.newPage();

  // Disable caching to get fresh radar data
  await page.setCacheEnabled(false);

  await page.setViewport({
    width: resolution.width,
    height: resolution.height,
    deviceScaleFactor: 2 // Retina
  });

  const mapPath = path.join(__dirname, 'map.html');
  await page.goto(`file://${mapPath}?style=${style}`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000
  });

  // Wait for all tiles to load
  console.log('Loading map and radar data...');
  await page.waitForFunction('window.mapReady === true', { timeout: 90000 });

  // Small buffer for final rendering
  console.log('All tiles loaded, finalizing...');
  await new Promise(resolve => setTimeout(resolve, 1000));

  // Take screenshot to a temp file first, then move
  const tempPath = path.join(__dirname, `wallpaper-temp-${Date.now()}.png`);
  const outputPath = path.join(__dirname, 'wallpaper.png');

  await page.screenshot({
    path: tempPath,
    type: 'png'
  });

  // Verify temp file was created
  if (!fs.existsSync(tempPath)) {
    throw new Error('Screenshot failed - temp file not created');
  }

  const stats = fs.statSync(tempPath);
  console.log(`Screenshot size: ${stats.size} bytes`);

  // Remove old file and rename temp to final
  if (fs.existsSync(outputPath)) {
    fs.unlinkSync(outputPath);
  }
  fs.renameSync(tempPath, outputPath);

  console.log(`Wallpaper saved to: ${outputPath}`);

  await browser.close();

  // Set as desktop wallpaper (unless --no-set flag is passed)
  if (!noSet) {
    console.log('Setting as desktop wallpaper...');
    await setWallpaper(outputPath);
  } else {
    console.log('Skipping wallpaper set (--no-set flag)');
  }

  console.log('Done!');
}

main().catch(console.error);
