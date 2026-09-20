// Code-native layouts around unchanged, real Android screenshots. Node >= 22.
import {spawn, execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, writeFileSync, mkdirSync, existsSync, renameSync, rmSync} from 'node:fs';
import {resolve, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';

const [mode, destination] = process.argv.slice(2);
if (!['assets', 'contact'].includes(mode) || !destination) {
  throw Error('Usage: node scripts/store_assets/render.mjs assets|contact OUTPUT');
}
const out = resolve(destination);
mkdirSync(out, {recursive: true});
const profile = mkdtempSync('/dev/shm/fz-assets-chrome-');
const chrome = spawn('google-chrome', ['--headless=new', '--no-sandbox',
  '--disable-gpu', '--disable-dev-shm-usage', '--no-first-run',
  '--no-default-browser-check', '--hide-scrollbars', '--remote-debugging-port=0',
  `--user-data-dir=${profile}`, 'about:blank'], {stdio: 'ignore'});
let socket;
try {
  for (let i = 0; !existsSync(join(profile, 'DevToolsActivePort')); i++) {
    if (i > 100) throw Error('Chrome did not start');
    await delay(100);
  }
  const port = readFileSync(join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0];
  const pages = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
  socket = new WebSocket(pages.find(p => p.type === 'page').webSocketDebuggerUrl);
  await new Promise((ok, fail) => {socket.onopen = ok; socket.onerror = fail;});
  let id = 0;
  const pending = new Map();
  socket.onmessage = ({data}) => {
    const message = JSON.parse(data);
    if (pending.has(message.id)) {
      const {ok, fail} = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) fail(Error(JSON.stringify(message.error))); else ok(message.result);
    }
  };
  const call = (method, params = {}) => new Promise((ok, fail) => {
    pending.set(++id, {ok, fail});
    socket.send(JSON.stringify({id, method, params}));
  });
  const uri = p => pathToFileURL(resolve(p)).href;
  const font = `@font-face{font-family:Roboto;src:url('${uri('assets/fonts/Roboto-Regular.ttf')}')}@font-face{font-family:Roboto;src:url('${uri('assets/fonts/Roboto-Bold.ttf')}');font-weight:700}`;
  async function render(name, width, height, body, css = '') {
    const path = join(out, name);
    mkdirSync(resolve(path, '..'), {recursive: true});
    const html = join(out, 'raw/layouts', `${name}.html`);
    mkdirSync(resolve(html, '..'), {recursive:true});
    if (existsSync(`${path}.html`)) renameSync(`${path}.html`, html);
    writeFileSync(html, `<!doctype html><meta charset="utf-8"><style>${font}*{box-sizing:border-box}html,body{margin:0;width:${width}px;height:${height}px;overflow:hidden;background:#fff;font-family:Roboto,sans-serif}${css}</style>${body}`);
    await call('Emulation.setDeviceMetricsOverride', {width, height, deviceScaleFactor:1, mobile:false});
    await call('Page.navigate', {url:uri(html)});
    await delay(100);
    const ready = await call('Runtime.evaluate', {expression:'Promise.all([document.fonts.ready,...Array.from(document.images).map(i=>i.decode())])', awaitPromise:true});
    if (ready.exceptionDetails) throw Error(`Image/font loading failed for ${name}`);
    const result = await call('Page.captureScreenshot', {format:'png', captureBeyondViewport:false});
    writeFileSync(path, Buffer.from(result.data, 'base64'));
    // Lossless RGB encoding only: no changes to the screenshot content.
    execFileSync('convert', [path, `${name === 'icon/app-icon.png' ? 'PNG32' : 'PNG24'}:${path}`]);
    console.log(path);
  }
  if (mode === 'contact') {
    const groups = [
      ['Smartphone', Array.from({length:8},(_,i)=>`phone/0${i+1}.png`)],
      ['7-Zoll-Tablet', ['01-dashboard','02-history','03-reading','04-pdf'].map(n=>`tablet7/${n}.png`)],
      ['10-Zoll-Tablet', ['01-dashboard','02-history','03-reading','04-pdf'].map(n=>`tablet10/${n}.png`)],
    ];
    let body = `<h1>Fahrzeugakte <span>Store-Bilder · Deutsch</span></h1><section class="branding"><img src="${uri(join(out,'icon/app-icon.png'))}"><img src="${uri(join(out,'feature/feature-graphic.png'))}"></section>`;
    for (const [title,files] of groups) {
      body += `<h2>${title}</h2><section class="${title==='Smartphone'?'phones':'tablets'}">${files.map(f=>`<figure><img src="${uri(join(out,f))}"><figcaption>${f}</figcaption></figure>`).join('')}</section>`;
    }
    await render('VORSCHAU.png',1800,3500,body,`body{background:#F1F4F7;padding:45px;color:#243D53}h1{font-size:36px;margin:0 0 30px}h1 span{font-size:22px;font-weight:400;margin-left:20px}h2{font-size:24px;margin:28px 0 16px}.branding{display:flex;gap:40px;height:240px}.branding img{height:100%;width:auto}.phones,.tablets{display:grid;gap:18px}.phones{grid-template-columns:repeat(4,1fr)}.tablets{grid-template-columns:repeat(2,1fr)}figure{margin:0}figure img{width:100%;display:block}figcaption{font-size:13px;margin-top:8px}.tablets img{height:275px;object-fit:contain;background:#F1F4F7}.tablets{row-gap:18px}`);
  } else {
    const logo = uri('assets/branding/fahrzeugakte_icon_1024.png');
    await render('icon/app-icon.png',512,512,`<img src="${logo}" width="512" height="512">`, `body{background:#243D53}`);
    const car = readFileSync('assets/branding/fahrzeugakte_mark.svg', 'utf8');
    await render('feature/feature-graphic.png',1024,500,`<div class="orb"></div><main><div class="eyebrow">DEIN FAHRZEUG. DEINE GESCHICHTE.</div><h1>Fahrzeugakte</h1><p>Wartungen festhalten.<br>Belege griffbereit.</p><div class="foot">Fotos · PDF · Erinnerungen</div></main><div class="paper rear"></div><div class="paper front"><i></i><i></i><i></i></div><div class="car">${car}</div>`,
      `body{background:#243D53;color:#F0F5F7}.orb{position:absolute;width:520px;height:520px;left:615px;top:-60px;border:1px solid #536C81;border-radius:50%}.car{position:absolute;right:15px;top:66px;width:405px;height:405px}.car svg{width:100%;height:100%}main{position:absolute;left:64px;top:83px}.eyebrow{font-size:14px;letter-spacing:1.7px;color:#B9D0E1}h1{font-size:64px;line-height:1.04;letter-spacing:-1.6px;margin:25px 0 25px}p{font-size:29px;line-height:1.35;margin:0}.foot{margin-top:33px;font-size:19px;color:#B9D0E1}.paper{position:absolute;width:118px;height:156px;border:2px solid #6D8BA3;border-radius:10px}.rear{right:85px;top:78px;transform:rotate(15deg)}.front{right:114px;top:76px;transform:rotate(3deg);background:#243D53;padding:27px 20px}.front i{display:block;height:2px;background:#6D8BA3;margin:13px 0}.front i:last-child{width:65%}`);
    const headlines = ['Deine Fahrzeuge\nim Blick','Wartungen und\nReparaturen festhalten','Fotos hinzufügen\nund ordnen','PDF-Belege\ngriffbereit','Deine Fahrzeuggeschichte\nüberblicken','An Termine\nerinnern lassen','Fahrzeugprotokolle\nals PDF teilen','Deine Daten\nverschlüsselt sichern'];
    for (let i=0;i<headlines.length;i++) {
      const number = String(i+1).padStart(2,'0');
      const raw = join(out,`raw/phone/${number}.png`);
      if (!existsSync(raw)) throw Error(`Missing real capture: ${raw}`);
      await render(`phone/${number}.png`,1080,1920,`<header><div class="brand">FAHRZEUGAKTE <span>· ${number}</span></div><h1>${headlines[i].replace('\n','<br>')}</h1></header><img class="screen" src="${uri(raw)}">`,
        `body{background:#F1F4F7;color:#243D53}header{height:330px;padding:45px 70px 0}.brand{font-size:22px;font-weight:700;letter-spacing:2.8px}.brand span{color:#536C81}h1{font-size:${i===4?58:64}px;line-height:1.1;letter-spacing:-1.8px;margin:25px 0 0}.screen{display:block;height:1550px;width:auto;margin:0 auto;box-shadow:0 8px 26px #243D5320}`);
    }
  }
} finally {
  socket?.close();
  chrome.kill();
  await delay(300);
  rmSync(profile, {recursive:true, force:true});
}
