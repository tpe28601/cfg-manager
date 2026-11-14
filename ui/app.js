// Agents Cfg Manager Web 前端（vanilla JS）
'use strict';

const $ = s => document.querySelector(s);
const $$ = s => Array.from(document.querySelectorAll(s));

const state = {
  sourceRoot: '', label: 'project', items: [],
  includeAuth: false, zipDir: '', targetRoot: '', namePattern: '',
  profiles: [], zipInfo: null
};

async function api(path, opts = {}) {
  const r = await fetch(path, opts);
  let j = null;
  try { j = await r.json(); } catch (e) { /* empty body */ }
  if (!r.ok || (j && j.error)) {
    const msg = (j && j.error && (j.error.message || j.error)) || ('HTTP ' + r.status);
    throw new Error(msg);
  }
  return j;
}
function post(path, data) {
  return api(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Toolbox-Request': '1' },
    body: JSON.stringify(data || {})
  });
}

let toastTimer = null;
function toast(msg, isError) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.toggle('tb-toast--danger', !!isError);
  t.classList.toggle('tb-toast--ok', !isError);
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, isError ? 6000 : 3000);
}
function show(el, text) { el.hidden = false; el.textContent = text; }

function openActionDialog(title, options = {}) {
  const dialog = $('#action-dialog');
  const message = $('#action-message');
  const field = $('#action-field');
  const input = $('#action-input');
  const accept = $('#action-accept');
  const hasInput = Boolean(options.label);
  $('#action-title').textContent = title;
  message.textContent = options.message || '';
  message.hidden = !options.message;
  if (options.message) dialog.setAttribute('aria-describedby', message.id);
  else dialog.removeAttribute('aria-describedby');
  field.hidden = !hasInput;
  $('#action-label').textContent = options.label || '';
  input.disabled = !hasInput;
  input.required = hasInput && !options.readOnly;
  input.readOnly = Boolean(options.readOnly);
  input.value = options.value || '';
  accept.hidden = Boolean(options.readOnly);
  accept.disabled = Boolean(options.readOnly);
  accept.textContent = options.accept || '確認';
  accept.className = 'tb-btn ' + (options.danger ? 'tb-btn--danger' : 'tb-btn--primary');
  $('#action-cancel').textContent = options.readOnly ? '關閉' : '取消';
  return new Promise(resolve => {
    const listeners = new AbortController();
    function finish(value) {
      listeners.abort();
      dialog.close();
      resolve(value);
    }
    dialog.addEventListener('submit', event => {
      event.preventDefault();
      const accepted = event.submitter === accept && !accept.disabled;
      finish(accepted ? (hasInput ? input.value.trim() : true) : null);
    }, { signal: listeners.signal });
    dialog.addEventListener('cancel', event => {
      event.preventDefault();
      finish(null);
    }, { signal: listeners.signal });
    dialog.showModal();
    if (hasInput) {
      input.focus();
      if (options.readOnly) input.select();
    }
  });
}

function fmtBytes(b) {
  if (b === null || b === undefined) return '-';
  const u = ['B', 'KB', 'MB', 'GB'];
  let i = 0, v = Number(b);
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return (i === 0 ? v : v.toFixed(1)) + ' ' + u[i];
}
function currentScopeData() {
  return {
    sourceRoot: $('#pack-src').value.trim(),
    label: state.label,
    items: state.items.map(it => ({ path: it.path, enabled: it.enabled, exclude: it.exclude })),
    includeAuth: $('#pack-auth').checked,
    zipDir: $('#pack-zipdir').value.trim(),
    targetRoot: $('#unp-tgt').value.trim() || state.targetRoot,
    updated: new Date().toISOString()
  };
}
const saveLast = debounce(() => { post('/api/profiles/last', { data: currentScopeData() }).catch(() => {}); }, 800);
function debounce(fn, ms) { let t = null; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; }

// ---------------- Tabs ----------------
$$('#tabs .tb-tab').forEach(btn => btn.addEventListener('click', () => {
  $$('#tabs .tb-tab').forEach(b => {
    b.classList.toggle('is-active', b === btn);
    b.setAttribute('aria-pressed', String(b === btn));
  });
  $$('.page').forEach(p => p.classList.remove('active'));
  $('#page-' + btn.dataset.tab).classList.add('active');
  if (btn.dataset.tab === 'profiles') loadProfiles();
  if (btn.dataset.tab === 'history') loadHistory();
}));

