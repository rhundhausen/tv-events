// Event grid: loads the slim events file, then filters, searches, sorts, and pages in the browser.
// All event text comes from outside sources, so it is only ever set with textContent.

const cfg = JSON.parse(document.getElementById('tv-config').textContent);
const PAGE_SIZE = 25;
const TZ = 'America/Boise';

const ymdFmt = new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' });
const timeFmt = new Intl.DateTimeFormat('en-US', { timeZone: TZ, hour: 'numeric', minute: '2-digit' });
const dayFmt = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', weekday: 'short', month: 'short', day: 'numeric' });
const shortFmt = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', month: 'short', day: 'numeric' });
const numFmt = new Intl.NumberFormat('en-US');

const $ = (id) => document.getElementById(id);
const el = {
  q: $('q'), when: $('when'), from: $('from'), to: $('to'), city: $('city'), size: $('size'),
  reset: $('reset'), cats: $('cats'), count: $('count'), rows: $('rows'),
  pagerTop: $('pager-top'), pagerBottom: $('pager-bottom'),
};

// Dates are handled as YYYY-MM-DD strings in Boise time; noon UTC keeps day math clear of DST edges.
const boiseDay = (date) => ymdFmt.format(date);
const asDate = (ymd) => new Date(`${ymd}T12:00:00Z`);
const addDays = (ymd, n) => { const d = asDate(ymd); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
// Lowercase, no accents, no apostrophes: "Women's" and "womens" both become "womens".
const fold = (s) => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/['‘’]/g, '').toLowerCase();
// Short forms people search with. A search word matches if the event has it or any of its long forms.
const ALIASES = { bsu: ['boise state'], nnu: ['northwest nazarene'], cofi: ['college of idaho'] };
const searchTerms = (q) => fold(q).split(/\s+/).filter(Boolean).map((w) => [w, ...(ALIASES[w] || [])]);
const today = () => boiseDay(new Date());

const state = { q: '', cats: new Set(), city: '', size: '', when: '', from: '', to: '', sort: 'date', dir: 1, page: 1 };
let events = [];

function prepare(e) {
  const allDay = Boolean(e.a) || e.s.length === 10;
  const sd = allDay ? e.s.slice(0, 10) : boiseDay(new Date(e.s));
  let ed = e.e ? (allDay ? e.e.slice(0, 10) : boiseDay(new Date(e.e))) : sd;
  if (ed < sd) ed = sd;
  const catLabel = cfg.categories[e.k] || e.k;
  return {
    title: e.t, venue: e.v, city: e.c, cat: e.k, catLabel, tags: e.g || [], size: e.z, url: e.u, desc: e.d,
    sd, ed, allDay,
    instant: allDay ? 0 : Date.parse(e.s),
    dateText: sd === ed ? dayFmt.format(asDate(sd)) : `${dayFmt.format(asDate(sd))} to ${shortFmt.format(asDate(ed))}`,
    timeText: allDay ? 'All day' : timeFmt.format(new Date(e.s)),
    hay: fold([e.t, e.v, e.c, catLabel, (e.g || []).join(' '), e.d].join(' ')),
  };
}

function presetRange(when) {
  const t = today();
  switch (when) {
    case 'today': return [t, t];
    case 'tomorrow': return [addDays(t, 1), addDays(t, 1)];
    case 'weekend': {
      const dow = asDate(t).getUTCDay();
      if (dow === 0) return [t, t];
      if (dow === 6) return [t, addDays(t, 1)];
      const fri = addDays(t, 5 - dow);
      return [fri, addDays(fri, 2)];
    }
    case 'week': return [t, addDays(t, 6)];
    case 'month': return [t, addDays(t, 29)];
    case 'custom': return [state.from, state.to];
    default: return ['', ''];
  }
}

function matches(e, words, from, to, skipCats) {
  if (e.ed < from) return false;
  if (to && e.sd > to) return false;
  if (state.city && e.city !== state.city) return false;
  if (state.size && e.size !== state.size) return false;
  if (!skipCats && state.cats.size && !state.cats.has(e.cat)) return false;
  for (const forms of words) if (!forms.some((f) => e.hay.includes(f))) return false;
  return true;
}

const sorters = {
  date: (a, b) => a.sd.localeCompare(b.sd) || a.instant - b.instant || a.title.localeCompare(b.title),
  title: (a, b) => a.title.localeCompare(b.title) || sorters.date(a, b),
  venue: (a, b) => a.venue.localeCompare(b.venue) || sorters.date(a, b),
  city: (a, b) => a.city.localeCompare(b.city) || sorters.date(a, b),
};

function render() {
  const words = searchTerms(state.q);
  const [rangeFrom, to] = presetRange(state.when);
  const from = rangeFrom && rangeFrom > today() ? rangeFrom : today();

  // Category counts reflect every other filter, so a chip shows what clicking it would give.
  const counts = {};
  const shown = [];
  for (const e of events) {
    if (!matches(e, words, from, to, true)) continue;
    counts[e.cat] = (counts[e.cat] || 0) + 1;
    if (!state.cats.size || state.cats.has(e.cat)) shown.push(e);
  }
  const sorter = sorters[state.sort] || sorters.date;
  shown.sort((a, b) => sorter(a, b) * state.dir);

  const pages = Math.max(1, Math.ceil(shown.length / PAGE_SIZE));
  state.page = Math.min(Math.max(1, state.page), pages);
  const start = (state.page - 1) * PAGE_SIZE;
  const slice = shown.slice(start, start + PAGE_SIZE);

  renderChips(counts);
  renderRows(slice);
  el.count.textContent = shown.length
    ? `Showing ${numFmt.format(start + 1)} to ${numFmt.format(start + slice.length)} of ${numFmt.format(shown.length)} events`
    : 'No events match these filters';
  renderPager(el.pagerTop, pages);
  renderPager(el.pagerBottom, pages);
  renderSortHeaders();
  writeUrl();
}

function renderChips(counts) {
  el.cats.replaceChildren();
  const ids = Object.keys(cfg.categories);
  for (const id of ids) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'chip';
    b.dataset.cat = id;
    b.setAttribute('aria-pressed', state.cats.has(id) ? 'true' : 'false');
    const n = counts[id] || 0;
    if (!n && !state.cats.has(id)) b.classList.add('empty');
    const label = document.createElement('span');
    label.textContent = cfg.categories[id];
    const count = document.createElement('span');
    count.className = 'n';
    count.textContent = numFmt.format(n);
    b.append(label, count);
    el.cats.append(b);
  }
}

function cell(text, className) {
  const td = document.createElement('td');
  if (className) td.className = className;
  if (text) td.textContent = text;
  return td;
}

function renderRows(list) {
  const frag = document.createDocumentFragment();
  for (const e of list) {
    const tr = document.createElement('tr');

    const date = cell(e.dateText, 'c-date');
    date.dataset.label = 'Date';
    const time = cell(e.timeText, 'c-time');
    time.dataset.label = 'Time';

    const title = cell('', 'c-title');
    if (/^https?:\/\//i.test(e.url)) {
      const a = document.createElement('a');
      a.href = e.url;
      a.target = '_blank';
      a.rel = 'noopener';
      a.textContent = e.title;
      title.append(a);
    } else {
      title.textContent = e.title;
    }
    if (e.desc) title.title = e.desc;

    const venue = cell(e.venue, 'c-venue');
    venue.dataset.label = 'Venue';
    const city = cell(e.city, 'c-city');
    city.dataset.label = 'City';

    const cat = cell('', 'c-cat');
    const pill = document.createElement('span');
    pill.className = `pill cat-${e.cat}`;
    pill.textContent = e.catLabel;
    cat.append(pill);

    const size = cell('', 'c-size');
    if (e.size) {
      const badge = document.createElement('span');
      badge.className = 'size';
      badge.textContent = e.size;
      badge.title = cfg.sizes[e.size] || e.size;
      size.append(badge);
    }

    tr.append(date, time, title, venue, city, cat, size);
    frag.append(tr);
  }
  if (!list.length) {
    const tr = document.createElement('tr');
    const td = cell('', 'empty-row');
    td.colSpan = 7;
    const p = document.createElement('span');
    p.textContent = 'Nothing matches. ';
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'link';
    b.textContent = 'Clear the filters';
    b.addEventListener('click', resetAll);
    td.append(p, b);
    tr.append(td);
    frag.append(tr);
  }
  el.rows.replaceChildren(frag);
}

function renderPager(nav, pages) {
  nav.replaceChildren();
  if (pages <= 1) return;
  const add = (label, page, disabled, aria) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'btn small';
    b.textContent = label;
    b.disabled = disabled;
    if (aria) b.setAttribute('aria-label', aria);
    b.addEventListener('click', () => {
      state.page = page;
      render();
      if (nav === el.pagerBottom) document.querySelector('.status').scrollIntoView({ block: 'start' });
    });
    nav.append(b);
  };
  add('First', 1, state.page === 1);
  add('Prev', state.page - 1, state.page === 1, 'Previous page');
  const info = document.createElement('span');
  info.className = 'page-info';
  info.textContent = `Page ${state.page} of ${pages}`;
  nav.append(info);
  add('Next', state.page + 1, state.page === pages, 'Next page');
  add('Last', pages, state.page === pages);
}

