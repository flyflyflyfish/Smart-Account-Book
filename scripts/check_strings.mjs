#!/usr/bin/env node
/**
 * 资源一致性检查（CI 本地均可运行，无第三方依赖）：
 *   1. entry/src/main/resources 下所有 .json 语法校验；
 *   2. zh_CN / en_US 的 string.json key 必须是 base 的子集（缺省回落 base，不允许多出无效 key）；
 *   3. 代码中所有 $r('app.string.*') / getStringSync($r('app.string.*')) 引用均有定义。
 * 任一失败以非零码退出。
 */
import fs from 'node:fs';
import path from 'node:path';

const RES_DIR = path.resolve('entry/src/main/resources');
const SRC_DIR = path.resolve('entry/src/main/ets');
const errors = [];

function walk(dir, ext, out = []) {
  if (!fs.existsSync(dir)) {
    return out;
  }
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    const stat = fs.statSync(full);
    if (stat.isDirectory()) {
      walk(full, ext, out);
    } else if (ext.some((e) => name.endsWith(e))) {
      out.push(full);
    }
  }
  return out;
}

// 1. JSON 语法校验
const jsonFiles = walk(RES_DIR, ['.json']);
const stringKeySets = new Map();
for (const file of jsonFiles) {
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    errors.push(`JSON 语法错误: ${file}: ${err.message}`);
    continue;
  }
  if (path.basename(file) === 'string.json' && Array.isArray(parsed.string)) {
    const keys = new Set(parsed.string.map((item) => item.name));
    const locale = path.relative(RES_DIR, file).split(path.sep)[0];
    stringKeySets.set(locale, keys);
  }
}

// 2. zh_CN / en_US 的 key 必须是 base 的子集（缺省项运行时回落 base，多出项无效）
const baseKeys = stringKeySets.get('base');
if (!baseKeys) {
  errors.push('未找到 entry/src/main/resources/base/element/string.json');
} else {
  for (const [locale, keys] of stringKeySets) {
    if (locale === 'base') {
      continue;
    }
    for (const key of keys) {
      if (!baseKeys.has(key)) {
        errors.push(`[${locale}] 多出 base 没有的 string key: ${key}`);
      }
    }
  }
}

// 3. 代码引用的 app.string.* 必须有定义
if (baseKeys) {
  const refRe = /app\.string\.([A-Za-z0-9_]+)/g;
  const missing = new Map();
  for (const file of walk(SRC_DIR, ['.ets', '.ts'])) {
    const content = fs.readFileSync(file, 'utf8');
    let m;
    while ((m = refRe.exec(content)) !== null) {
      if (!baseKeys.has(m[1])) {
        if (!missing.has(m[1])) {
          missing.set(m[1], file);
        }
      }
    }
  }
  for (const [key, file] of missing) {
    errors.push(`引用了未定义的 app.string.${key}（首见 ${path.relative('.', file)}）`);
  }
}

if (errors.length > 0) {
  console.error(`资源一致性检查失败，共 ${errors.length} 处：`);
  for (const e of errors) {
    console.error(`  - ${e}`);
  }
  process.exit(1);
}
const localeList = [...stringKeySets.keys()].join(', ');
console.log(`资源一致性检查通过：${jsonFiles.length} 个 JSON 语法正确；string key 对齐（${localeList}）；代码引用均有定义。`);