// ---------------- 範圍項目表 ----------------
function renderScope() {
  const tb = $('#scope-table tbody');
  tb.innerHTML = '';
  if (!state.items.length) {
    tb.innerHTML = '<tr><td colspan="4" class="ac-empty">尚未加入項目。可載入內建範圍，或從下方新增。</td></tr>';
  }
  state.items.forEach((it, idx) => {
    const tr = document.createElement('tr');

    const tdUse = document.createElement('td');
    const cb = document.createElement('input');
    cb.type = 'checkbox'; cb.checked = it.enabled;
    cb.setAttribute('aria-label', '啟用項目 ' + (idx + 1));
    cb.addEventListener('change', () => {
      it.enabled = cb.checked;
      tr.classList.toggle('off', !cb.checked);
      saveLast();
    });
    tdUse.appendChild(cb);

    const tdPath = document.createElement('td');
    const inp = document.createElement('input');
    inp.type = 'text'; inp.value = it.path; inp.spellcheck = false;
    inp.className = 'tb-input tb-input--mono';
    inp.setAttribute('aria-label', '項目 ' + (idx + 1) + ' 的相對路徑');
    inp.addEventListener('change', () => { it.path = inp.value.trim(); saveLast(); });
    tdPath.appendChild(inp);

    const tdEx = document.createElement('td');
    const ex = document.createElement('input');
    ex.type = 'text'; ex.value = (it.exclude || []).join(', ');
    ex.className = 'tb-input tb-input--mono';
    ex.setAttribute('aria-label', '項目 ' + (idx + 1) + ' 的排除樣式');
    ex.placeholder = '*.log, *.tmp';
    ex.addEventListener('change', () => {
      it.exclude = ex.value.split(',').map(s => s.trim()).filter(Boolean);
      saveLast();
    });
    tdEx.appendChild(ex);

    const tdDel = document.createElement('td');
    const del = document.createElement('button');
    del.type = 'button'; del.className = 'tb-btn tb-btn--danger tb-btn--sm'; del.textContent = '刪除';
    del.setAttribute('aria-label', '刪除項目 ' + (idx + 1));
    del.addEventListener('click', () => { state.items.splice(idx, 1); renderScope(); saveLast(); });
    tdDel.appendChild(del);

    tr.append(tdUse, tdPath, tdEx, tdDel);
    if (!it.enabled) tr.classList.add('off');
    tb.appendChild(tr);
  });
}

$('#scope-add').addEventListener('click', () => {
  const p = $('#new-item-path').value.trim();
  if (!p) { toast('請輸入項目路徑', true); return; }
  const ex = $('#new-item-exclude').value.split(',').map(s => s.trim()).filter(Boolean);
  state.items.push({ path: p, enabled: true, exclude: ex });
  $('#new-item-path').value = ''; $('#new-item-exclude').value = '';
  renderScope(); saveLast();
});

$('#pack-preset').addEventListener('change', async e => {
  const preset = e.target.value;
  e.target.value = '';
  if (!preset) return;
  const d = await api('/api/defaults/items');
  state.items = (d[preset] || []).map(x => ({ path: x.path, enabled: x.enabled !== false, exclude: x.exclude || [] }));
  renderScope(); saveLast();
  toast('已載入內建範圍: ' + preset);
});

async function scanScope() {
  const body = { sourceRoot: $('#pack-src').value.trim(), items: state.items };
  if (!body.sourceRoot) throw new Error('請先輸入來源根目錄');
  return post('/api/items/scan', body);
}

function renderScan(r) {
  let txt = '項目統計:\n';
  r.items.forEach(s => {
    txt += '  ' + s.path.padEnd(30) + String(s.count).padStart(6) + ' 檔  ' + fmtBytes(s.bytes) +
           (s.error ? '   <- ' + s.error : '') + '\n';
  });
  txt += '\n合計: ' + r.count + ' 檔 / ' + fmtBytes(r.bytes) + '\n';
  if (r.sample && r.sample.length) {
    txt += '\n檔案範例（前 ' + r.sample.length + ' 筆）:\n';
    r.sample.slice(0, 50).forEach(f => { txt += '  ' + fmtBytes(f.length).padStart(10) + '  ' + f.rel + '\n'; });
    if (r.truncated) txt += '  ...(已截斷)\n';
  }
  return txt;
}

