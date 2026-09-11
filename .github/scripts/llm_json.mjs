#!/usr/bin/env node
/**
 * llm_json.mjs — shared multi-provider LLM JSON client (Node.js version).
 *
 * Posts a chat-completion request through an ordered chain of OpenAI-compatible
 * providers: openrouter -> gemini -> groq -> cline -> ollama
 *
 * Usage:
 *   llm_json.mjs --system-file SYS --user-file USER --out OUT \
 *               --schema '<JQ_BOOL_FILTER>' [--effort low|medium|high] [--max-tokens N]
 *
 * Env:
 *   OPENROUTER_API_KEY / GEMINI_API_KEY / GROQ_API_KEY / CLINE_API_KEY / OLLAMA_API_KEY
 *   LLM_PROVIDER_ORDER  (space/comma-separated subset/reorder)
 *   LLM_MAX_ATTEMPTS    (default 3)
 *   LLM_BACKOFF         (default "5 15 45" seconds)
 *   LLM_REASONING_EFFORT (explicit override)
 */

import { readFile, writeFile, rename, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomInt } from 'node:crypto';

// ─── Provider specs ──────────────────────────────────────────────────────────
const PROVIDER_SPECS = [
  { name: 'openrouter', endpointEnv: 'OPENROUTER_ENDPOINT', endpointDefault: 'https://openrouter.ai/api/v1/chat/completions', keysEnv: 'OPENROUTER_API_KEY', modelsEnv: 'OPENROUTER_MODELS', modelsDefault: 'nex-agi/nex-n2.5-mini:free', supportsEffort: false },
  { name: 'gemini',     endpointEnv: 'GEMINI_ENDPOINT',     endpointDefault: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions', keysEnv: 'GEMINI_API_KEY', modelsEnv: 'GEMINI_MODELS', modelsDefault: 'gemini-3.5-flash-lite gemini-3.1-flash-lite gemini-3-flash-preview', supportsEffort: false },
  { name: 'groq',       endpointEnv: 'GROQ_ENDPOINT',       endpointDefault: 'https://api.groq.com/openai/v1/chat/completions', keysEnv: 'GROQ_API_KEY', modelsEnv: 'GROQ_MODELS', modelsDefault: 'openai/gpt-oss-20b qwen/qwen3.6-27b groq/compound-mini', supportsEffort: true },
  { name: 'cline',      endpointEnv: 'CLINE_ENDPOINT',      endpointDefault: 'https://api.cline.bot/api/v1/chat/completions', keysEnv: 'CLINE_API_KEY', modelsEnv: 'CLINE_MODELS', modelsDefault: 'openrouter/free', supportsEffort: false },
  { name: 'ollama',     endpointEnv: 'OLLAMA_ENDPOINT',     endpointDefault: 'https://ollama.com/v1/chat/completions', keysEnv: 'OLLAMA_API_KEY', modelsEnv: 'OLLAMA_MODELS', modelsDefault: 'gpt-oss:20b gpt-oss:120b', supportsEffort: false },
];

// ─── Helpers ─────────────────────────────────────────────────────────────────
function fail(msg) {
  console.error(`::error ::llm_json: ${msg}`);
  process.exit(1);
}

function log(msg) {
  console.error(`llm_json: ${msg}`);
}

function withJitter(base) {
  if (base <= 0) return 0;
  const delta = Math.floor(base / 5);
  const span = delta * 2 + 1;
  return base - delta + randomInt(span);
}

function backoffFor(idx, backoffArr) {
  const i = Math.min(idx, backoffArr.length - 1);
  return withJitter(backoffArr[i] ?? 0);
}

function isTransport(code) {
  return [0, 429, 500, 502, 503, 504].includes(code);
}

function isKeyFailure(code) {
  return [401, 402, 403].includes(code);
}

// ─── Schema validation (jq-style boolean filter) ─────────────────────────────
function compileSchema(schema) {
  // Convert simple jq-style expressions to JS validators
  // Supported: type=="object", (.field|type=="string"), (.field=="val" or .field=="val2")
  const trimmed = schema.trim();

  // Simple type check: type=="object"
  const typeMatch = trimmed.match(/^type=="(\w+)"$/);
  if (typeMatch) {
    return (obj) => typeof obj === typeMatch[1];
  }

  // AND expressions: expr1 and expr2
  const andParts = splitTopLevel(trimmed, ' and ');
  if (andParts.length > 1) {
    const validators = andParts.map(compileSchema);
    return (obj) => validators.every(v => v(obj));
  }

  // OR expressions inside parentheses: (.field=="val1" or .field=="val2")
  const orMatch = trimmed.match(/^\((.+)\)$/);
  if (orMatch) {
    const orParts = splitTopLevel(orMatch[1], ' or ');
    if (orParts.length > 1) {
      const validators = orParts.map(p => compileSchema(p.trim()));
      return (obj) => validators.some(v => v(obj));
    }
  }

  // Field type check: (.field|type=="string") or .field|type=="string"
  const fieldTypeMatch = trimmed.match(/^\(?\.(\w+)\|type=="(\w+)"\)?$/);
  if (fieldTypeMatch) {
    const [, field, type] = fieldTypeMatch;
    if (type === 'array') {
      return (obj) => Array.isArray(obj?.[field]);
    }
    return (obj) => typeof obj?.[field] === type;
  }

  // Field value check: (.field=="value") or .field=="value"
  const fieldValueMatch = trimmed.match(/^\(?\.(\w+)==(".*")\)?$/);
  if (fieldValueMatch) {
    const [, field, valueStr] = fieldValueMatch;
    const value = JSON.parse(valueStr);
    return (obj) => obj?.[field] === value;
  }

  fail(`unsupported schema expression: ${schema}`);
}

function splitTopLevel(str, delimiter) {
  const parts = [];
  let depth = 0;
  let current = '';
  let i = 0;
  while (i < str.length) {
    if (str[i] === '(') depth++;
    else if (str[i] === ')') depth--;
    if (depth === 0 && str.slice(i, i + delimiter.length) === delimiter) {
      parts.push(current);
      current = '';
      i += delimiter.length;
    } else {
      current += str[i];
      i++;
    }
  }
  parts.push(current);
  return parts;
}

// ─── Strip fenced code blocks ────────────────────────────────────────────────
function stripFences(text) {
  const lines = text.split('\n');
  let first = 0;
  let last = lines.length - 1;
  if (last >= 0 && /^```[A-Za-z0-9]*$/.test(lines[0])) first = 1;
  if (last >= first && /^```$/.test(lines[last])) last--;
  return lines.slice(first, last + 1).join('\n');
}

// ─── Extract content from OpenAI response ────────────────────────────────────
function extractContent(body) {
  const content = body?.choices?.[0]?.message?.content;
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content.map(p => (typeof p === 'object' ? p.text ?? '' : p)).join('');
  }
  return '';
}

