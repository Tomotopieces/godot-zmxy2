// Extract the equipment catalogue from my/AllEquipment.as into tools/data/equipment.json.
// Random stat rolls ("20 + Math.round(Math.random() * 55)") become [min, max] ranges.
//   node tools/rig/extract_equipment.js
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const SRC = path.join(ROOT, 'decomp/res/zmxy2_game/scripts/my/AllEquipment.as');
const OUT = path.join(ROOT, 'tools/data/equipment.json');

// MyEquipObj(showid, name, id, type, user, quality, color, hp, mp, atk, def, crit, miss,
//            hp_regen, mp_regen, lifesteal, mdef, deephit, strengthen, desc, change, prob, pskill)
const STATS = ['hp', 'mp', 'atk', 'def', 'crit', 'miss', 'hp_regen', 'mp_regen', 'lifesteal', 'mdef', 'deephit'];
// sell price in souls by quality (MyEquipObj.transValue)
const VALUE = { '粗糙': 10, '普通': 20, '优秀': 40, '精良': 80, '史诗': 160, '传说': 320 };
const TYPES = { zbfj: 'cloth', zbwq: 'weapon', zbsp: 'accessory', zbwp: 'item', zbsz: 'fashion', zbcb: 'wing', zbfb: 'treasure' };

function splitArgs(s) {
  const out = []; let depth = 0, cur = '', str = null;
  for (const ch of s) {
    if (str) { cur += ch; if (ch === str) str = null; continue; }
    if (ch === '"' || ch === "'") { str = ch; cur += ch; continue; }
    if ('({['.includes(ch)) depth++;
    if (')}]'.includes(ch)) depth--;
    if (ch === ',' && depth === 0) { out.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

function evalWith(expr, rnd) {
  const M = Object.create(Math); M.random = () => rnd;
  return Function('Math', `"use strict"; return (${expr});`)(M);
}

function range(expr) {
  if (expr === undefined) return 0;
  const lo = evalWith(expr, 0), hi = evalWith(expr, 0.999999);
  return lo === hi ? lo : [lo, hi];
}

const src = fs.readFileSync(SRC, 'utf8');
const items = {};
const re = /new MyEquipObj\(/g;
let m;
while ((m = re.exec(src))) {
  let i = m.index + m[0].length, depth = 1, str = null;
  for (; i < src.length && depth; i++) {
    const ch = src[i];
    if (str) { if (ch === str) str = null; continue; }
    if (ch === '"') str = ch;
    else if (ch === '(') depth++;
    else if (ch === ')') depth--;
  }
  const a = splitArgs(src.slice(m.index + m[0].length, i - 1));
  const id = evalWith(a[2], 0);
  if (!id || items[id]) continue;
  const e = {
    name: evalWith(a[1], 0), show: +a[0], type: TYPES[evalWith(a[3], 0)] || evalWith(a[3], 0),
    user: evalWith(a[4], 0), quality: evalWith(a[5], 0).replace(/\s/g, ''), color: '#' + String(evalWith(a[6], 0)).slice(2),
    stats: {}, strengthen: a[18] ? evalWith(a[18], 0) : {}, desc: a[19] ? evalWith(a[19], 0) : '',
  };
  e.value = VALUE[e.quality] || 0;
  // strengthening stones and charms are plain bag items with a role
  const st = /^wpqhs(\d)$/.exec(e.type);
  if (st) { e.stone = +st[1]; e.type = 'item'; }
  if (e.type === 'wpxyf') { e.charm = 'luck'; e.type = 'item'; }
  if (e.type === 'wpbdf') { e.charm = 'keep'; e.type = 'item'; }
  STATS.forEach((s, k) => { const v = range(a[7 + k]); if (v !== 0) e.stats[s] = v; });
  items[id] = e;
}
// pickup rules (my/FallEquipObj.as, base/BaseRoleProperies.as)
const fall = fs.readFileSync(path.join(ROOT, 'decomp/res/zmxy2_game/scripts/my/FallEquipObj.as'), 'utf8');
const boss = JSON.parse(fall.match(/bosslist:Array = (\[[^\]]*\])/)[1]);
const rules = {
  regen_frames: 24, bag_size: 25, ground_frames: 240, boss_loot: [...new Set([...boss, 'xyb'])],   // 小月饼 (中秋) stays on the ground like the other boss loot
  // usable items (PackThings.useClick): timed buffs last one hour of stage time and do not stack (HeroBuff)
  buff_frames: 86400,
  use: { sbbl: { buff: 'drop' }, xique: { buff: 'drop' }, jxbuff: { buff: 'hp' }, hhbuff: { buff: 'mp_regen' }, wdd: { special: 'wds_power' },
    // 大月饼 (BaseRoleProperies: +600 hp / +600 mp / +100 atk / +50 def, drop rate x1.5), one hour each
    jxdyb: { buff: 'moon_hp' }, jmdyb: { buff: 'moon_mp' }, jgjdyb: { buff: 'moon_atk' }, jfydyb: { buff: 'moon_def' }, jbldyb: { buff: 'moon_lucky' } },
  // effects of the running buffs add up (*_add, mp_regen) or multiply (*_mul); icon_scale is the original's HUD scale
  buffs: {
    drop: { drop_mul: 2, icon: 'sbbl_buff', icon_scale: 0.3 }, hp: { hp_mul: 1.5, icon: 'hn_buff', icon_scale: 0.3 }, mp_regen: { mp_regen: 10, icon: 'hh_guoqing_buff', icon_scale: 1 },
    moon_hp: { hp_add: 600, icon: 'buff_moon_hp', icon_scale: 0.3 }, moon_mp: { mp_add: 600, icon: 'buff_moon_mp', icon_scale: 0.3 },
    moon_atk: { atk_add: 100, icon: 'buff_moon_atk', icon_scale: 0.3 }, moon_def: { def_add: 50, icon: 'buff_moon_def', icon_scale: 0.3 },
    moon_lucky: { drop_mul: 1.5, icon: 'buff_moon_lucky', icon_scale: 0.3 },
    // 国庆: killing 劈天斧 / 风神盾 (Monster79/80.destroy -> setGuoqingAtkCount / DefCount), 20x20 icons unscaled
    gq_atk: { atk_add: 100, icon: 'atk_guoqing_buff', icon_scale: 1, label: '攻击 +100，持续一小时' }, gq_def: { def_add: 50, icon: 'def_guoqing_buff', icon_scale: 1, label: '防御 +50，持续一小时' },
  },
  kill_buffs: { 79: 'gq_atk', 80: 'gq_def' },   // monster id -> buff it grants when killed
  // 中秋: one 小月饼 from every boss; 10 -> a random 大月饼, 100 -> the hero's 绝版武器 (PackThings.swapBigMoonCake / swapMoonWeapon)
  moon: { cake: 'xyb', big: ['jxdyb', 'jmdyb', 'jgjdyb', 'jfydyb', 'jbldyb'], big_cost: 10, weapon_cost: 100, weapons: { 悟空: 'nyd', 唐僧: 'myz', 八戒: 'syc' } },
  // fashion: extra equipment / stone drop rate (User.getCurFashionEquipFallThingProbability)
  drop_bonus: { wkwdg: 0.1, wkbsz: 0.18, wkzyf: 0.2 },
  // 苍生挂饰: one revive (half HP / MP, short invincibility), not when falling out of the stage
  // 1级强化石 from bosses (BaseMonster.dropStone): only while the hero level is at most the stage's cap (-1 = always)
  stone_drop: { item: 'wpqhs1', level_caps: { sl11: 4, sl12: 7, sl13: 10, sl21: 13, sl22: 16, sl23: 19, sl31: 22, sl32: 25, sl33: 28, sl41: -1, sl51: 27, sl61: 27, sl71: -1, sl111: -1 } },
  // bag pages hold 25 entries each; items (道具) stack
  tabs: { equip: ['weapon', 'cloth', 'accessory', 'treasure'], item: ['item'], look: ['fashion', 'wing'] },
  unique: ['csgs'],
  // 炼丹炉 强化 (export/strength/Strength.as, AllEquipment.getStrengthNumber): success chance of one stone by
  // stone level and current +N; stones add up (max 1), the luck charm multiplies; a failure at +drop_from or more
  // loses a level unless a keep charm is in. Level 5 stones have no entry (useless in the original too).
  strengthen: {
    types: ['weapon', 'cloth', 'accessory', 'wing'],
    chance: {
      1: [0.375, 0.0937, 0.0234, 0.0058, 0, 0, 0],
      2: [1, 0.375, 0.0937, 0.0234, 0.0058, 0, 0],
      3: [1, 1, 0.375, 0.0937, 0.0234, 0.0058, 0],
      4: [1, 1, 1, 0.375, 0.0937, 0.0234, 0.0058],
    },
    luck_mul: 1.25, drop_from: 3,
  },
  // 炼丹炉 合成 (Fusion.as, AllEquipment.mixProduce): three materials in any order.
  //   treasure: new 法宝, hp/mp/atk/def = average of the materials (with their strengthening)
  //   fresh: a newly rolled item; sum: the materials' rolled stats added up; average: like treasure but equipment
  //   stone: free, may fail (materials are lost either way)
  fusion: {
    cost: 1000, stone_chance: 0.75,
    recipes: [
      { out: 'dshl', mats: ['dslj', 'dsyj', 'dsqz'], kind: 'treasure' },
      { out: 'tsgj', mats: ['tsgl', 'tsyp', 'tsyj'], kind: 'treasure' },
      { out: 'bsj', mats: ['bsxj', 'bszj', 'bsyz'], kind: 'treasure' },
      { out: 'lsys', mats: ['lcgy', 'lcld', 'lczh'], kind: 'treasure' },
      { out: 'xhmt', mats: ['xhyk', 'xhxh', 'xhmj'], kind: 'treasure' },
      { out: 'ssc', mats: ['qssp', 'jssp', 'lssp'], kind: 'fresh' },
      { out: 'gwj', mats: ['fygwj', 'yzfw', 'yinzfw'], kind: 'fresh' },
      { out: 'dzjj', mats: ['dzj', 't', 't'], kind: 'sum' }, { out: 'dzjj', mats: ['dzj', 'c', 'c'], kind: 'sum' },
      { out: 'dzjj', mats: ['dzj', 'ch', 'ch'], kind: 'sum' }, { out: 'dzjj', mats: ['dzj', 't', 'c'], kind: 'sum' },
      { out: 'dzjj', mats: ['dzj', 't', 'ch'], kind: 'sum' }, { out: 'dzjj', mats: ['dzj', 'c', 'ch'], kind: 'sum' },
      { out: 'qcp', mats: ['hshb', 'lshb', 'zshb'], kind: 'fresh' },
      { out: 'bszj', mats: ['bsxj', 'bsxj', 'bsxj'], kind: 'average' },
      { out: 'bsyz', mats: ['bszj', 'bszj', 'bszj'], kind: 'average' },
      { out: 'bsxj', mats: ['bsyz', 'bsyz', 'bsyz'], kind: 'average' },
      { out: 'wpqhs2', mats: ['wpqhs1', 'wpqhs1', 'wpqhs1'], kind: 'stone' },
      { out: 'wpqhs3', mats: ['wpqhs2', 'wpqhs2', 'wpqhs2'], kind: 'stone' },
      { out: 'wpqhs4', mats: ['wpqhs3', 'wpqhs3', 'wpqhs3'], kind: 'stone' },
      { out: 'dcyj', mats: ['xzyj', 'zzyj', 'gzyj'], kind: 'average' },
      { out: 'wds', mats: ['mzyj', 'szyj', 'dcyj'], kind: 'treasure' },
    ],
  },
  // 法宝 (AllEquipment.initSutraEquipment, MyEquipObj.growth, SutraInterface): growth = random rate in the range
  // (one decimal); up = stats per level, x growth, plus the full value again for the matching element
  // (金 atk, 水 mp, 火 hp, 土 def; 木 boosts the skill instead). Level L -> L+1 costs L^2 x cost_mul souls.
  treasures: {
    max_level: 10, cost_mul: 1000, mp_base: 30, mp_per_level: 10,
    elements: ['jin', 'mu', 'shui', 'huo', 'tu'], double_chance: 0.09,
    element_stat: { jin: 'atk', shui: 'mp', huo: 'hp', tu: 'def' },
    defs: {
      dshl: { growth: [0.5, 1.0], up: { hp: 20, mp: 20, atk: 4, def: 2 } },
      tsgj: { growth: [0.6, 1.2], up: { hp: 30, mp: 30, atk: 5, def: 2 } },
      bsj: { growth: [0.7, 1.4], up: { hp: 30, mp: 50, atk: 5, def: 2 } },
      lsys: { growth: [0.8, 1.6], up: { hp: 50, mp: 30, atk: 5, def: 4 } },
      xhmt: { growth: [1.0, 1.8], up: { hp: 30, mp: 30, atk: 9, def: 2 } },
      wds: { growth: [1.2, 2.0], up: { hp: 50, mp: 50, atk: 10, def: 5 }, fixed: { hp: 250, mp: 250, atk: 50, def: 25 },
        // one random passive: [stat, min, step, steps]
        passives: [['crit', 0.02, 0.01, 3], ['lifesteal', 0.02, 0.01, 3], ['mdef', 0.02, 0.01, 3], ['hp_regen', 2, 1, 3], ['mp_regen', 2, 1, 3]] },
    },
  },
  // 商城 (Micropayment, AllEquipment.findSellPrice): paid with 功勋 in the rebuild (the original's 点券 fall back to it).
  // 功勋 comes from the 4-1 boss, a limited number of times per day (Monster60).
  shop: {
    pages: { item: ['hhbuff', 'wdd', 'wpqhs4', 'wpqhs1', 'wpqhs3', 'sbbl', 'wpxyf', 'wpbdf'], look: ['ttzy', 'wkmrz', 'wkbsz', 'wkzyf', 'wkwdg'] },
    prices: { hhbuff: 250, wdd: 500, wpqhs4: 700, wpqhs1: 30, wpqhs3: 270, sbbl: 600, wpxyf: 300, wpbdf: 500, ttzy: 800, wkmrz: 800, wkbsz: 870, wkzyf: 900, wkwdg: 800 },
    per_page: 6,
    merit: { monster: 60, amount: 50, per_day: 1 },
  },
  revive: { item: 'csgs', invincible_frames: 24, ratio: 0.5, max_y: 1200 },
};
fs.writeFileSync(OUT, JSON.stringify({ _doc: 'From my/AllEquipment.as. stats: value or [min,max] roll. show = appearance frame on the rig. Frame counts are converted by game/tools/bake_data.gd.', rules, items }, null, 1));
console.log('equipment', Object.keys(items).length, '->', OUT);
