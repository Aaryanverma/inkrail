import {emphasis, expandFormatting, markdownLines} from './markdown.js';
import {hasLetterText, normalizeSeal} from './seal.js';

const inlineTags = [
  [emphasis.bold, 'strong'], [emphasis.italic, 'em'], [emphasis.underline, 'u'],
  [emphasis.strikethrough, 'del'], [emphasis.code, 'code']
];

function escapeText(text) {
  return text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

function letterBody({text, formatting}) {
  const styles = expandFormatting(text, formatting);
  return markdownLines(text).map(({start, end, block, literal}) => {
    let tag = 'p', className = '';
    const prefix = block && text.slice(start + block.source.length, end).trim() ? block : null;
    if (prefix?.kind === 'heading') {
      tag = 'h' + prefix.level;
      start += prefix.source.length;
    } else if (prefix?.kind === 'quote') tag = 'blockquote';
    else if (prefix?.kind === 'list') className = ' class="list-line"';
    else if (literal) className = ' class="literal-line"';

    const pieces = [];
    for (let i = start; i < end;) {
      const from = i, mask = styles[i++];
      while (i < end && styles[i] === mask) i++;
      let content = escapeText(text.slice(from, i));
      for (const [bit, name] of inlineTags) {
        if (mask & bit) content = '<' + name + '>' + content + '</' + name + '>';
      }
      pieces.push(content);
    }
    return '<' + tag + className + ' dir="auto">' + (pieces.join('') || '<br>') + '</' + tag + '>';
  }).join('\n');
}

export function interactiveLetterHTML(template, page, settings, seal, {wax, grain, rustle}) {
  const imprint = normalizeSeal(seal);
  if (!imprint || !hasLetterText(page.text)) throw new Error('Add writing and choose a seal to export this letter.');
  const {paper, ribbon, writingFont, fontSize, wideMargins, paperTexture, textureStrength,
    paperEmbossing, embossingDepth, marginStyle, inkStrength} = settings;
  const payload = JSON.stringify({seal: imprint, paper, ribbon, writingFont, fontSize, wideMargins,
    paperTexture, textureStrength, paperEmbossing, embossingDepth, marginStyle, inkStrength})
    .replaceAll('<', '\\u003c').replaceAll('>', '\\u003e').replaceAll('&', '\\u0026');
  const slots = {BODY: letterBody(page), PAYLOAD: payload, INSCRIPTION: escapeText(imprint.text), WAX: wax, GRAIN: grain, RUSTLE: rustle};
  return template.replace(/__INKRAIL_(BODY|PAYLOAD|INSCRIPTION|WAX|GRAIN|RUSTLE)__/g, (_, key) => slots[key]);
}

async function asset(name) {
  const response = await fetch(new URL('./assets/' + name, import.meta.url));
  if (!response.ok) throw new Error('Could not load ' + name + ' from Inkrail’s installation.');
  return response;
}

function base64Blob(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error);
    reader.onload = () => resolve(reader.result.slice(reader.result.indexOf(',') + 1));
    reader.readAsDataURL(blob);
  });
}

async function base64Asset(name) {
  return base64Blob(await (await asset(name)).blob());
}

export async function protectInteractiveLetter(template, html, password) {
  if (typeof password !== 'string' || !password.length) throw new Error('Enter a password for this letter.');
  if (!crypto.subtle) throw new Error('This browser cannot encrypt the letter. Update Microsoft Edge WebView2 and try again.');
  const slot = '__INKRAIL_ENCRYPTED__';
  if (template.split(slot).length !== 2) throw new Error('The protected letter template is incomplete.');

  const utf8 = new TextEncoder();
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const material = await crypto.subtle.importKey('raw', utf8.encode(password), 'PBKDF2', false, ['deriveKey']);
  const key = await crypto.subtle.deriveKey(
    {name: 'PBKDF2', hash: 'SHA-256', iterations: 600000, salt}, material,
    {name: 'AES-GCM', length: 256}, false, ['encrypt']
  );
  const encrypted = await crypto.subtle.encrypt({name: 'AES-GCM', iv, tagLength: 128}, key, utf8.encode(html));
  const payload = {
    version: 1, salt: btoa(String.fromCharCode(...salt)), iv: btoa(String.fromCharCode(...iv)),
    ciphertext: await base64Blob(new Blob([encrypted]))
  };
  return template.replace(slot, () => JSON.stringify(payload));
}

export async function makeInteractiveLetter(page, settings, seal, password = null) {
  const [template, wax, grain, rustle] = await Promise.all([
    asset('InteractiveLetter.html').then(response => response.text()),
    base64Asset('letter-seal-wax.png'), base64Asset('paper-grain.png'), base64Asset('paper-unfold.mp3')
  ]);
  const html = interactiveLetterHTML(template, page, settings, seal, {wax, grain, rustle});
  if (password === null) return html;
  const lock = await asset('ProtectedInteractiveLetter.html');
  return protectInteractiveLetter(await lock.text(), html, password);
}