function apiErrorMessage(body) {
  const msg = body?.error?.message ?? body?.error ?? body?.message;
  if (!msg) return '';
  return String(msg).replace(/\n/g, ' ').slice(0, 300);
}

// ─── Main LLM request with fallback ─────────────────────────────────────────
async function requestWithFallback({ sysFile, userFile, schema, effort, maxTokens, maxAttempts, backoffArr, activeProviders, phase = 'primary', assistant = '', correction = '' }) {
  const sys = await readFile(sysFile, 'utf8');
  const user = await readFile(userFile, 'utf8');
  let lastMsg = '';
  let lastCode = 0;

  for (const providerSpec of activeProviders) {
    const { name, endpointEnv, endpointDefault, keysEnv, modelsEnv, modelsDefault, supportsEffort } = providerSpec;
    const endpoint = process.env[endpointEnv] || endpointDefault;

    // Collect keys
    const keysEnvVar = process.env[keysEnv];
    if (!keysEnvVar) {
      log(`skipping provider ${name} (no key configured)`);
      continue;
    }
    const keys = keysEnvVar.split(/\s+/).filter(Boolean);
    if (keys.length === 0) {
      log(`skipping provider ${name} (no key configured)`);
      continue;
    }

    // Resolve models
    const modelsStr = process.env[modelsEnv] || modelsDefault;
    const models = modelsStr.split(/\s+/).filter(Boolean);

    let keyIdx = 0;
    for (const key of keys) {
      keyIdx++;
      for (const model of models) {
        let forceNoEffort = false;
        let nextKey = false;
        let attempt = 1;

        while (attempt <= maxAttempts) {
          const sendEffort = !forceNoEffort && supportsEffort && effort;
          const body = buildBody({ model, sendEffort, effort, sys, user, assistant, correction, maxTokens });

          const { code, body: respBody, headers } = await post(endpoint, key, body);
          const cmsg = apiErrorMessage(respBody);
          if (cmsg) lastMsg = cmsg;
          lastCode = code;

          if (code === 200) {
            const content = extractContent(respBody);
            if (content) {
              log(`HTTP 200 (${phase}) via ${name}/${model} on key ${keyIdx}/${keys.length}, attempt ${attempt}/${maxAttempts}`);
              return content;
            }
            // Empty content — transient, retry
            const fr = respBody?.choices?.[0]?.finish_reason ?? '';
            if (attempt < maxAttempts) {
              const retryAfter = parseRetryAfter(headers);
              const delay = retryAfter ?? backoffFor(attempt - 1, backoffArr);
              log(`HTTP 200 empty content (${phase}) via ${name}/${model} on key ${keyIdx}/${keys.length}${fr ? ` [finish=${fr}]` : ''}${cmsg ? ` : ${cmsg}` : ''}; backoff ${delay}s before attempt ${attempt + 1}/${maxAttempts}`);
              await sleep(delay);
              attempt++;
              continue;
            }
            log(`empty-content exhausted (HTTP 200, ${phase}, ${name}/${model})${fr ? ` [finish=${fr}]` : ''}${cmsg ? ` : ${cmsg}` : ''} after ${attempt} attempt(s); next model`);
            break;
          }

          if (isKeyCap(code, respBody)) {
            log(`key ${keyIdx}/${keys.length} hit the free-tier daily cap (HTTP 429, ${name}); next key`);
            nextKey = true;
            break;
          }
          if (isKeyFailure(code)) {
            log(`key ${keyIdx}/${keys.length} rejected HTTP ${code} (${phase}, ${name}); next key`);
            nextKey = true;
            break;
          }

          if ([400, 404, 422].includes(code)) {
            if (!forceNoEffort && supportsEffort && effort && cmsg.includes('reasoning_effort')) {
              log(`HTTP ${code} (${phase}, ${name}/${model}) mentions reasoning_effort; retrying once without it`);
              forceNoEffort = true;
              continue;
            }
            log(`HTTP ${code} (${phase}, ${name}/${model}); model unavailable, next model${cmsg ? ` : ${cmsg}` : ''}`);
            break;
          }

          if (isTransport(code)) {
            if (attempt < maxAttempts) {
              const retryAfter = parseRetryAfter(headers);
              const delay = retryAfter ?? backoffFor(attempt - 1, backoffArr);
              log(`transport HTTP ${code} (${phase}) via ${name}/${model} on key ${keyIdx}/${keys.length}; backoff ${delay}s before attempt ${attempt + 1}/${maxAttempts}`);
              await sleep(delay);
              attempt++;
              continue;
            }
            log(`transport exhausted (HTTP ${code}, ${phase}, ${name}/${model}); next model`);
            break;
          }

          // Unexpected status — next model
          log(`HTTP ${code} (${phase}, ${name}/${model}); next model${cmsg ? ` : ${cmsg}` : ''}`);
          break;
        }

        if (nextKey) break;
      }
    }
  }

  fail(`all providers failed on ${phase}: ${lastMsg || '(no message)'} (last HTTP ${lastCode})`);
}

