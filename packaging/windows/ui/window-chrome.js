// Linux draws no system title bar: the desk is the title area. Window controls
// sit in the top-right corner in the header's style, the desk background moves
// the window (double-click maximizes) and F11, handled natively, goes full screen.
import {call} from './bridge.js';

export const nativeChrome = location.protocol === 'inkrail:';

const icons = {
  minimize: '<path d="M5.5 10.5h9"/>',
  maximize: '<rect x="5.5" y="5.5" width="9" height="9" rx="1.6"/>',
  restore: '<rect x="4.5" y="7.5" width="8" height="8" rx="1.4"/><path d="M7.5 7.5V6c0-.8.6-1.5 1.5-1.5h5.5c.8 0 1.5.7 1.5 1.5v5.5c0 .8-.7 1.5-1.5 1.5h-2"/>',
  close: '<path d="m6 6 8 8m0-8-8 8"/>',
};

// Anything interactive, and the paper itself, keeps its normal behaviour.
const notDraggable = 'button,a,input,textarea,select,label,[contenteditable],[role=menu],[role=menuitem],dialog,' +
  '.ink-desk__paper,.ink-desk__capsule,.w-controls';

export function mountWindowChrome() {
  if (!nativeChrome) return;
  const root = document.documentElement;
  root.dataset.chrome = 'native';

  const bar = document.createElement('div');
  bar.className = 'w-controls';
  bar.setAttribute('role', 'group');
  bar.setAttribute('aria-label', 'Window');
  const make = (op, label, icon, extra = '') => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 's-btn w-btn ' + extra;
    b.title = label;
    b.setAttribute('aria-label', label);
    b.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true">' + icons[icon] + '</svg>';
    b.addEventListener('mousedown', e => e.preventDefault()); // Keep the caret in the letter.
    b.onclick = () => void call(op).catch(() => {});
    bar.append(b);
    return b;
  };
  make('windowMinimize', 'Minimize', 'minimize');
  const maximize = make('windowMaximize', 'Maximize', 'maximize');
  make('windowClose', 'Close', 'close', 'w-close');
  document.body.append(bar);

  const hint = document.createElement('div');
  hint.className = 'w-hint';
  hint.setAttribute('role', 'status');
  hint.textContent = 'Press F11 to exit full screen';
  document.body.append(hint);
  let hintTimer = 0;

  function apply({maximized = false, fullscreen = false} = {}) {
    const was = root.dataset.fullscreen === 'true';
    root.dataset.maximized = String(maximized);
    root.dataset.fullscreen = String(fullscreen);
    const label = maximized ? 'Restore' : 'Maximize';
    maximize.title = label;
    maximize.setAttribute('aria-label', label);
    maximize.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true">' + icons[maximized ? 'restore' : 'maximize'] + '</svg>';
    if (fullscreen && !was) {
      clearTimeout(hintTimer);
      hint.classList.add('w-hint--shown');
      hintTimer = setTimeout(() => hint.classList.remove('w-hint--shown'), 2600);
    } else if (!fullscreen) hint.classList.remove('w-hint--shown');
  }
  window.addEventListener('inkrail-window-state', e => apply(e.detail));
  call('windowState').then(apply, () => {});

  window.addEventListener('mousedown', e => {
    if (e.button !== 0 || !e.target.closest?.('#desk') || e.target.closest(notDraggable)) return;
    e.preventDefault();
    void call(e.detail === 2 ? 'windowMaximize' : 'windowDrag').catch(() => {});
  });
}

export const toggleFullscreen = () => call('windowFullscreen');
