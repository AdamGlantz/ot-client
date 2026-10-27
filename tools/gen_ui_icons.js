// Renders the touch UI's icons (ot-client#28) from game-icons.net SVGs
// (CC BY 3.0, https://game-icons.net) to PNGs at 2x: a single-colour glyph
// on a transparent background, one file per icon and colour.
//
//   node tools/gen_ui_icons.js <game-icons checkout> <output dir>
//
// Also writes the round spell sheet: spell-icons-32x32.png with a circular
// mask, at 64 px per icon.
const fs = require('fs');
const path = require('path');
const { chromium } = require(process.env.PW_MODULE || 'playwright');

const SIZE = 64;
const COLOURS = { '': '#e8e8e8', '_on': '#e0b84c' };
// output name -> game-icons file
const ICONS = {
    menu: 'delapouite/hamburger-menu', equipment: 'delapouite/chest-armor', map: 'lorc/treasure-map',
    skills: 'delapouite/histogram', battle: 'lorc/crossed-swords', vip: 'delapouite/star-formation',
    containers: 'delapouite/backpack', chat: 'delapouite/chat-bubble', edit: 'delapouite/pencil',
    fullscreen: 'delapouite/expand', settings: 'lorc/cog',
    attack: 'delapouite/crosshair', follow: 'lorc/footprint', look: 'delapouite/eye-target',
    chase: 'lorc/run', skull: 'lorc/skull-crossed-bones', player: 'delapouite/person',
};

(async () => {
    const [source, out] = process.argv.slice(2);
    fs.mkdirSync(out, { recursive: true });
    const browser = await chromium.launch();
    const page = await browser.newPage();
    const render = (svg, colour) => page.evaluate(async ({ svg, colour, size }) => {
        // the icon path only (drop the black square behind it), in our colour
        svg = svg.replace(/<path d="M0 0h512v512H0z"\/>/, '').replace(/fill="#fff"/g, `fill="${colour}"`);
        const img = new Image();
        img.src = 'data:image/svg+xml;base64,' + btoa(svg);
        await img.decode();
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = size;
        canvas.getContext('2d').drawImage(img, 0, 0, size, size);
        return canvas.toDataURL('image/png').split(',')[1];
    }, { svg, colour, size: SIZE });
    for (const [name, file] of Object.entries(ICONS)) {
        const svg = fs.readFileSync(path.join(source, file + '.svg'), 'utf8');
        for (const [suffix, colour] of Object.entries(COLOURS)) {
            fs.writeFileSync(path.join(out, name + suffix + '.png'), Buffer.from(await render(svg, colour), 'base64'));
        }
    }

    // round spells: every 32 px tile scaled to 64 and cut to a circle
    const sheet = fs.readFileSync(path.join(__dirname, '../data/images/game/spells/spell-icons-32x32.png')).toString('base64');
    const round = await page.evaluate(async (sheet) => {
        const img = new Image();
        img.src = 'data:image/png;base64,' + sheet;
        await img.decode();
        const count = img.width / 32, size = 64;
        const canvas = document.createElement('canvas');
        canvas.width = count * size;
        canvas.height = size;
        const ctx = canvas.getContext('2d');
        ctx.imageSmoothingEnabled = false;
        for (let i = 0; i < count; i++) {
            ctx.save();
            ctx.beginPath();
            ctx.arc(i * size + size / 2, size / 2, size / 2 - 1, 0, Math.PI * 2);
            ctx.clip();
            ctx.drawImage(img, i * 32, 0, 32, 32, i * size, 0, size, size);
            ctx.restore();
        }
        return canvas.toDataURL('image/png').split(',')[1];
    }, sheet);
    fs.writeFileSync(path.join(out, 'spell-icons-round-64x64.png'), Buffer.from(round, 'base64'));
    await browser.close();
})();
