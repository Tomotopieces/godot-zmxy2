// Builds docs/items.md: every item of the original (tools/data/equipment.json) with what it does in this
// remake and where the player can get it. Sources are computed from the data the game is baked from:
// monster drop lists (per stage), the shop, fusion recipes, boss stone drops and a few hand-written special cases.
//   node tools/rig/item_report.js
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const eq = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/data/equipment.json')));
const auto = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/data/monsters_auto.json'))).monsters;
const ovr = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/data/monsters.json'))).overrides;
const levelsDir = path.join(ROOT, 'game/assets/levels');

const DROP_MUL = 1.5;   // FallEquipObj: probability x 1.5 (BaseMonster.fallEquip)
// sl11 = 1-1, sl101 = 10-1, sl111 = 11-1
const SCENE_NAME = (s) => { const d = s.slice(2); return d.length === 3 ? `${d.slice(0, 2)}-${d[2]}` : `${d[0]}-${d[1]}`; };
const STAGE_NAMES = { '1-1': '1-1', '1-2': '1-2', '1-3': '1-3', '2-1': '2-1', '2-2': '2-2 判官府', '2-3': '2-3 阎罗殿', '3-1': '3-1 忘川河', '3-2': '3-2 奈何桥', '3-3': '3-3 孟婆', '4-1': '4-1', '5-1': '5-1 白骨精(隐藏)', '6-1': '6-1 红孩儿(隐藏)', '7-1': '7-1 刑天(隐藏)', '8-1': '8-1 楚江王(隐藏)', '9-1': '9-1 宋帝王(活动)', '10-2': '10-2 五官王', '10-3': '10-3 卞城王', '10-4': '10-4 泰山王', '10-5': '10-5 都市王', '10-6': '10-6 平等王', '11-1': '11-1(活动)' };
// stages that have no entrance in the game flow (the original opens them only from events)
// (9-1 / 11-1 are entered from the 活动 panel on the stage map; nothing is left without an entrance)
const NO_ENTRY = new Set();
// 中秋: the cake drops from every boss; the exchange menu of the bag turns 10 into a big one and 100 into the hero's weapon
const moon = eq.rules.moon;
const MOON_SOURCE = Object.assign({ [moon.cake]: '中秋：每个 BOSS 单位死亡必掉 1 个' },
  Object.fromEntries(moon.big.map((id) => [id, `中秋：${moon.big_cost} 个小月饼兑换（随机一种）`])),
  Object.fromEntries(Object.values(moon.weapons).map((id) => [id, `中秋：${moon.weapon_cost} 个小月饼兑换（本角色）`])));

