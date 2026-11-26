import {canonicalSound, soundProfiles} from './sound-profiles.js';
import {defaults} from './defaults.js';
import {mountDeskPreview} from './desk.js';
import {styleWritingPreview,inkImpression,styleInkStrike} from './editor.js';
import {defaultSeal, drawSeal, limitSealText, normalizeSeal, sealColors, sealShapes, sealTextLimit} from './seal.js';

// Settings and letter box. Persisted keys and enum identifiers match InkrailCore.
const titled = values => values.map(([id,label,detail]) => ({id,label,detail}));
export const choices = Object.freeze({
  paper: titled([['ivory','Ivory','#eeecd9'],['cream','Cream','#e5d7b7'],['white','White','#f3f1e9']]),
  paperStartPosition: titled([['top','Top'],['bottom','Bottom']]),
  paperMotion: titled([['sheet','Sheet'],['roll','Paper roll']]),
  paperTexture: titled([['classic','Classic','The original fine grain'],['smooth','Smooth','A clean, even surface'],['laid','Laid','Fine lines in the paper'],['cotton','Cotton','Soft, irregular fibres']]),
  marginStyle: titled([['none','None'],['botanical','Botanical'],['ledger','Ledger'],['artDeco','Art Deco'],['celestial','Celestial']]),
  paperEmbossing: titled([['none','None','Unmarked paper'],['botanical','Botanical','A quiet botanical impression'],['monogram','Monogram','A small Inkrail imprint'],['sunburst','Sunburst','A subtle radiating seal'],['makerMark','Maker’s mark','The carriage initials pressed into paper']]),
  capsule: titled([['porcelain','Porcelain','#e5e2d6'],['sage','Sage','#86977c'],['cobalt','Cobalt','#3d609c'],['terracotta','Terracotta','#ad6548'],['graphite','Graphite','#454c4a']]),
  rail: titled([['steel','Steel'],['brass','Brass'],['charcoal','Charcoal']]),
  ribbon: titled([['carbon','Carbon','#292b26'],['midnight','Midnight','#213d57'],['oxblood','Oxblood','#591f24']]),
  writingFont: titled([['courier','Courier Prime','Heavier typewriter strokes with a distinct italic'],['americanTypewriter','American Typewriter','Rounded typewriter serif'],['menlo','Menlo','Clean monospaced text'],['georgia','Georgia','Warm, readable serif'],['courierNew','Courier New','Fine, familiar typewriter serif'],['typewriterLight','Typewriter Light','Airy American Typewriter'],['typewriterCondensed','Typewriter Condensed','Narrow American Typewriter'],['monaco','Monaco','Compact, rounded monospaced text']]),
  deskFinish: titled([['charcoal','Charcoal'],['walnut','Walnut'],['felt','Felt'],['linen','Linen'],['oak','Honey Oak'],['leather','Leather']]),
  deskAccent: titled([['none','None'],['sprig','Botanical sprig'],['paperclip','Paperclip'],['envelope','Envelope'],['brassLamps','Paired bronze lamps'],['linenLamps','Paired linen lamps']]),
  typewriterSound: titled(soundProfiles),
  mechanismStyle: titled([['classic','Classic','The original capsule'],['brushedSteel','Brushed Steel','Satin metal · fine ribs'],['champagne','Champagne','Soft gold · Art Deco'],['walnut','Walnut','Wood grain · brass'],['porcelain','Porcelain','Ivory glaze · sage'],['midnight','Midnight','Graphite · gold inlay'],['roseQuartz','Rose Quartz','Blush stone · pearl veins'],['seaGlass','Sea Glass','Frosted teal · silver'],['lavender','Lavender','Lilac enamel · soft shine'],['racingGreen','Racing Green','Deep green · ivory stripes'],['copper','Copper','Hammered metal · patina'],['wildflower','Wildflower','Cream enamel · tiny blooms']]),
});
export {defaults};
const bounds = {textureStrength:[0,1], embossingDepth:[0,1], fontSize:[15,28], inkStrength:[.35,1], inkBuildup:[0,1], soundVolume:[0,1], lampIntensity:[.25,1], lampWarmth:[0,1]};
export function normalizeSettings(source = {}) {
  return Object.fromEntries(Object.entries(defaults).map(([key, fallback]) => {
    const value = source?.[key];
    if (key === 'marginStyle' && value == null && source?.garden === true) return [key, 'botanical'];
    if (key === 'typewriterSound') return [key, canonicalSound(value)];
    if (choices[key]) return [key, choices[key].some(x => x.id === value) ? value : fallback];
    if (bounds[key]) return [key, Number.isFinite(value) ? Math.min(bounds[key][1], Math.max(bounds[key][0], value)) : fallback];
    return [key, typeof value === typeof fallback ? value : fallback];
  }));
}
const graphemes = new Intl.Segmenter(undefined, {granularity:'grapheme'});
function prefix(text, count) {
  let i=0;
  for (const item of graphemes.segment(text)) if (i++ === count) return text.slice(0,item.index);
  return text;
}
const firstLine = text => (text ?? '').split(/[\r\n\u0085\u2028\u2029\v\f]+/u).map(x=>x.trim()).find(Boolean) || 'Untitled letter';
export const pageTitle = page => page.privateTitle?.trim() || prefix(firstLine(page.text),64);
export function pagePreview(page) {
  const text = page.text ?? '';
  const terminals = /(?:(?<!\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|\p{L}\.\p{L}))\.(?=[\s\p{Pe}\p{Pf}"']|$)|(?=[^.])\p{Sentence_Terminal})\p{Sentence_Terminal}*[\p{Pe}\p{Pf}"']*/giu;
  let ends = 0, stop = text.length;
  for (const match of text.matchAll(terminals)) {
    if (++ends === 2) { stop = match.index + match[0].length; break; }
  }
  let result = text.slice(0,stop).trim().replace(/\s+/gu,' ');
  if (!result) return '';
  if (!ends) result = prefix(result,140).trimEnd();
  return result.replace(/\.+$/u,'') + '...';
}
const modified = page => typeof page.modifiedAt==='number' ? new Date(978307200000 + page.modifiedAt*1000) : new Date(page.modifiedAt);
const idOf = page => String(page.id);
export function letterGroups(pages, query = '', locale) {
  const key = query.toLocaleLowerCase(locale);
  const month = new Intl.DateTimeFormat(locale,{month:'long',year:'numeric'});
  const groups = new Map();
  const ordered = [...pages].sort((a,b)=>(+modified(b)||0)-(+modified(a)||0));
  for (const page of ordered) {
    if (key && !page.privateTitle?.toLocaleLowerCase(locale).includes(key) && !(page.text ?? '').toLocaleLowerCase(locale).includes(key)) continue;
    const d = modified(page);
    const dateKey = Number.isFinite(+d) ? d.getFullYear()+'-'+d.getMonth() : 'unknown';
    if (!groups.has(dateKey)) groups.set(dateKey,{month:Number.isFinite(+d)? month.format(d).toLocaleUpperCase(locale) : 'DATE UNAVAILABLE',pages:[]});
    groups.get(dateKey).pages.push(page);
  }
  return [...groups.values()];
}
const tabs = ['Paper','Type','Machine','Desk','Sound','Light','Storage'];
const preferredRail = {brushedSteel:'steel',champagne:'brass',walnut:'brass',porcelain:'charcoal',midnight:'charcoal',roseQuartz:'brass',seaGlass:'steel',lavender:'steel',racingGreen:'brass',copper:'charcoal',wildflower:'brass'};
const labelFor = (key,id) => choices[key].find(x=>x.id===id)?.label ?? '';
const el = (tag, cls='', text) => {
  const node=document.createElement(tag);
  if (cls) node.className=cls;
  if (text!=null) node.textContent=text;
  return node;
};
function append(node,...children) { node.append(...children.filter(Boolean)); return node; }
function button(text, action, cls='ip-plain') {
  const node=el('button',cls,text);
  node.type='button';
  node.addEventListener('click',action);
  return node;
}
function icon(name) {
  const ns='http://www.w3.org/2000/svg';
  const svg=document.createElementNS(ns,'svg');
  svg.classList.add('ip-glyph');
  svg.setAttribute('viewBox','0 0 24 24'); svg.setAttribute('aria-hidden','true');
  const path=document.createElementNS(ns,'path');
  path.setAttribute('d', {
    search:'M15.5 15.5 21 21M18 10.5a7.5 7.5 0 1 1-15 0 7.5 7.5 0 0 1 15 0Z',
    trash:'M4 7h16m-10 4v6m4-6v6M6 7l1 13h10l1-13m-9 0V4h6v3',
    edit:'M4 20h3l12-12-3-3L4 17v3Zm10-13 3 3',
    clear:'M5 5l14 14m0-14L5 19',
    play:'M8 5v14l11-7Z',
  }[name]);
  svg.append(path); return svg;
}
function iconButton(name,label,action) {
  const b=button('',action,'ip-plain ip-icon');
  b.title=label; b.setAttribute('aria-label',label); b.append(icon(name)); return b;
}
const note = text => el('p','ip-note',text);
function card(title, subtitle,...body) {
  return append(el('section','ip-card'), append(el('div','ip-card-title'),el('h3','',title),subtitle&&note(subtitle)),el('hr'),...body);
}
function row(left, right) { return append(el('div','ip-row'),left,right); }
function drawTypePreview(node,prefs) {
  styleWritingPreview(node,prefs);
  node.style.setProperty('--preview-paper', choices.paper.find(x=>x.id===prefs.paper)?.detail);
  const sample=el('span','ip-sample');
  const text='Some keys leave more ink.\nA few letters linger on the page.';
  if (prefs.wornInk) {
    for (const {segment,index} of graphemes.segment(text)) {
      if(!/^[!-~]$/.test(segment)){sample.append(document.createTextNode(segment));continue;}
      const letter=el('span','ip-ink-impression',segment);
      styleInkStrike(letter,inkImpression(index,text.charCodeAt(index),prefs.inkBuildup,prefs.fontSize));
      sample.append(letter);
    }
  } else sample.textContent=text;
  node.replaceChildren(sample);
}

export function mountPanels(root, callbacks = {}) {
  let prefs = normalizeSettings();
  let library = {pages:[],deleted:[],selectedID:null,trashWarning:''};
  let storage = {path:'',available:true,message:''};
  let kind=null, tab='paper', showDeleted=false, query='', activeBefore=null, revision=0;
  let busy=false, returnFromSub=null;
  const dialog=el('dialog','ip-dialog');
  const sub=el('dialog','ip-dialog ip-subdialog');
  const headingId='ip-dialog-heading', subheadingId='ip-subdialog-heading';
  dialog.setAttribute('aria-labelledby',headingId);
  sub.setAttribute('aria-labelledby',subheadingId);
  dialog.setAttribute('aria-modal','true'); sub.setAttribute('aria-modal','true');
  root.append(dialog,sub);
  let body,errorBox,nav,footer,libraryList,visibleShape='', searchInput, warningBox, bottom, previews=[];
  const libraryBusyButtons=new Set();

  function report(error) {
    if (!errorBox || !dialog.open) return;
    errorBox.textContent=error instanceof Error ? error.message : String(error);
    errorBox.hidden=false;
  }
  function clearError() { if (errorBox) errorBox.hidden=true; }
  function changeSettings(patch) {
    update({...prefs,...patch});
    try { Promise.resolve(callbacks.onSettings?.(patch)).catch(report); }
    catch(error) { report(error); }
  }
  function stopAudio() { callbacks.onStopSoundPreview?.(); }
  function close() {
    if (!dialog.open || (kind==='seal' && busy)) return false;
    if (sub.open) { if (!busy) sub.close(); return true; }
    const previous=kind;
    if (kind==='settings') {stopAudio(); cleanupPreviews();}
    kind=null; revision++; busy=false; dialog.close();
    if (previous==='seal') {
      dialog.querySelector('form').reset();
      dialog.replaceChildren();
      errorBox=null;
    }
    activeBefore?.focus?.({preventScroll:true});
    activeBefore=null;
    callbacks.onClose?.(previous);
    return true;
  }
  function open(type, page, forExport = false) {
    if (!dialog.open) activeBefore=document.activeElement;
    if (sub.open) sub.close();
    if (kind==='settings' && type!=='settings') {stopAudio(); cleanupPreviews();}
    kind=type; revision++; busy=false;
    dialog.classList.toggle('ip-library',type==='library');
    dialog.classList.toggle('ip-seal-dialog',type==='seal');
    if (type==='settings') buildSettings();
    else if (type==='seal') buildSeal(page, forExport);
    else { showDeleted=false; query=''; buildLibrary(); }
    if (!dialog.open) dialog.showModal();
    if (type==='settings') previews.forEach(hydratePreview);
    if (type==='library') searchInput.focus({preventScroll:true});
    else if (type==='seal') dialog.querySelector('input').select();
    else nav.querySelector('[aria-selected="true"]').focus({preventScroll:true});
  }
  dialog.addEventListener('cancel',ev=>{ ev.preventDefault(); close(); });
  sub.addEventListener('cancel',ev=>{ ev.preventDefault(); if (!busy) sub.close(); });
  sub.addEventListener('close',()=>{
    if (sub.open || !returnFromSub) return;
    const {page,action}=returnFromSub;returnFromSub=null;
    if (kind!=='library'||!dialog.open) return;
    const controls=[...libraryList.querySelectorAll('button[data-page]')];
    const target=controls.find(node=>node.dataset.page===page&&node.dataset.rowAction===action) ||
      controls.find(node=>node.dataset.rowAction===(showDeleted?'restore':'select')) || searchInput;
    target?.focus({preventScroll:true});
  });
  for (const d of [dialog,sub]) {
    let pressedOutside=false;
    function outside(e) {
      const r=d.getBoundingClientRect();
      return e.target===d && (e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom);
    }
    d.addEventListener('pointerdown',e=>{pressedOutside=outside(e);});
    d.addEventListener('pointercancel',()=>{pressedOutside=false;});
    d.addEventListener('click',e=>{
      if (pressedOutside && outside(e)) d===sub ? (!busy && sub.close()) : close();
      pressedOutside=false;
    });
  }
  function addError(parent) {
    errorBox=el('p','ip-error');
    errorBox.setAttribute('role','alert'); errorBox.hidden=true;
    parent.append(errorBox);
  }
  function makeHeader(title, subtitle, doneStyle, mono=false) {
    const titleNode=el('h2','',title);
    titleNode.id=headingId;
    return append(el('header','ip-header'+(mono?' ip-mono':'')),append(el('div'),titleNode,el('p','',subtitle)),button('Done',close,doneStyle));
  }
  function makePreview(mode, overrides={}) {
    const node=el('div','ip-preview ip-preview-'+mode);
    if (mode==='mechanismTile') node.setAttribute('aria-hidden','true');
    else { node.setAttribute('role','img'); node.setAttribute('aria-label',({paper:'Paper and type preview',type:'Typeface and ink preview',machine:'Selected slider and rail preview',desk:'Desk finish and accent preview',light:'Night lamp preview'})[mode]); }
    previews.push({node,mode,overrides});
    return node;
  }
  function cleanupPreviews() {
    for (const item of previews) item.renderer?.destroy();
    previews=[];
  }
  function hydratePreview(item) {
    const {node,mode,overrides}=item;
    const state={...prefs,...overrides};
    if (callbacks.renderPreview) {callbacks.renderPreview(node,state,mode);return;}
    if (mode==='type') {
      node.setAttribute('aria-label','Typeface and ink preview: '+labelFor('writingFont',state.writingFont)+', '+(state.wornInk?'worn ribbon':'even ink'));
      drawTypePreview(node,state);return;
    }
    const paintMode=mode==='mechanismTile'?'machine':mode==='light'?'lamp':mode;
    if (!item.renderer) item.renderer=mountDeskPreview(node,state,paintMode);
    else item.renderer.update(state);
    styleWritingPreview(node,state);
    if(mode==='paper') {
      node.setAttribute('aria-label','Paper and type preview: '+['paperMotion','paper','paperTexture','paperEmbossing','writingFont'].map(key=>labelFor(key,state[key])).join(', ')+', margin style '+labelFor('marginStyle',state.marginStyle));
      const sampleText=state.paperMotion==='roll'?'The paper rises.\nThe next line waits.':'The rain is soft.\nA little room to write.';
      const host=item.renderer.surface??node;
      if (!item.sample) item.sample=el('span','ip-sample ip-paper-sample');
      const sample=item.sample;
      if (sample.parentNode!==host) host.append(sample);
      sample.textContent=sampleText;
      sample.classList.toggle('ip-sample-bordered',state.marginStyle!=='none');
      sample.classList.toggle('ip-sample-roll',state.paperMotion==='roll');
      sample.classList.toggle('ip-sample-bottom',state.paperStartPosition==='bottom');
    } else if(mode==='desk') {
      node.setAttribute('aria-label','Desk finish and accent preview: '+labelFor('deskFinish',state.deskFinish)+', '+labelFor('deskAccent',state.deskAccent));
    } else if(mode==='light') {
      node.setAttribute('aria-label','Night lamp preview: '+(state.nightMode?'warmth '+Math.round(state.lampWarmth*100)+' percent':'lamp off'));
    }
  }
  function select(key,label) {
    const wrapper=el('span','ip-select-wrap');
    const field=el('select','ip-select');
    field.setAttribute('aria-label',label);
    field.dataset.bind=key;
    for (const choice of choices[key]) {
      const option=el('option','',choice.label); option.value=choice.id;
      field.append(option);
    }
    field.addEventListener('change',()=>changeSettings({[key]:field.value}));
    const icon=el('span','ip-select-tip','⌃');icon.setAttribute('aria-hidden','true');
    return row(el('span','',label),append(wrapper,field,icon));
  }
  function toggle(key,label) {
    const field=el('input','ip-toggle');
    field.type='checkbox';field.setAttribute('role','switch');field.dataset.bind=key;
    field.addEventListener('change',()=>changeSettings({[key]:field.checked}));
    return append(el('label','ip-toggle-line'),el('span','',label),field);
  }
  let sliderId=0;
  function slider(key,label,{percentage=true,unit='pt',disabledBy=''}={}) {
    const field=el('input','ip-range'), out=el('output','ip-range-value');
    field.type='range'; [field.min,field.max]=bounds[key]; field.step=percentage?.01:1;
    field.setAttribute('aria-label',label); field.dataset.bind=key; field.id='ip-range-'+(++sliderId);
    out.htmlFor=field.id;out.dataset.valueFor=key;out.dataset.unit=percentage?'%':' '+unit;
    if (disabledBy) field.dataset.disableBy=disabledBy;
    field.addEventListener('input',()=>changeSettings({[key]:field.valueAsNumber}));
    return append(el('label','ip-range-line'),el('span','',label),field,out);
  }
  function options(key,label, style) {
    const field=el('div','ip-options ip-'+style);
    field.setAttribute('role','group');field.setAttribute('aria-label',label);
    for (const {id,label:caption,detail} of choices[key]) {
      const b=button('',()=>changeSettings({[key]:id}),'ip-option');
      b.dataset.choiceKey=key;b.dataset.choiceVal=id;b.setAttribute('aria-pressed','false');
      if (style==='segmented') b.textContent=caption;
      if (style==='swatches') {
        const dot=el('i'); dot.style.backgroundColor=detail; dot.setAttribute('aria-hidden','true');
        b.append(dot,el('span','',caption));
      }
      if (style==='machine-grid') {
        b.setAttribute('aria-label',caption+' '+detail);
        b.append(makePreview('mechanismTile',{mechanismStyle:id}),el('span','ip-option-title',caption),el('small','',detail));
        b.title=caption+': '+detail;
      }
      if (style==='sound-grid') {
        b.setAttribute('aria-label',caption+' '+detail);
        b.dataset.disableBy='soundEnabled';
        b.append(el('span','ip-check'),append(el('span',''),el('span','ip-option-title',caption),el('small','',detail)));
      }
      field.append(b);
    }
    return style.endsWith('-grid')?field:row(el('span','',label),field);
  }
  const scenes=[['Leather study','Leather · bronze lamps','leather','brassLamps'],['Walnut study','Walnut · bronze lamps','walnut','brassLamps'],['Warm oak','Honey oak · linen lamps','oak','linenLamps']];
  function sceneChoices() {
    const out=el('div','ip-options ip-scenes');out.setAttribute('role','group');out.setAttribute('aria-label','Desk scenes');
    for (const [name,desc,deskFinish,deskAccent] of scenes) {
      const b=button('',()=>changeSettings({deskFinish,deskAccent}),'ip-option');
      b.dataset.scene=deskFinish;b.dataset.accent=deskAccent;
      b.setAttribute('aria-label',name+' '+desc);
      b.append(append(el('span','ip-scene-header'),el('span','ip-option-title',name),el('span','ip-check')),el('small','',desc));
      out.append(b);
    }
    return out;
  }
  function shape() { return [tab,prefs.paperTexture==='smooth',prefs.paperEmbossing==='none',prefs.wornInk,prefs.mechanismStyle==='classic',prefs.matchRailToStyle].join(); }
  function renderSettingsBody() {
    const top=body.scrollTop;
    const active=document.activeElement;
    const before=[active?.dataset.bind,active?.dataset.choiceKey, active?.dataset.choiceVal, active?.dataset.scene];
    cleanupPreviews();
    let nodes;
    switch (tab) {
      case 'paper':
        nodes=[makePreview('paper'),
          card('Page layout',null,options('paperMotion','Paper motion','segmented'),options('paperStartPosition','Start writing','segmented'),
            el('p','ip-note ip-start-note'),toggle('wideMargins','Wide margins')),
          card('Paper surface','Choose the feel of your sheet.',options('paper','Paper colour','swatches'),
            select('paperTexture','Texture'),prefs.paperTexture!=='smooth'&&slider('textureStrength','Texture detail'),toggle('curvedPaper','Curved upper corners'),
            select('marginStyle','Margin style')),
          card('Embossing','A quiet impression pressed into the paper.',select('paperEmbossing','Mark'),prefs.paperEmbossing!=='none'&&slider('embossingDepth','Relief'))];
        break;
      case 'type':
        nodes=[makePreview('type'),card('Typeface',null,select('writingFont','Writing font'),slider('fontSize','Type size',{percentage:false})),
          card('Ribbon & ink',null,toggle('wornInk','Worn ribbon'),prefs.wornInk&&slider('inkBuildup','Ink buildup'),
            prefs.wornInk&&note('Uneven strikes leave some letters darker and thicker, others faint.'),
            slider('inkStrength','Ink darkness'),options('ribbon','Ribbon colour','swatches')),
          note('Fonts and paper styling stay on your desk. Text exports contain your words.')];
        break;
      case 'machine':
        nodes=[makePreview('machine'),
          card('Slider styles','The same little machine. A different character.',options('mechanismStyle','Slider styles','machine-grid')),
          card('Finishes',null,prefs.mechanismStyle==='classic'?options('capsule','Capsule colour','swatches'):toggle('matchRailToStyle','Match rail to style'),
            prefs.mechanismStyle==='classic'||!prefs.matchRailToStyle?select('rail','Rail finish'):row(el('span','','Rail finish'),el('span','ip-preferred-rail')))];
        break;
      case 'desk':
        nodes=[makePreview('desk'),card('Around the paper',null,sceneChoices(),select('deskFinish','Desk finish'),select('deskAccent','Desk objects'),
          toggle('widerFocusPaper','Wider paper in Focus Mode'),note('Desk scenes appear outside Focus Mode. Narrow windows tuck objects away. Your paper, embossing and roll settings stay as you chose them.'))];
        break;
      case 'sound': {
        const preview=button('',()=>callbacks.onPreviewSound?.(),'ip-emphasis ip-preview-sound-button');
        preview.append(icon('play'),document.createTextNode('Preview sound'));
        nodes=[card('Typewriter sounds','The margin bell rings about seven character widths before the end of the line.',toggle('soundEnabled','Mechanical sounds'), options('typewriterSound','Typewriter sounds','sound-grid')),
          card('Listening level',null,slider('soundVolume','Volume',{disabledBy:'soundEnabled'}),
            row(preview,note('Keys, space bar, bell and return'))),
          note('Preview plays only when you press the button. Mute stops the sounds immediately.')];
        break;
      }
      case 'light':
        nodes=[makePreview('light'),card('Night writing','A soft pool of light around the next sentence.',toggle('nightMode','Night writing'),
          slider('lampIntensity','Lamp intensity',{disabledBy:'nightMode'}),append(el('div'),slider('lampWarmth','Warmth',{disabledBy:'nightMode'}),append(el('div','ip-warmth'),el('span','','Cool white'),el('span','','Amber')))),
          note('You can also click the capsule on your writing desk to toggle its lamp.')];
        break;
      case 'storage': {
        const path=el('p','ip-path',storage.path||'Path unavailable');
        path.setAttribute('aria-label','Letters folder: '+path.textContent);
        const change=button('Change Location…', e=>run('changeStorage',undefined,undefined,e.currentTarget),'ip-emphasis');
        change.disabled=!storage.available;
        nodes=[card('A home for your letters','Choose where Inkrail keeps your writing.',el('strong','ip-path-label','Letters folder'),path,
          append(el('div','ip-storage-actions'),change,button('Show in File Explorer',e=>run('revealStorage',undefined,undefined,e.currentTarget))),
          note('Choose a new or empty folder. Your letters, recently deleted letters and backups are copied there before future saves switch to the new location.'),
          note('Your previous folder stays intact as a safety copy. It will no longer receive changes.')),
          !storage.available&&card('Letters folder unavailable',null,note('Reconnect the drive or put the folder back, then reopen Inkrail. Export any unsaved writing before closing the app.')),
          storage.message&&card('Storage update',null,note(storage.message)),
          note('Keep a separate backup of your letters folder. Inkrail does not sync changes between folders or devices.')];
        break;
      }
    }
    body.replaceChildren(...nodes.filter(Boolean));
    visibleShape=shape();body.scrollTop=top;
    if (before.some(Boolean)) {
      Array.from(body.querySelectorAll('[data-bind],[data-choice-key],[data-scene]'))
        .find(x=>x.dataset.bind===before[0]&&x.dataset.choiceKey===before[1]&&x.dataset.choiceVal===before[2]&&x.dataset.scene===before[3])
        ?.focus({preventScroll:true});
    }
    reflectSettings();
  }
  function reflectSettings(renderPreviews=true) {
    for (const f of body.querySelectorAll('[data-bind]')) {
      const value=prefs[f.dataset.bind];
      if (f.type==='checkbox') f.checked=value; else f.value=String(value);
    }
    for (const chosen of body.querySelectorAll('[data-choice-key]')) chosen.setAttribute('aria-pressed',String(prefs[chosen.dataset.choiceKey]===chosen.dataset.choiceVal));
    for (const pick of body.querySelectorAll('[data-scene]')) pick.setAttribute('aria-pressed',String(prefs.deskFinish===pick.dataset.scene&&prefs.deskAccent===pick.dataset.accent));
    for (const f of body.querySelectorAll('[data-disable-by]')) f.disabled=!prefs[f.dataset.disableBy];
    for (const out of body.querySelectorAll('[data-value-for]')) {
      const val=prefs[out.dataset.valueFor];out.value = (out.dataset.unit==='%'?Math.round(val*100):Math.round(val))+out.dataset.unit;
    }
    const preview=body.querySelector('.ip-preview-sound-button');
    if (preview) preview.disabled=!prefs.soundEnabled||prefs.soundVolume===0;
    const rail=body.querySelector('.ip-preferred-rail');
    if (rail) rail.textContent=labelFor('rail',preferredRail[prefs.mechanismStyle]);
    const start=body.querySelector('.ip-start-note');
    if (start) start.textContent=prefs.paperStartPosition==='top'?'Start near the top. The paper feeds upward when the writing reaches the lower band.':'Start at the lower writing line. Each new line feeds the paper upward.';
    if (renderPreviews) previews.forEach(hydratePreview);
  }
  function activateTab(id,{focus=false}={}) {
    if (!tabs.some(t=>t.toLowerCase()===id)) id='paper';
    if (id!==tab) stopAudio();
    tab=id;
    for (const btn of nav.querySelectorAll('[role="tab"]')) {
      const active=btn.dataset.tab===tab;
      btn.setAttribute('aria-selected',String(active));
      btn.tabIndex=active?0:-1;
      if (active) {
        body.setAttribute('aria-labelledby',btn.id);
        if (focus) btn.focus();
      }
    }
    footer.firstElementChild.textContent=tab==='storage'?'Your letters · Your chosen folder':'Saved on this PC · Applies to your writing desk';
    clearError();
    body.scrollTop=0;
    renderSettingsBody();
  }
  function buildSettings() {
    const header=makeHeader('Make it yours.','A little character. A quieter desk.','ip-emphasis');
    nav=el('nav','ip-tabs');
    nav.setAttribute('role','tablist');nav.setAttribute('aria-label','Settings section');
    for (const [i,name] of tabs.entries()) {
      const id=name.toLowerCase();
      const b=button(name,()=>activateTab(id),'ip-tab');
      b.id='ip-tab-'+id;b.dataset.tab=id;b.setAttribute('role','tab');b.setAttribute('aria-controls','ip-settings-body');
      b.addEventListener('keydown',ev=>{
        let index;
        if (ev.key==='ArrowRight') index=(i+1)%tabs.length;
        else if (ev.key==='ArrowLeft') index=(i+tabs.length-1)%tabs.length;
        else if (ev.key==='Home') index=0;
        else if (ev.key==='End') index=tabs.length-1;
        else return;
        ev.preventDefault(); ev.stopPropagation();activateTab(tabs[index].toLowerCase(),{focus:true});
      });
      nav.append(b);
    }
    body=el('div','ip-settings-body');body.id='ip-settings-body';body.setAttribute('role','tabpanel');
    footer=append(el('footer','ip-settings-footer'),el('span'),el('span','','Made with ♥ by Aaryan Verma'));
    footer.lastElementChild.setAttribute('aria-label','Made with love by Aaryan Verma');
    dialog.replaceChildren(header,nav,body,footer);
    addError(dialog);
    dialog.insertBefore(errorBox,body);
    activateTab(tab);
  }
  function buildSeal(page, forExport) {
    const existing=normalizeSeal(page.seal);
    const draft={...(existing || defaultSeal)};
    const form=el('form','ip-seal-form');
    const heading=el('h2','',forExport?'Export interactive letter':'Letter seal');
    heading.id=headingId;
    const preview=el('div','ip-seal-preview');
    const field=el('input','ip-title-input');
    field.type='text';field.value=draft.text;field.autocomplete='off';
    const textLabel=el('label','ip-seal-field');
    textLabel.append(append(el('span','ip-seal-label'),el('span','','Seal text'),el('small','', 'Up to '+sealTextLimit+' characters')),field);
    const apply=el('button','ip-emphasis',forExport?'Continue to export…':existing?'Save changes':'Apply seal');
    apply.type='submit';
    const protection=forExport ? passwordOptions(updateApply) : null;
    function updateApply() {
      apply.disabled=busy || !normalizeSeal(draft) || (protection && !protection.valid());
    }
    function previewDraft() {
      const value=normalizeSeal(draft);
      preview.replaceChildren(drawSeal(value || {...draft,text:''}));
      updateApply();
    }
    function updateText(event) {
      if (event.isComposing) return;
      const limited=limitSealText(field.value);
      if (field.value!==limited) field.value=limited;
      draft.text=limited;
      previewDraft();
    }
    field.addEventListener('input',updateText);
    field.addEventListener('compositionend',updateText);
    function choiceField(key,label,choices) {
      const field=el('select','ip-select');
      for (const [id,name] of Object.entries(choices)) field.add(new Option(name,id));
      field.value=draft[key];
      field.onchange=()=>{draft[key]=field.value;previewDraft();};
      return append(el('label','ip-seal-field'),el('span','',label),field);
    }
    const choices=append(el('div','ip-seal-choices'),choiceField('shape','Shape',sealShapes),choiceField('color','Wax color',sealColors));
    const actions=el('footer','ip-confirm-actions');
    if (existing && !forExport) actions.append(button('Remove seal',async e=>{
      if (await run('setSeal',page.id,null,e.currentTarget,true)) close();
    },'ip-plain ip-remove-seal'));
    actions.append(button('Cancel',close),apply);
    form.addEventListener('submit',async e=>{
      e.preventDefault();
      const seal=normalizeSeal(draft);
      if (busy || !seal || (protection && !protection.valid())) return;
      const value=protection ? {seal,password:protection.password()} : seal;
      form.inert=true;
      const saved=await run(forExport?'exportInteractive':'setSeal',page.id,value,apply,!forExport);
      form.inert=false;
      if (saved) close();
      else { updateApply(); apply.focus(); }
    });
    form.append(heading,preview,textLabel,choices);
    if (protection) form.append(protection.section);
    addError(form);
    form.append(actions);
    dialog.replaceChildren(form);
    previewDraft();
  }
  function passwordOptions(onChange) {
    const section=el('div','ip-export-protection');
    const toggle=el('input');
    toggle.type='checkbox';
    toggle.name='protectLetter';
    const fields=el('div','ip-password-fields');
    const hint=note('Share the password separately. Inkrail can’t recover it.');
    const mismatch=note('The passwords don’t match.');
    mismatch.setAttribute('aria-live','polite');
    function field(name,label) {
      const input=el('input','ip-title-input');
      input.type='password'; input.name=name; input.autocomplete='new-password';
      input.spellcheck=false; input.autocapitalize='none';
      fields.append(append(el('label','ip-seal-field'),el('span','',label),input));
      return input;
    }
    const password=field('password','Password');
    const confirmation=field('confirmPassword','Confirm password');
    fields.append(hint,mismatch);
    fields.hidden=mismatch.hidden=true;
    section.append(append(el('label','ip-password-toggle'),toggle,el('span','','Require a password')),fields);

    function validate() {
      const differs=confirmation.value.length>0 && password.value!==confirmation.value;
      mismatch.hidden=!differs;
      confirmation.setAttribute('aria-invalid',String(differs));
      onChange();
    }
    toggle.onchange=()=>{
      fields.hidden=!toggle.checked;
      if (toggle.checked) password.focus();
      else { password.value=''; confirmation.value=''; }
      validate();
    };
    password.oninput=confirmation.oninput=validate;
    return {
      section,
      valid:()=>!toggle.checked || (password.value.length>0 && password.value===confirmation.value),
      password:()=>toggle.checked ? password.value : null
    };
  }
  function buildLibrary() {
    const header=makeHeader('Your letter box.','Everything you left on the page.','ip-plain',true);
    searchInput=el('input','ip-search');searchInput.type='search';
    searchInput.placeholder='Find a word, find a letter…';searchInput.setAttribute('aria-label', searchInput.placeholder);
    searchInput.spellcheck=false;searchInput.autocomplete='off';
    const clear=iconButton('clear','Clear search',()=>{searchInput.value='';searchInput.dispatchEvent(new Event('input'));searchInput.focus();});
    clear.hidden=true;
    searchInput.addEventListener('input',()=>{
      query=searchInput.value;
      clear.hidden=!query;
      renderLibraryRows();
    });
    const search=append(el('div','ip-search-line'),icon('search'),searchInput,clear);
    warningBox=el('p','ip-note ip-trash-warning');
    libraryList=el('div','ip-library-list');
    libraryList.setAttribute('role','region');
    libraryList.setAttribute('aria-label','Letters');
    bottom=el('footer','ip-library-footer');
    dialog.replaceChildren(header,search,warningBox,libraryList,bottom);
    addError(dialog);dialog.insertBefore(errorBox,libraryList);
    renderLibrary();
  }
  function renderLibrary() {
    dialog.querySelector('#'+headingId).textContent=showDeleted?'Recently deleted.':'Your letter box.';
    dialog.querySelector('.ip-header p').textContent=showDeleted?'Restorable for 30 days, then permanently deleted.':'Everything you left on the page.';
    warningBox.hidden=!showDeleted||!library.trashWarning;
    warningBox.textContent=showDeleted?(library.trashWarning||''):'';
    const toggleBtn=button(showDeleted?'Back to letters':'Recently deleted',async e=>{
      if (busy) return;
      const trigger=e.currentTarget;
      if (showDeleted) { showDeleted=false; clearError(); }
      else {
        showDeleted=true;
        const ok=await run('listTrash',undefined,undefined,trigger);
        if (!ok) showDeleted=false;
      }
      if (kind==='library') {
        libraryList.scrollTop=0;
        renderLibrary();
        bottom.firstElementChild?.focus({preventScroll:true});
      }
    });
    const right=el('div');
    if (!showDeleted) {
      right.append(button('Import',async e=>{ if (await run('import',undefined,undefined,e.currentTarget, true)) close(); }),
        button('+ New letter',async e=>{ if (await run('new',undefined,undefined,e.currentTarget, true)) close(); }));
    }
    bottom.replaceChildren(toggleBtn,right);
    renderLibraryRows();
  }
  function renderLibraryRows() {
    const active=document.activeElement;
    const before=[active?.dataset.page,active?.dataset.rowAction];
    const top=libraryList.scrollTop;
    const groups=letterGroups(showDeleted?library.deleted:library.pages,query);
    const children=[];
    libraryBusyButtons.clear();
    if (!groups.length) children.push(el('p','ip-empty',showDeleted?'No recently deleted letters.':'No letters found.'));
    for (const {month,pages} of groups) {
      const section=append(el('section','ip-month'),el('h3','',month));
      for (const page of pages) section.append(letterRow(page));
      children.push(section);
    }
    libraryList.replaceChildren(...children);
    libraryList.scrollTop=top;
    if (before[0]) {
      const replacement=Array.from(libraryList.querySelectorAll('button[data-page]')).find(b=>b.dataset.page===before[0]&&b.dataset.rowAction===before[1]);
      replacement?.focus({preventScroll:true});
    }
  }
  function letterRow(page) {
    const id=idOf(page), title=pageTitle(page), d=modified(page);
    const selected=!showDeleted&&library.selectedID!=null&&String(library.selectedID).toLowerCase()===id.toLowerCase();
    const item=el('article','ip-letter-row'+(selected?' ip-current':''));
    item.dataset.page=id;
    let content;
    if (showDeleted) content=el('div','ip-open-letter');
    else {
      content=button('',async e=>{ if (await run('select',id,undefined,e.currentTarget,true)) close(); },'ip-open-letter');
      content.setAttribute('aria-label','Open '+title);
      if (selected) content.setAttribute('aria-current','true');
      markAction(content,id,'select');
    }
    const top=append(el('span','ip-letter-top'),el('span','ip-letter-title',title),el('time','',Number.isFinite(+d)?new Intl.DateTimeFormat(undefined,{day:'numeric'}).format(d):''));
    if (Number.isFinite(+d)) top.lastElementChild.dateTime=d.toISOString();
    content.append(top,el('span','ip-letter-preview',pagePreview(page)||'An unwritten page.'));
    item.append(content);
    let controls=[];
    if (showDeleted) {
      const restore=button('Restore',e=>run('restore',id,undefined,e.currentTarget));
      restore.setAttribute('aria-label','Restore '+title);
      markAction(restore,id,'restore');controls.push(restore);
    } else {
      const rename=iconButton('edit','Rename '+title,()=>openRename(page));
      const del=iconButton('trash','Delete '+title,()=>openTrash(page));
      del.title='Move to Recently Deleted';
      markAction(rename,id,'rename');markAction(del,id,'trash');
      controls.push(rename,del);
      // Windows keyboard alternative to the visible rename icon.
      item.addEventListener('keydown',e=>{if(e.key==='F2'){e.preventDefault();openRename(page);}});
      item.addEventListener('contextmenu',e=>{e.preventDefault();openRename(page);});
    }
    item.append(append(el('span','ip-letter-actions'),...controls));
    return item;
  }
  function markAction(node,id,action) {
    node.dataset.page=id;node.dataset.rowAction=action;node.disabled=busy;
    libraryBusyButtons.add(node);
  }
  async function run(action,id,value,trigger,successFalsy=false) {
    if (busy) return false;
    const at=revision;
    const subAlert=sub.open?sub.querySelector('.ip-error'):null;
    if (subAlert) subAlert.hidden=true; else clearError();
    busy=true;
    if(trigger) trigger.disabled=true;
    libraryBusyButtons.forEach(x=>{x.disabled=true;});
    let ok=false;
    try {
      const response=await callbacks.onAction?.(action,id,value);
      ok=revision===at && (!successFalsy || response!==false);
    } catch (error) {
      if (revision===at) {
        if (subAlert) {
          subAlert.textContent=error instanceof Error?error.message:String(error);
          subAlert.hidden=false;
        } else report(error);
      }
    } finally {
      if (revision===at) {
        busy=false;
        const cancelLock=action==='changeStorage'&&!storage.available;
        if(trigger) trigger.disabled=cancelLock;
        libraryBusyButtons.forEach(x=>{x.disabled=false;});
      }
    }
    return ok;
  }
  function openSub(title,detail,body,confirmLabel,confirm,returnFocus) {
    if (busy||sub.open) return false;
    returnFromSub=returnFocus;
    const titleNode=el('h3','',title);titleNode.id=subheadingId;
    const caption=note(detail); caption.id='ip-sub-caption';
    sub.setAttribute('aria-describedby',caption.id);
    const alert=el('p','ip-error');alert.setAttribute('role','alert');alert.hidden=true;
    const form=el('form','ip-confirm-form');
    const cancel=button('Cancel',()=>{if(!busy) sub.close();});
    const submit=el('button',confirmLabel==='Move Letter'?'ip-emphasis ip-destructive':'ip-emphasis',confirmLabel);
    submit.type='submit';
    form.addEventListener('submit',async e=>{
      e.preventDefault();
      if (await confirm(submit) && sub.open) sub.close();
    });
    form.append(titleNode,...(body?[body]:[]),caption,alert,append(el('footer','ip-confirm-actions'),cancel,submit));
    sub.replaceChildren(form);
    sub.showModal();
    (body||cancel).focus({preventScroll:true});
    return true;
  }
  function openRename(page) {
    const field=el('input','ip-title-input');field.type='text';field.setAttribute('aria-label','Private title');
    field.placeholder='Private title';field.autocomplete='off';
    field.value=page.privateTitle||'';
    if (openSub('Rename letter','This title appears only in your letter box. Leave it blank to use the first line.',field,'Save',
      trigger=>run('rename',idOf(page),field.value,trigger),{page:idOf(page),action:'rename'})) field.select();
  }
  function openTrash(page) {
    openSub('Move this letter to Recently Deleted?','You can restore it from the letter box for 30 days. After that, it will be permanently deleted.',null,'Move Letter',
      trigger=>run('trash',idOf(page),undefined,trigger),{page:idOf(page),action:'trash'});
  }
  function update(values) {
    const next=normalizeSettings(values);
    const changed=Object.keys(defaults).filter(key=>prefs[key]!==next[key]);
    if (!changed.length) return;
    if (changed.some(k=>['soundEnabled','typewriterSound','soundVolume'].includes(k))) stopAudio();
    prefs=next;
    if (kind==='settings') {
      if (shape()!==visibleShape) renderSettingsBody();
      else reflectSettings();
    }
  }
  return {
    showSettings(section='paper') {
      const next=String(section).toLowerCase();
      if (kind==='settings' && dialog.open) {activateTab(next,{focus:true});return;}
      tab=tabs.some(t=>t.toLowerCase()===next)?next:'paper';
      open('settings');
    },
    showLibrary() { open('library'); },
    showSeal(page, forExport = false) { open('seal',page,forExport); },
    close,
    isOpen() {return dialog.open;},
    update,
    setLibrary(values={}) {
      library={...library,...values};
      if (kind==='library') {
        warningBox.hidden=!showDeleted||!library.trashWarning;
        warningBox.textContent=showDeleted?(library.trashWarning||''):'';
        renderLibraryRows();
      }
    },
    setStorage(values={}) {
      const before=storage;
      storage={...storage,...values};
      if (kind==='settings'&&tab==='storage'&&Object.keys(storage).some(key=>storage[key]!==before[key])) renderSettingsBody();
    },
    destroy() { if(sub.open) sub.close(); if(dialog.open) close(); dialog.remove(); sub.remove(); },
  };
}
