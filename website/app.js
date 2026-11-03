(() => {
  const root = document.documentElement;
  const themeButton = document.querySelector('.theme-toggle');
  let savedTheme;
  try { savedTheme = localStorage.getItem('jiaxintie-theme'); } catch {}
  if (savedTheme === 'dark' || savedTheme === 'light') root.dataset.theme = savedTheme;
  const currentDark = () => root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
  const updateThemeLabel = () => themeButton?.setAttribute('aria-label', currentDark() ? '切换浅色模式' : '切换深色模式');
  updateThemeLabel();
  themeButton?.addEventListener('click', () => {
    const theme = currentDark() ? 'light' : 'dark';
    root.dataset.theme = theme;
    try { localStorage.setItem('jiaxintie-theme', theme); } catch {}
    updateThemeLabel();
  });

  const stage = document.querySelector('.demo-stage');
  const pin = document.querySelector('.demo-pin');
  const handle = document.querySelector('.pin-handle');
  const caption = document.querySelector('.demo-caption');
  const descriptions = {
    capture: ['F1', '框住一点灵感', '操作示意 · 按 F1 拖动框选，再按 F1 完成复制'],
    annotate: ['S', '加一点自己的标注', '操作示意 · 圈出重点，加一个箭头，写一句话'],
    pin: ['F3', '留在顺手的位置', '操作示意 · 拖动图片顶部，试试贴在不同的位置']
  };
  document.querySelectorAll('[data-demo-step]').forEach(button => {
    button.addEventListener('click', () => {
      const step = button.dataset.demoStep;
      if (!stage || !descriptions[step]) return;
      stage.dataset.step = step;
      pin.style.left = ''; pin.style.top = '';
      handle.disabled = step !== 'pin';
      document.querySelectorAll('[data-demo-step]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
      stage.querySelector('.floating-key kbd').textContent = descriptions[step][0];
      caption.textContent = descriptions[step][2];
    });
  });
  if (handle) handle.disabled = true;
  let drag;
  handle?.addEventListener('pointerdown', event => {
    if (stage.dataset.step !== 'pin' || event.button !== 0) return;
    const rect = pin.getBoundingClientRect();
    const parent = stage.getBoundingClientRect();
    // Work in the parent's layout coordinates, including browser zoom and scale.
    const sx = stage.clientWidth / parent.width;
    const sy = stage.clientHeight / parent.height;
    drag = { id: event.pointerId, x: event.clientX, y: event.clientY, left: pin.offsetLeft, top: pin.offsetTop, sx, sy };
    pin.classList.add('is-dragging'); handle.setPointerCapture(event.pointerId);
    event.preventDefault();
  });
  handle?.addEventListener('pointermove', event => {
    if (!drag || drag.id !== event.pointerId) return;
    const left = Math.max(5, Math.min(stage.clientWidth - pin.offsetWidth - 5, drag.left + (event.clientX - drag.x) * drag.sx));
    const top = Math.max(40, Math.min(stage.clientHeight - pin.offsetHeight - 6, drag.top + (event.clientY - drag.y) * drag.sy));
    pin.style.left = `${left}px`; pin.style.top = `${top}px`;
  });
  const endDrag = () => { drag = null; pin?.classList.remove('is-dragging'); };
  handle?.addEventListener('pointerup', endDrag);
  handle?.addEventListener('pointercancel', endDrag);
  handle?.addEventListener('lostpointercapture', endDrag);
  handle?.addEventListener('keydown', event => {
    if (stage.dataset.step !== 'pin' || !['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key)) return;
    event.preventDefault();
    const dx = event.key === 'ArrowLeft' ? -12 : event.key === 'ArrowRight' ? 12 : 0;
    const dy = event.key === 'ArrowUp' ? -12 : event.key === 'ArrowDown' ? 12 : 0;
    pin.style.left = `${Math.max(5, Math.min(stage.clientWidth - pin.offsetWidth - 5, pin.offsetLeft + dx))}px`;
    pin.style.top = `${Math.max(40, Math.min(stage.clientHeight - pin.offsetHeight - 6, pin.offsetTop + dy))}px`;
  });

  let lastShot = 3;
  document.querySelector('.cache-next')?.addEventListener('click', () => {
    lastShot += 1;
    const slots = document.querySelector('.cache-slots');
    slots.firstElementChild.remove();
    const item = document.createElement('div');
    const symbol = document.createElement('span'); symbol.textContent = ['✳','↗','♡'][lastShot % 3];
    const label = document.createElement('small'); label.textContent = `截图 ${String(lastShot).padStart(2,'0')}`;
    item.append(symbol, label); slots.append(item);
    document.querySelector('.cache-status').textContent = `规则示意：保留截图 ${lastShot - 2}、${lastShot - 1}、${lastShot}，手动图片不变。`;
  });
})();