// monster ids -> names (docs/analysis/05_monsters.md)
const NAMES = {};
for (const l of fs.readFileSync(path.join(ROOT, 'docs/analysis/05_monsters.md'), 'utf8').split('\n')) {
  const m = /^\| (\d+) \| ([^|]+) \|/.exec(l);
  if (m) NAMES[m[1]] = /[一-龥]/.test(m[2]) && !/^–/.test(m[2].trim()) ? m[2].trim() : '小怪';
}
NAMES['45'] = '白骨精';
for (const k in NAMES) NAMES[k] = NAMES[k].split(/ ?[(（]/)[0];   // "泰山王 (reflect)" -> "泰山王"

// monsters that only appear through another monster / a stage script: id -> scenes
const SUMMONED = {
  35: ['sl13'], 33: ['sl23'], 34: ['sl23'], 36: ['sl23'], 37: ['sl23'], 53: ['sl23'], 54: ['sl23'], 55: ['sl23'],
  41: ['sl31'], 48: ['sl33'], 49: ['sl33'], 51: ['sl41'], 60: ['sl41'], 62: ['sl81'], 65: ['sl91'], 66: ['sl91'],
  68: ['sl102'], 74: ['sl104'], 75: ['sl104'], 76: ['sl104'], 78: ['sl106'], 81: ['sl71'],
};

// monster id -> scenes
const scenes = {};
const add = (id, sc) => { (scenes[id] = scenes[id] || new Set()).add(sc); };
for (const lv of fs.readdirSync(levelsDir)) {
  const d = JSON.parse(fs.readFileSync(path.join(levelsDir, lv, 'level.json')));
  for (const s of d.spawners) add(s.enemy, lv);
}
for (const [id, list] of Object.entries(SUMMONED)) list.forEach((s) => add(id, s));

// drops of (monster, scene): [{item, p}]
function drops(id, scene) {
  const m = auto[id];
  if (!m) return [];
  let d = (m.per_scene && m.per_scene[scene]) || m.base;
  let list = d.equip_drops || [], p = d.equip_chance;
  const o = ovr[id] || {};
  if (id === '33' || id === '34') { if (scene !== 'sl12') list = []; }                // plain 无常 drop nothing
  if (o.equip_drops) list = o.equip_drops;
  if (id === '46') list = o.brain.hard.drops;                                          // only above the hard-mode level, see brain_46.gd
  // the drop roll succeeds with `equip_chance` (x1.5); then one entry is picked, all equally likely (the original's
  // round(rand * (n - 1)) favoured the middle entries; the remake does not)
  const pick = (i, n) => 1 / n;
  if (id === '45') {                                                                // per-form drops, see brain_45.gd
    return o.brain.forms.flatMap((f, i) => f.drops.map((it, j) => ({ item: it, p: Math.min(1, f.equip_chance) * pick(j, f.drops.length), note: `第${i + 1}形态` })));
  }
  return list.map((it, j) => ({ item: it, p: Math.min(1, (p === undefined ? 0.15 : p) * DROP_MUL) * pick(j, list.length) }));
}

// item -> sources
const src = {};
const addSrc = (item, text) => { (src[item] = src[item] || []).push(text); };
for (const [id, set] of Object.entries(scenes)) {
  for (const sc of set) {
    for (const dr of drops(id, sc)) {
      const st = SCENE_NAME(sc);
      addSrc(dr.item, { kind: 'drop', id, stage: st, p: dr.p, note: dr.note || '' });
    }
  }
}
// shop
const shopItems = [...eq.rules.shop.pages.item, ...eq.rules.shop.pages.look];
for (const it of shopItems) addSrc(it, { kind: 'shop', price: eq.rules.shop.prices[it] });
// fusion
const mats = new Set();
for (const r of eq.rules.fusion.recipes) { addSrc(r.out, { kind: 'fusion', mats: r.mats, cost: r.kind === 'stone' ? 0 : eq.rules.fusion.cost }); r.mats.forEach((m) => mats.add(m)); }
// boss stones, pearls, keys
addSrc('wpqhs1', { kind: 'text', text: '关底 BOSS 掉落（主角等级不超过该关上限时，约 5%~100%）' });
addSrc('bsz', { kind: 'text', text: '3-3 场景里的珊瑚珠被打碎，20% 掉落' });

const MONSTER_LABEL = (id) => `${NAMES[id] || '小怪'}#${id}`;
const pct = (p) => (p * 100).toFixed(1).replace(/[.]0$/, '') + '%';
// one text per source; drops of the same monster with the same chance over several stages are merged
function describeAll(list) {
  const out = [], groups = new Map();
  for (const s of list) {
    if (s.kind !== 'drop') { out.push(describe(s)); continue; }
    const key = `${s.id}|${s.p}|${s.note}`;
    if (!groups.has(key)) groups.set(key, { s, stages: [] });
    groups.get(key).stages.push(s.stage);
  }
  const drops = [...groups.values()].map(({ s, stages }) => `${MONSTER_LABEL(s.id)} ${[...new Set(stages)].map((x) => STAGE_NAMES[x] || x).join('、')}${s.note ? ' ' + s.note : ''} ${pct(s.p)}`);
  return [...drops, ...out];
}
function describe(s) {
  if (s.kind === 'shop') return `商城 ${s.price} 功勋`;
  if (s.kind === 'fusion') return `炼丹炉合成：${s.mats.map((m) => (eq.items[m] || { name: m }).name).join(' + ')}${s.cost ? '（' + s.cost + ' 灵魂）' : '（3 合 1，75%）'}`;
  return s.text;
}

const STAT_NAMES = { hp: '生命', mp: '魔法', atk: '攻击', def: '防御', crit: '暴击', miss: '闪避', hp_regen: '回血', mp_regen: '回魔', lifesteal: '吸血', mdef: '魔抗', deephit: '重击' };
const PCT = new Set(['crit', 'miss', 'lifesteal', 'mdef', 'deephit']);
function statText(it) {
  return Object.entries(it.stats).map(([k, v]) => {
    const f = (x) => (PCT.has(k) ? Math.round(x * 1000) / 10 + '%' : Math.round(x));
    return `${STAT_NAMES[k]}${Array.isArray(v) ? f(v[0]) + '~' + f(v[1]) : f(v)}`;
  }).join(' ');
}

const TYPE_NAMES = { weapon: '武器', cloth: '防具', accessory: '饰品', treasure: '法宝', fashion: '时装', wing: '翅膀', item: '道具' };
const OTHER_CHAR = (it) => it.user && !['悟空', '唐僧', '八戒'].includes(it.user);
const USABLE = Object.keys(eq.rules.use);

// implementation status
function status(id, it) {
  if (it.stone) return it.stone === 5 ? '△ 可放入炼丹炉，但 5 级石成功率为 0（原版 bug，保留）' : '✓ 强化石';
  if (it.charm) return '✓ ' + (it.charm === 'luck' ? '幸运符：强化成功率 ×1.25' : '保底符：强化失败不降级');
  if (it.type === 'item') {
    if (USABLE.includes(id)) return '✓ 可使用（' + (id === 'wdd' ? '强化已装备的五毒兽' : '限时 buff') + '）';
    if (id === moon.cake) return '✓ 背包点击：兑换大月饼 / 绝版武器';
    if (id === 'yll') return '✓ 持有后可开启刑天门';
    if (id === 'bsz') return '✓ 持有后触碰忘川河极光进入楚江王';
    if (mats.has(id)) return '✓ 合成材料';
    return '△ 仅可出售';
  }
  if (OTHER_CHAR(it)) return `✗ ${it.user}专属，本作没有该角色`;
  if (it.type === 'treasure') return '✓ H 键释放，可升级';
  if (it.type === 'wing') return '✓ 属性 + 外观，可强化';
  if (it.type === 'fashion') return /^j/.test(id) ? '✗ 活动限定，未做' : '✓ 外观' + (eq.rules.drop_bonus[id] ? ` + 掉率 +${eq.rules.drop_bonus[id] * 100}%` : '');
  if (id === 'csgs') return '✓ 死亡时复活一次（消耗）';
  return '✓ 属性 + 外观';
}

function obtain(id, it) {
  if (MOON_SOURCE[id]) return { text: MOON_SOURCE[id], reachable: true };
  const list = (src[id] || []);
  if (!list.length) return null;
  // drops from stages without an entrance are not reachable
  const real = list.filter((s) => s.kind !== 'drop' || !NO_ENTRY.has(s.stage));
  const shown = describeAll(real.length ? real : list);
  // collapse identical monster/p over several stages
  return { text: shown.join('；'), reachable: real.length > 0 };
}

const order = ['weapon', 'cloth', 'accessory', 'treasure', 'wing', 'fashion', 'item'];
const lines = [];
lines.push('# 物品清单与实装情况', '', '由 `node tools/rig/item_report.js` 生成（数据来自 `tools/data/equipment.json`、`monsters_auto.json`、`monsters.json`、关卡文件），不要手改。', '');
lines.push('- ✓ 已实装　△ 部分/特殊　✗ 未做（原因见备注）　⚠ 已实装但目前没有任何获取渠道');
lines.push('- 怪物掉率是已经乘过原版的 ×1.5 之后的值，之后还会乘双倍爆率 buff 和时装加成；"#数字"是怪物 ID。掉率是“该怪的某一件”的概率：先按怪的总掉率判定，掉落时再在掉落表里等概率选一件。药品、经验球、强化石各自单独判定，不和装备抢概率。');
lines.push('- 红孩儿 #46 的金刚甲只在主角等级大于 15 时掉落。');
lines.push('- 活动关卡 9-1（七夕）/ 11-1（国庆）从地图的「活动」面板进入，每天各一次；中秋月饼靠 BOSS 掉落 + 背包兑换。', '');

const problems = [];
let total = 0, ok = 0;
for (const type of order) {
  const items = Object.entries(eq.items).filter(([, it]) => it.type === type);
  lines.push(`## ${TYPE_NAMES[type]}（${items.length}）`, '', '| ID | 名称 | 品质 | 角色 | 属性 | 实装 | 获取途径 |', '|---|---|---|---|---|---|---|');
  for (const [id, it] of items) {
    const st = status(id, it), ob = obtain(id, it);
    let how = ob ? ob.text : '无';
    total++;
    const implemented = st.startsWith('✓') || st.startsWith('△');
    if (!ob || !ob.reachable) {
      if (implemented) { problems.push({ id, it, st, how: ob ? ob.text : '' }); how = '⚠ ' + (ob ? ob.text + '（关卡无入口）' : '无'); }
    } else if (implemented) ok++;
    lines.push(`| ${id} | ${it.name} | ${it.quality} | ${it.user || '通用'} | ${statText(it) || (it.desc ? '' : '')} | ${st} | ${how} |`);
  }
  lines.push('');
}

lines.push('## 总结', '');
lines.push(`- 共 ${Object.keys(eq.items).length} 件物品；其中已实装且能在游戏里正常获得的 ${ok} 件。`);
if (problems.length) {
  lines.push('- 已实装但目前拿不到的：', ...problems.map((p) => `  - ${p.it.name}（${p.id}）：${p.st.replace(/^[✓△] /, '')}${p.how ? '；原有渠道 ' + p.how : ''}`));
}
const notDone = Object.entries(eq.items).filter(([id, it]) => status(id, it).startsWith('✗'));
lines.push(`- 未做：${notDone.length} 件（其他角色专属 ${notDone.filter(([, it]) => OTHER_CHAR(it)).length}、活动限定 ${notDone.filter(([, it]) => !OTHER_CHAR(it)).length}）。`);
lines.push('');
fs.writeFileSync(path.join(ROOT, 'docs/items.md'), lines.join('\n'));
console.log('docs/items.md written;', total, 'items,', problems.length, 'implemented without a source');
for (const p of problems) console.log('  no source:', p.id, p.it.name, '-', p.how || '(none)');

// ------------------------------------------------------------------ docs/drops.md: what each monster drops
{
  const ITEM_NAME = (id) => (eq.items[id] ? eq.items[id].name : id);
  const stageOrder = (s) => { const [a, b] = SCENE_NAME(s).split('-').map(Number); return a * 100 + b; };
  const stoneRate = (id, scene) => {
    const d = (auto[id] && ((auto[id].per_scene && auto[id].per_scene[scene]) || auto[id].base)) || {};
    const o = (ovr[id] || {});
    const boss = !!(d.boss || (o.boss));
    const rate = o.stone_rate !== undefined ? o.stone_rate : d.stone_rate;
    return { boss, rate };
  };
  const rows = [];
  for (const [id, set] of Object.entries(scenes)) {
    const bySig = new Map();   // identical drops over several stages are one row
    for (const sc of [...set].sort((a, b) => stageOrder(a) - stageOrder(b))) {
      const list = drops(id, sc);
      const d = (auto[id] && ((auto[id].per_scene && auto[id].per_scene[sc]) || auto[id].base)) || {};
      const st = stoneRate(id, sc);
      const cap = eq.rules.stone_drop.level_caps[sc];
      const stone = st.boss && cap !== undefined && cap !== 0 && st.rate ? `${pct(st.rate)}（主角 ${cap < 0 ? '任意等级' : '≤' + cap + ' 级'}）` : '';
      const sig = JSON.stringify([list.map((x) => [x.item, x.p, x.note]), stone]);
      if (!bySig.has(sig)) bySig.set(sig, { id, scenes: [], list, stone, boss: d.boss });
      bySig.get(sig).scenes.push(STAGE_NAMES[SCENE_NAME(sc)] || SCENE_NAME(sc));
    }
    for (const r of bySig.values()) rows.push(r);
  }
  rows.sort((a, b) => stageOrder([...scenes[a.id]].sort((x, y) => stageOrder(x) - stageOrder(y))[0]) - stageOrder([...scenes[b.id]].sort((x, y) => stageOrder(x) - stageOrder(y))[0]) || +a.id - +b.id);
  const out = [];
  out.push('# 怪物掉落表', '',
    `由 \`node tools/rig/item_report.js\` 与 docs/items.md 一起生成，不要手改。`, '',
    '- 装备：先按怪的“装备掉率”（原版数值 ×1.5）判定掉不掉，掉的话在该怪的装备表里**等概率**选一件，所以每件的概率 = 总掉率 ÷ 件数。表里列的是每件的概率；之后还会乘双倍爆率 buff 和时装加成。',
    '- 强化石（1 级）：只有关底 BOSS 才有，单独判定，不占装备的概率；只有主角等级不超过该关上限才会掉。',
    '- 药品和经验球所有怪都一样，各自独立判定：血瓶共约 5%（小红约 3.75%、大红约 1.25%），蓝瓶约 5%；红球每怪 2~4 个，绿 / 蓝 / 白球各有 4% 概率出 3 个、4% 出 2 个、4% 出 1 个。',
    '- 红孩儿的金刚甲只在主角等级大于 15 时掉落。', '',
    '| 怪物 | 出现关卡 | 装备（每件概率） | 关底强化石 |', '|---|---|---|---|');
  for (const r of rows) {
    const items = r.list.length ? r.list.map((x) => `${ITEM_NAME(x.item)}(${x.item}) ${pct(x.p)}${x.note ? '·' + x.note : ''}`).join('<br>') : '—';
    const total = r.list.length && r.id !== '45' ? `<br>（总掉率 ${pct(Math.min(1, r.list.reduce((s, x) => s + x.p, 0)))}）` : '';
    out.push(`| ${MONSTER_LABEL(r.id)}${r.boss ? ' ★' : ''} | ${[...new Set(r.scenes)].join('、')} | ${items}${r.list.length && r.id !== '45' ? total : ''} | ${r.stone || '—'} |`);
  }
  out.push('', '★ = BOSS。');
  fs.writeFileSync(path.join(ROOT, 'docs/drops.md'), out.join('\n') + '\n');
  console.log('docs/drops.md written;', rows.length, 'rows');
}