// ---------------- 打包頁 ----------------
$('#scope-preview').addEventListener('click', async () => {
  try { show($('#pack-out'), renderScan(await scanScope())); }
  catch (e) { toast(e.message, true); }
});

function packBody(dryRun) {
  return {
    sourceRoot: $('#pack-src').value.trim(),
    zipDir: $('#pack-zipdir').value.trim(),
    namePattern: $('#pack-namepat').value.trim(),
    label: state.label,
    items: state.items,
    includeAuth: $('#pack-auth').checked,
    targetRoot: $('#unp-tgt').value.trim(),
    dryRun
  };
}

$('#pack-dry').addEventListener('click', async () => {
  try {
    const r = await post('/api/pack', packBody(true));
    show($('#pack-out'), renderScan(r) + '\n將輸出: ' + r.zipOut);
  } catch (e) { toast(e.message, true); }
});

$('#pack-run').addEventListener('click', async () => {
  if (!await openActionDialog('執行打包', { accept: '打包' })) return;
  try {
    const r = await post('/api/pack', packBody(false));
    show($('#pack-out'), '完成!\n輸出: ' + r.zip + '\n檔案數: ' + r.count +
         (r.skipped ? '（跳過 ' + r.skipped + ' 檔）' : '') +
         '\n來源大小: ' + fmtBytes(r.sourceBytes) + '\nzip 大小: ' + fmtBytes(r.zipBytes));
    toast('打包完成: ' + r.zip);
  } catch (e) { toast(e.message, true); }
});

$('#pack-save').addEventListener('click', () => saveProfileAs());

// ---------------- Profiles ----------------
async function saveProfileAs() {
  const name = await openActionDialog('儲存設定檔', { label: '設定檔名稱', accept: '儲存' });
  if (!name) return;
  try {
    await post('/api/profiles/save', { name, data: currentScopeData() });
    toast('已儲存設定檔: ' + name);
    loadProfiles();
  } catch (e) { toast(e.message, true); }
}

async function loadProfiles() {
  try {
    const r = await api('/api/profiles');
    const tb = $('#pf-table tbody');
    tb.innerHTML = '';
    if (!r.profiles.length) {
      tb.innerHTML = '<tr><td colspan="5" class="ac-empty">尚無設定檔。可儲存目前的打包條件。</td></tr>';
      return;
    }
    r.profiles.forEach(pf => {
      const tr = document.createElement('tr');
      const tdN = document.createElement('td'); tdN.textContent = pf.name;
      const tdU = document.createElement('td'); tdU.textContent = pf.updated;
      const tdS = document.createElement('td'); tdS.textContent = (pf.data && pf.data.sourceRoot) || '';
      const tdC = document.createElement('td');
      tdC.textContent = pf.data && pf.data.items ? pf.data.items.length + ' 項' : '';
      const tdA = document.createElement('td');
      const actions = document.createElement('div'); actions.className = 'ac-cell-actions';
      const ld = document.createElement('button'); ld.className = 'tb-btn tb-btn--sm'; ld.textContent = '載入';
      ld.addEventListener('click', async () => {
        try {
          const rr = await post('/api/profiles/load', { name: pf.name });
          applyProfile(rr.data);
          toast('已載入設定檔: ' + pf.name);
        } catch (e) { toast(e.message, true); }
      });
      const dl = document.createElement('button'); dl.className = 'tb-btn tb-btn--danger tb-btn--sm'; dl.textContent = '刪除';
      dl.addEventListener('click', async () => {
        if (!await openActionDialog('刪除設定檔', { message: pf.name, accept: '刪除', danger: true })) return;
        try { await post('/api/profiles/delete', { name: pf.name }); loadProfiles(); }
        catch (e) { toast(e.message, true); }
      });
      actions.append(ld, dl);
      tdA.appendChild(actions);
      tr.append(tdN, tdU, tdS, tdC, tdA);
      tb.appendChild(tr);
    });
  } catch (e) { toast(e.message, true); }
}
$('#pf-refresh').addEventListener('click', loadProfiles);
$('#pf-save').addEventListener('click', saveProfileAs);