function buildBody({ model, sendEffort, effort, sys, user, assistant, correction, maxTokens }) {
  const messages = [
    { role: 'system', content: sys },
    { role: 'user', content: user },
  ];
  if (assistant) {
    messages.push({ role: 'assistant', content: assistant });
    messages.push({ role: 'user', content: correction });
  }
  const body = { model, messages, max_tokens: maxTokens };
  if (sendEffort && effort) body.reasoning_effort = effort;
  return body;
}

async function post(endpoint, key, body) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 60_000);
  try {
    const resp = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const headers = Object.fromEntries(resp.headers.entries());
    let respBody;
    const text = await resp.text();
    try { respBody = JSON.parse(text); } catch { respBody = {}; }
    return { code: resp.status, body: respBody, headers };
  } catch (err) {
    return { code: 0, body: {}, headers: {} };
  } finally {
    clearTimeout(timeout);
  }
}

function parseRetryAfter(headers) {
  const val = headers['retry-after'];
  if (!val) return null;
  const n = parseInt(val, 10);
  if (isNaN(n) || n <= 0 || n > 60) return null;
  return n;
}

function isKeyCap(code, body) {
  return code === 429 && body?.error?.metadata?.limit_source === 'openrouter_free_tier_daily';
}

function sleep(seconds) {
  return new Promise(r => setTimeout(r, seconds * 1000));
}