function renderSortHeaders() {
  for (const th of document.querySelectorAll('th[data-sort]')) {
    const active = th.dataset.sort === state.sort;
    if (active) th.setAttribute('aria-sort', state.dir === 1 ? 'ascending' : 'descending');
    else th.removeAttribute('aria-sort');
  }
}

function fillSelects() {
  const byCity = {};
  for (const e of events) if (e.city) byCity[e.city] = (byCity[e.city] || 0) + 1;
  for (const [name, n] of Object.entries(byCity).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))) {
    const o = document.createElement('option');
    o.value = name;
    o.textContent = `${name} (${numFmt.format(n)})`;
    el.city.append(o);
  }
  // Largest first, so the list reads down in size.
  for (const [id, label] of Object.entries(cfg.sizes).sort((a, b) => cfg.sizeOrder.indexOf(b[0]) - cfg.sizeOrder.indexOf(a[0]))) {
    const o = document.createElement('option');
    o.value = id;
    o.textContent = label;
    el.size.append(o);
  }
}

function syncControls() {
  el.q.value = state.q;
  el.when.value = state.when;
  el.city.value = state.city;
  el.size.value = state.size;
  const [f, t] = presetRange(state.when);
  el.from.value = f;
  el.to.value = t;
}

function readUrl() {
  const p = new URLSearchParams(location.search);
  state.q = p.get('q') || '';
  state.cats = new Set((p.get('cat') || '').split(',').filter((c) => c in cfg.categories));
  state.city = p.get('city') || '';
  state.size = p.get('size') || '';
  state.when = p.get('when') || '';
  state.from = p.get('from') || '';
  state.to = p.get('to') || '';
  if (state.from || state.to) state.when = 'custom';
  const [sort, dir] = (p.get('sort') || 'date').split(':');
  state.sort = sort in sorters ? sort : 'date';
  state.dir = dir === 'desc' ? -1 : 1;
  state.page = Number.parseInt(p.get('page') || '1', 10) || 1;
}