function applyProfile(d) {
  if (!d) return;
  if (d.sourceRoot) { $('#pack-src').value = d.sourceRoot; $('#cpy-src').value = d.sourceRoot; state.sourceRoot = d.sourceRoot; }
  if (d.label) state.label = d.label;
  state.items = (d.items || []).map(x => ({ path: x.path, enabled: x.enabled !== false, exclude: x.exclude || [] }));
  state.includeAuth = !!d.includeAuth;
  $('#pack-auth').checked = state.includeAuth;
  if (d.zipDir) $('#pack-zipdir').value = d.zipDir;
  if (d.targetRoot) { $('#unp-tgt').value = d.targetRoot; $('#cpy-tgt').value = d.targetRoot; state.targetRoot = d.targetRoot; }
  renderScope();
}

// ---------------- 解壓頁 ----------------
$('#unp-load').addEventListener('click', async () => {
  const z = $('#unp-zip').value.trim();
  if (!z) { toast('請輸入 zip 路徑', true); return; }
  try {
    const r = await api('/api/zip?path=' + encodeURIComponent(z));
    state.zipInfo = r;
    let txt = '';
    if (r.manifest) {
      txt += '產生時間: ' + r.manifest.created + '\n來源: ' + r.manifest.sourceRoot +
             '\nlabel: ' + r.manifest.label + '   auth: ' + r.manifest.includeAuth + '\n';
    } else {
      txt += '（無 manifest.json — 非本工具產生的壓縮包，仍會列出檔案）\n';
    }
    txt += '檔案數: ' + r.count + '   解壓後大小: ' + fmtBytes(r.bytes);
    if (r.truncated) txt += '\n（清單僅顯示前 300 筆）';
    show($('#unp-info'), txt);
    const selfRadio = $$('input[name="unp-mode"]').find(x => x.value === 'self');
    if (r.manifest && r.manifest.sourceRoot) {
      $('#unp-tgt').value = r.manifest.sourceRoot;
      if (selfRadio) selfRadio.checked = true;
    }
  } catch (e) { toast(e.message, true); }
});

function unpackBody(dryRun) {
  const mode = $$('input[name="unp-mode"]').find(x => x.checked).value;
  let tgt = $('#unp-tgt').value.trim();
  if (mode === 'self' && state.zipInfo && state.zipInfo.manifest) tgt = state.zipInfo.manifest.sourceRoot;
  return { zip: $('#unp-zip').value.trim(), targetRoot: tgt, dryRun, noBackup: $('#unp-nobackup').checked };
}

$('#unp-dry').addEventListener('click', async () => {
  try {
    const r = await post('/api/unpack', unpackBody(true));
    let txt = '預覽: ' + r.count + ' 檔（新增 ' + r.new + ' / 覆蓋 ' + r.overwrite + '）\n目標: ' + r.targetRoot;
    if (r.overwriteList && r.overwriteList.length) {
      txt += '\n\n將覆蓋（前 ' + r.overwriteList.length + ' 筆）:\n' + r.overwriteList.join('\n');
    }
    show($('#unp-out'), txt);
  } catch (e) { toast(e.message, true); }
});

$('#unp-run').addEventListener('click', async () => {
  if (!await openActionDialog('執行解壓', {
    message: $('#unp-nobackup').checked ? '既有檔案會直接覆蓋。' : '既有檔案會先備份到目標目錄的 _backup 資料夾。',
    accept: '解壓'
  })) return;
  try {
    const r = await post('/api/unpack', unpackBody(false));
    show($('#unp-out'), '完成!\n寫入 ' + r.count + ' 檔 → ' + r.targetRoot +
         '\n新增 ' + r.new + ' / 覆蓋 ' + r.overwrite +
         (r.backupRoot ? '\n舊檔備份於: ' + r.backupRoot : ''));
    toast('解壓完成');
  } catch (e) { toast(e.message, true); }
});