// ─── Parse CLI args ──────────────────────────────────────────────────────────
function parseArgs(argv) {
  const args = { maxTokens: 1500 };
  for (let i = 2; i < argv.length; i++) {
    switch (argv[i]) {
      case '--system-file': args.sysFile = argv[++i]; break;
      case '--user-file':   args.userFile = argv[++i]; break;
      case '--out':         args.out = argv[++i]; break;
      case '--schema':      args.schema = argv[++i]; break;
      case '--effort':      args.effort = argv[++i]; break;
      case '--max-tokens':
        args.maxTokens = parseInt(argv[++i], 10);
        if (isNaN(args.maxTokens) || args.maxTokens < 0) fail('--max-tokens must be a non-negative integer');
        break;
      case '-h': case '--help':
        console.log(`Usage: llm_json.mjs --system-file SYS --user-file USER --out OUT --schema '<JQ_BOOL_FILTER>' [--effort low|medium|high] [--max-tokens N]`);
        process.exit(0);
      default: fail(`unknown argument: ${argv[i]}`);
    }
  }
  if (!args.sysFile) fail('--system-file is required');
  if (!args.userFile) fail('--user-file is required');
  if (!args.out) fail('--out is required');
  if (!args.schema) fail('--schema is required');
  if (args.effort && !['', 'low', 'medium', 'high'].includes(args.effort)) fail('--effort must be one of: low, medium, high');
  return args;
}

// ─── Main ────────────────────────────────────────────────────────────────────
async function main() {
  const args = parseArgs(process.argv);

  const maxAttempts = parseInt(process.env.LLM_MAX_ATTEMPTS || '3', 10);
  if (maxAttempts < 1) fail('LLM_MAX_ATTEMPTS must be >= 1');

  const backoffStr = process.env.LLM_BACKOFF || '5 15 45';
  const backoffArr = backoffStr.split(/\s+/).map(Number);

  // Effort resolution
  let effort;
  if ('LLM_REASONING_EFFORT' in process.env) {
    effort = process.env.LLM_REASONING_EFFORT;
  } else {
    effort = args.effort || '';
  }

  // Resolve active providers
  const orderRaw = (process.env.LLM_PROVIDER_ORDER || 'openrouter gemini groq cline ollama').replace(/,/g, ' ');
  const orderTokens = orderRaw.split(/\s+/).filter(Boolean);
  const activeProviders = [];
  const seen = new Set();
  for (const name of orderTokens) {
    const spec = PROVIDER_SPECS.find(p => p.name === name);
    if (spec && !seen.has(name)) {
      activeProviders.push(spec);
      seen.add(name);
    } else if (!spec) {
      log(`warning: unknown provider '${name}' in LLM_PROVIDER_ORDER; ignoring`);
    }
  }
  if (activeProviders.length === 0) fail('LLM_PROVIDER_ORDER contained no known provider');

  // Check at least one key is configured
  const anyKey = activeProviders.some(p => !!process.env[p.keysEnv]);
  if (!anyKey) fail('no API key configured (set OPENROUTER_API_KEY / GEMINI_API_KEY / GROQ_API_KEY / CLINE_API_KEY / OLLAMA_API_KEY)');

  const validate = compileSchema(args.schema);

  // Primary call
  let content = await requestWithFallback({
    sysFile: args.sysFile,
    userFile: args.userFile,
    schema: args.schema,
    effort,
    maxTokens: args.maxTokens,
    maxAttempts,
    backoffArr,
    activeProviders,
    phase: 'primary',
  });

  if (!content) fail('HTTP 200 but response contained no message content');

  // Strip fences and validate
  let candidate = stripFences(content);
  let parsed;
  try { parsed = JSON.parse(candidate); } catch { parsed = null; }

  if (parsed && validate(parsed)) {
    await writeOut(args.out, parsed);
    log(`wrote validated JSON to ${args.out}`);
    return;
  }

  // One semantic correction retry
  log('response failed schema validation; attempting one semantic correction');
  const correctionPrompt = 'Your previous reply was not valid JSON matching the required schema. Reply with ONLY valid JSON, no markdown, no prose.';

  content = await requestWithFallback({
    sysFile: args.sysFile,
    userFile: args.userFile,
    schema: args.schema,
    effort,
    maxTokens: args.maxTokens,
    maxAttempts,
    backoffArr,
    activeProviders,
    phase: 'correction',
    assistant: content,
    correction: correctionPrompt,
  });

  if (!content) fail('correction HTTP 200 but response contained no message content');

  candidate = stripFences(content);
  try { parsed = JSON.parse(candidate); } catch { parsed = null; }

  if (parsed && validate(parsed)) {
    await writeOut(args.out, parsed);
    log(`wrote corrected validated JSON to ${args.out}`);
    return;
  }

  fail('response still failed schema validation after one correction attempt');
}

async function writeOut(outPath, data) {
  const tmpDir = await mkdtemp(join(tmpdir(), 'llm_out_'));
  const tmpFile = join(tmpDir, 'out.json');
  try {
    await writeFile(tmpFile, JSON.stringify(data, null, 2));
    await rename(tmpFile, outPath);
  } finally {
    await rm(tmpDir, { recursive: true, force: true });
  }
}

main().catch(err => fail(err.message));