function writeUrl() {
  const p = new URLSearchParams();
  if (state.q) p.set('q', state.q);
  if (state.cats.size) p.set('cat', [...state.cats].join(','));
  if (state.city) p.set('city', state.city);
  if (state.size) p.set('size', state.size);
  if (state.when === 'custom') {
    if (state.from) p.set('from', state.from);
    if (state.to) p.set('to', state.to);
  } else if (state.when) {
    p.set('when', state.when);
  }
  if (state.sort !== 'date' || state.dir !== 1) p.set('sort', `${state.sort}${state.dir === -1 ? ':desc' : ''}`);
  if (state.page > 1) p.set('page', String(state.page));
  const qs = p.toString();
  history.replaceState(null, '', qs ? `?${qs}` : location.pathname);
}

function resetAll() {
  Object.assign(state, { q: '', cats: new Set(), city: '', size: '', when: '', from: '', to: '', sort: 'date', dir: 1, page: 1 });
  syncControls();
  render();
}

function onFilter(fn) {
  return (ev) => { fn(ev); state.page = 1; render(); };
}

let searchTimer;
el.q.addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(onFilter(() => { state.q = el.q.value.trim(); }), 150);
});
el.when.addEventListener('change', onFilter(() => {
  state.when = el.when.value;
  if (state.when !== 'custom') { state.from = ''; state.to = ''; }
  const [f, t] = presetRange(state.when);
  el.from.value = f;
  el.to.value = t;
}));
for (const input of [el.from, el.to]) {
  input.addEventListener('change', onFilter(() => {
    state.when = 'custom';
    el.when.value = 'custom';
    state.from = el.from.value;
    state.to = el.to.value;
  }));
}
el.city.addEventListener('change', onFilter(() => { state.city = el.city.value; }));
el.size.addEventListener('change', onFilter(() => { state.size = el.size.value; }));
el.reset.addEventListener('click', resetAll);
el.cats.addEventListener('click', onFilter((ev) => {
  const chip = ev.target.closest('.chip');
  if (!chip) return;
  const id = chip.dataset.cat;
  if (state.cats.has(id)) state.cats.delete(id);
  else state.cats.add(id);
}));
for (const th of document.querySelectorAll('th[data-sort] button')) {
  th.addEventListener('click', () => {
    const key = th.parentElement.dataset.sort;
    if (state.sort === key) state.dir = -state.dir;
    else { state.sort = key; state.dir = 1; }
    state.page = 1;
    render();
  });
}
document.addEventListener('keydown', (ev) => {
  if (ev.key === '/' && document.activeElement?.tagName !== 'INPUT') {
    ev.preventDefault();
    el.q.focus();
  }
});

// The build writes the ingest time in UTC; show it in Boise time.
const asOf = document.getElementById('as-of');
if (asOf && cfg.lastIngest) {
  const when = new Date(cfg.lastIngest);
  if (!Number.isNaN(when.getTime())) {
    asOf.textContent = new Intl.DateTimeFormat('en-US', {
      timeZone: TZ, weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', timeZoneName: 'short',
    }).format(when);
  }
}

fetch(cfg.events)
  .then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json(); })
  .then((list) => {
    events = list.map(prepare);
    fillSelects();
    readUrl();
    syncControls();
    render();
  })
  .catch((err) => {
    el.count.textContent = `Could not load events (${err.message}).`;
  });