// ---------------- 部署複製頁 ----------------
function copyBody(dryRun) {
  return {
    sourceRoot: $('#cpy-src').value.trim() || $('#pack-src').value.trim(),
    targetRoot: $('#cpy-tgt').value.trim(),
    items: state.items,
    dryRun,
    noBackup: $('#cpy-nobackup').checked
  };
}
$('#cpy-dry').addEventListener('click', async () => {
  try {
    const r = await post('/api/copy', copyBody(true));
    let txt = '預覽: ' + r.count + ' 檔（新增 ' + r.new + ' / 覆蓋 ' + r.overwrite + '）\n目標: ' + r.targetRoot + '\n\n';
    (r.items || []).forEach(s => {
      txt += '  ' + s.path.padEnd(30) + String(s.count).padStart(6) + ' 檔' + (s.error ? '  <- ' + s.error : '') + '\n';
    });
    if (r.overwriteList && r.overwriteList.length) txt += '\n將覆蓋（前 ' + r.overwriteList.length + ' 筆）:\n' + r.overwriteList.join('\n');
    show($('#cpy-out'), txt);
  } catch (e) { toast(e.message, true); }
});
$('#cpy-run').addEventListener('click', async () => {
  if (!await openActionDialog('執行部署複製', { accept: '複製' })) return;
  try {
    const r = await post('/api/copy', copyBody(false));
    show($('#cpy-out'), '完成!\n寫入 ' + r.count + ' 檔 → ' + r.targetRoot +
         (r.backupRoot ? '\n舊檔備份於: ' + r.backupRoot : ''));
    toast('部署複製完成');
  } catch (e) { toast(e.message, true); }
});

// ---------------- 歷史頁 ----------------
async function loadHistory() {
  try {
    const r = await api('/api/history');
    const tb = $('#his-table tbody');
    tb.innerHTML = '';
    if (!r.entries.length) { tb.innerHTML = '<tr><td colspan="7" class="ac-empty">尚無紀錄</td></tr>'; return; }
    r.entries.forEach(e => {
      const tr = document.createElement('tr');
      const cells = [e.time, e.action, e.detail || '', e.count, fmtBytes(e.bytes), (e.source || '') + ' → ' + (e.target || '')];
      cells.forEach(v => { const td = document.createElement('td'); td.textContent = v; tr.appendChild(td); });
      const tdA = document.createElement('td');
      const actions = document.createElement('div'); actions.className = 'ac-cell-actions';
      if (e.cli) {
        const cp = document.createElement('button'); cp.className = 'tb-btn tb-btn--sm'; cp.textContent = '複製指令';
        cp.addEventListener('click', async () => {
          try {
            await navigator.clipboard.writeText(e.cli);
            toast('已複製 CLI 指令');
          } catch {
            await openActionDialog('複製 CLI 指令', { label: '指令', value: e.cli, readOnly: true });
          }
        });
        actions.appendChild(cp);
      }
      const del = document.createElement('button'); del.className = 'tb-btn tb-btn--danger tb-btn--sm'; del.textContent = '刪除';
      del.addEventListener('click', async () => {
        try { await post('/api/history/delete', { id: e.id }); loadHistory(); } catch (er) { toast(er.message, true); }
      });
      actions.appendChild(del);
      tdA.appendChild(actions);
      tr.appendChild(tdA);
      if (e.status && e.status !== 'ok') tr.classList.add('off');
      tb.appendChild(tr);
    });
  } catch (e) { toast(e.message, true); }
}
$('#his-refresh').addEventListener('click', loadHistory);
$('#his-clear').addEventListener('click', async () => {
  if (!await openActionDialog('清空全部工作歷史', { accept: '清空', danger: true })) return;
  try { await post('/api/history/clear', {}); loadHistory(); } catch (e) { toast(e.message, true); }
});

// ---------------- 資料夾挑選（ui-kit tb-dirpicker 共用元件） ----------------
function dpFetchDir(path, opts) {
  return post('/api/browse', {
    path: path || '',
    scan: !!opts.scan, depth: opts.depth || 2, limit: opts.limit || 50,
    files: !!opts.files, extensions: opts.extensions || []
  }).catch(e => ({ error: e.message }));
}

