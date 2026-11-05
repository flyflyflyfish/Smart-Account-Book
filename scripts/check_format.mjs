#!/usr/bin/env node
// 提交前格式检查（无依赖），按 .editorconfig 约定检查：
//   1. 行尾空格（Markdown 除外）
//   2. CRLF 换行
//   3. 文件末尾缺少换行
//   4. ets / ts / json / json5 使用 Tab 缩进
//
// 用法：
//   node scripts/check_format.mjs <文件...>      检查指定文件（pre-commit 使用）
//   node scripts/check_format.mjs --base <ref>   检查相对 <ref> 有改动的文件（CI 使用）
//   node scripts/check_format.mjs --all          检查全部已跟踪文件
//   node scripts/check_format.mjs                检查已暂存的文件
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname } from 'node:path';

const CHECK_EXT = new Set(['.ets', '.ts', '.js', '.mjs', '.json', '.json5', '.md', '.yml', '.yaml', '.sh']);
const TAB_EXT = new Set(['.ets', '.ts', '.json', '.json5']);
const TRIM_EXEMPT_EXT = new Set(['.md']);
const SKIP_PREFIXES = ['oh_modules/', 'node_modules/', 'build/', '.hvigor/', 'AppScope/resources/rawfile/'];
const SKIP_NAMES = new Set(['oh-package-lock.json5']);
const MAX_BYTES = 1024 * 1024;

function git(args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function lines(out) {
  return out.split('\n').map((s) => s.trim()).filter(Boolean);
}

function changedSince(base) {
  try {
    return lines(git(['diff', '--name-only', '--diff-filter=ACM', base]));
  } catch {
    try {
      console.warn(`无法与 ${base} 比较，改为检查最近一次提交的改动`);
      return lines(git(['diff', '--name-only', '--diff-filter=ACM', 'HEAD~1']));
    } catch {
      console.warn('没有可比较的历史，跳过格式检查');
      return [];
    }
  }
}

function collectFiles(argv) {
  if (argv[0] === '--all') return lines(git(['ls-files']));
  if (argv[0] === '--base') {
    if (!argv[1]) {
      console.error('--base 需要提供比较的分支或提交');
      process.exit(2);
    }
    return changedSince(argv[1]);
  }
  if (argv.length > 0) return argv;
  return lines(git(['diff', '--cached', '--name-only', '--diff-filter=ACM']));
}

function shouldCheck(file) {
  const normalized = file.replaceAll('\\', '/');
  if (SKIP_PREFIXES.some((p) => normalized.startsWith(p))) return false;
  if (SKIP_NAMES.has(normalized.split('/').pop())) return false;
  if (!CHECK_EXT.has(extname(normalized))) return false;
  if (!existsSync(file)) return false;
  return statSync(file).size <= MAX_BYTES;
}

function checkFile(file) {
  const problems = [];
  const ext = extname(file);
  const text = readFileSync(file, 'utf8');
  if (text.length === 0) return problems;

  if (!text.endsWith('\n')) problems.push(`${file}: 文件末尾缺少换行`);
  text.split('\n').forEach((line, i) => {
    const n = i + 1;
    if (line.endsWith('\r')) {
      problems.push(`${file}:${n}: 使用了 CRLF 换行，应为 LF`);
      return;
    }
    if (!TRIM_EXEMPT_EXT.has(ext) && /[ \t]+$/.test(line)) {
      problems.push(`${file}:${n}: 行尾有多余空格`);
    }
    if (TAB_EXT.has(ext) && /^ *\t/.test(line)) {
      problems.push(`${file}:${n}: 使用了 Tab 缩进，应为 2 个空格`);
    }
  });
  return problems;
}

const files = collectFiles(process.argv.slice(2)).filter(shouldCheck);
if (files.length === 0) {
  console.log('没有需要检查的文件');
  process.exit(0);
}

const problems = files.flatMap(checkFile);
if (problems.length > 0) {
  console.error(problems.join('\n'));
  console.error(`\n格式检查未通过：${problems.length} 处问题（共检查 ${files.length} 个文件）`);
  process.exit(1);
}
console.log(`格式检查通过（共检查 ${files.length} 个文件）`);