function openBrowse(opts) {
  let start = opts.start || '';
  if ((opts.mode || 'dir') === 'file' && /\.[^\\/]+$/.test(start.toLowerCase())) {
    const i = Math.max(start.lastIndexOf('\\'), start.lastIndexOf('/'));
    start = i > 0 ? start.substring(0, i) : '';
  }
  TbDirPicker.open({
    title: (opts.mode || 'dir') === 'file' ? '選擇檔案' : '選擇資料夾',
    start: start,
    mode: opts.mode || 'dir',
    extensions: opts.extensions || [],
    fetchDir: dpFetchDir
  }).then(p => { if (p && opts.onPick) opts.onPick(p); });
}

// 解壓來源（zip 檔）沿用舊過濾條件的副檔名
const ZIP_EXTS = ['.zip', '.json', '.jsonl', '.txt', '.md'];

function bindBrowse(btnId, inputId, mode) {
  $(btnId).addEventListener('click', () => openBrowse({ mode, start: $(inputId).value.trim(), extensions: mode === 'file' ? ZIP_EXTS : [], onPick: p => { $(inputId).value = p; } }));
}
bindBrowse('#pack-src-browse', '#pack-src', 'dir');
bindBrowse('#pack-zipdir-browse', '#pack-zipdir', 'dir');
bindBrowse('#unp-zip-browse', '#unp-zip', 'file');
bindBrowse('#unp-tgt-browse', '#unp-tgt', 'dir');
bindBrowse('#cpy-src-browse', '#cpy-src', 'dir');
bindBrowse('#cpy-tgt-browse', '#cpy-tgt', 'dir');

$('#pack-src').addEventListener('change', () => { $('#cpy-src').value = $('#pack-src').value; saveLast(); });
$('#pack-auth').addEventListener('change', saveLast);
$('#pack-zipdir').addEventListener('change', saveLast);

// ---------------- 初始化 ----------------
(async function init() {
  try {
    const st = await api('/api/state');
    $('#pack-zipdir').value = st.defaults.zipDir;
    if (st.last) {
      applyProfile(st.last);
    } else {
      const d = await api('/api/defaults/items');
      state.items = d.project.map(x => ({ path: x.path, enabled: x.enabled !== false, exclude: x.exclude || [] }));
      $('#pack-src').value = st.defaults.suggestedSource;
      $('#cpy-src').value = st.defaults.suggestedSource;
      renderScope();
    }
    if (!$('#pack-src').value) {
      $('#pack-src').value = st.defaults.suggestedSource;
      $('#cpy-src').value = st.defaults.suggestedSource;
    }
    renderScope();
  } catch (e) { toast('初始化失敗: ' + e.message, true); }
})();

// ---------------- 圖標與主題（ui-kit 3.0） ----------------
// 圖標：<i data-tb-icon> 由 tb-icons.js 換成 Lucide SVG；主題由 tb-theme.js 套用（Hub 嵌入時跟著 Hub）
(function initLook() {
  if (window.TbIcons) TbIcons.render(document);
  const btn = $('#theme-toggle');
  if (!btn || !window.TbTheme) return;
  const ORDER = ['light', 'dark', 'system'];
  const LABEL = { light: '淺色', dark: '深色', system: '跟隨系統' };
  const ICON = { light: 'sun', dark: 'moon', system: 'monitor' };
  function paint() {
    const m = TbTheme.get().mode;
    btn.innerHTML = window.TbIcons ? TbIcons.svg(ICON[m], { anim: 'wiggle' }) : LABEL[m];
    btn.title = '主題：' + LABEL[m] + '（點一下切換）';
    btn.setAttribute('aria-label', btn.title);
  }
  paint();
  document.addEventListener('tb-theme-change', paint);
  btn.addEventListener('click', () => TbTheme.set(ORDER[(ORDER.indexOf(TbTheme.get().mode) + 1) % ORDER.length]));
})();

async function pollServerState() {
  const badge = $('#server-state');
  let label = '伺服器未回應';
  let tone = 'danger';
  try {
    const health = await api('/api/health');
    if (health?.ok) {
      $('#server-port').textContent = '本機服務 port ' + health.port;
      label = '連線正常';
      tone = 'ok';
    }
  } catch (_) { /* 下次輪詢重新連線 */ }
  if (badge.textContent !== label) badge.textContent = label;
  badge.className = 'tb-badge tb-badge--' + tone;
  setTimeout(pollServerState, 3000);
}
if (!document.documentElement.dataset.embedded) pollServerState();
