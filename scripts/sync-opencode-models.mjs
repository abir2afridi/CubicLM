#!/usr/bin/env node
// Auto-sync xKiro + B.AI free models into opencode.jsonc
// Usage: BAI_API_KEY=sk-... XKIRO_API_KEY=sk-xt-... node scripts/sync-opencode-models.mjs
// For xKiro, /v1/models is public (no key needed), for B.AI key required.

import fs from 'fs';
import path from 'path';
import os from 'os';

const configPath = path.join(os.homedir(), '.config', 'opencode', 'opencode.jsonc');

async function fetchXkiro() {
  const res = await fetch('https://api.xkiro.com/v1/models');
  if (!res.ok) throw new Error(`xKiro fetch failed ${res.status}`);
  const json = await res.json();
  return json.data;
}

async function fetchBai(apiKey) {
  if (!apiKey) return null;
  const res = await fetch('https://api.b.ai/v1/models', {
    headers: { Authorization: `Bearer ${apiKey}` }
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`B.AI fetch failed ${res.status}: ${txt.slice(0,300)}`);
  }
  const json = await res.json();
  // B.AI returns { data: [{id, object, created}] }
  return json.data;
}

async function main() {
  const raw = fs.readFileSync(configPath, 'utf8');
  const cfg = JSON.parse(raw);

  // ---- xKiro ----
  console.log('Fetching xKiro models...');
  const xData = await fetchXkiro();
  const xFree = xData.filter(m => m.access_tier === 'free');
  // Optionally include all if you want every model: const toAdd = xData;
  const toAdd = xFree; // keep only free; change to xData for all 102
  toAdd.sort((a,b)=>a.id.localeCompare(b.id));
  const xModels = {};
  for (const m of toAdd) {
    xModels[m.id] = { name: m.display_name || m.id };
  }
  // Keep existing premium picks so user doesn't lose them
  const keepPremium = ["openai/gpt-5.6-sol","z-ai/glm-5.2","qwen/qwen3.8-max","anthropic/claude-opus-4.8","anthropic/claude-sonnet-4.5","google/gemini-2.5-pro","moonshotai/kimi-k3"];
  for (const id of keepPremium) {
    if (!xModels[id]) {
      const found = xData.find(m=>m.id===id);
      xModels[id] = { name: found?.display_name || id };
    }
  }
  cfg.provider = cfg.provider || {};
  cfg.provider.xkiro = cfg.provider.xkiro || { name: "xKiro", npm: "@ai-sdk/openai-compatible", options: {} };
  cfg.provider.xkiro.options.baseURL = "https://api.xkiro.com/v1";
  cfg.provider.xkiro.options.apiKey = "{env:XKIRO_API_KEY}";
  cfg.provider.xkiro.models = xModels;
  console.log(`xKiro: ${Object.keys(xModels).length} models (free: ${xFree.length})`);

  // ---- B.AI ----
  const baiKey = process.env.BAI_API_KEY;
  const fallbackBai = [
    'claude-fable-5','claude-haiku-4-5','claude-opus-4-5','claude-opus-4-6','claude-opus-4-7','claude-opus-4-8','claude-opus-5','claude-sonnet-4-5','claude-sonnet-4-6','claude-sonnet-5','deepseek-v3.2','deepseek-v4-flash','deepseek-v4-pro','gemini-3-1-pro','gemini-3-5-flash','gemini-3-5-flash-lite','gemini-3-6-flash','gemini-3-flash','glm-5-1','glm-5-2','glm-5-3','glm-5-3-flash','gpt-5-2','gpt-5-4','gpt-5-4-mini','gpt-5-4-nano','gpt-5-4-pro','gpt-5-5','gpt-5-5-instant','gpt-5-6-luna','gpt-5-6-sol','gpt-5-6-terra','gpt-5-mini','gpt-5-nano','grok-4.5','grok-4.6','hy3','kimi-k2.5','kimi-k2.6','kimi-k3','mimo-v2.5','mimo-v2.5-pro','minimax-m2.5','minimax-m2.7','minimax-m3','qwen3-8-flash','qwen3.6-27b','qwen3.7-max','qwen3.8-27b','qwen3.8-max'
  ];
  if (baiKey) {
    console.log('Fetching B.AI models via API...');
    try {
      const bData = await fetchBai(baiKey);
      console.log(`B.AI API count: ${bData.length}`);
      const bModels = {};
      for (const m of bData) bModels[m.id] = { name: m.id };
      cfg.provider.bai = cfg.provider.bai || { name: "B.AI", npm: "@ai-sdk/openai-compatible", options: {} };
      cfg.provider.bai.options.baseURL = "https://api.b.ai/v1";
      cfg.provider.bai.options.apiKey = "{env:BAI_API_KEY}";
      if (Object.keys(bModels).length > 0) {
        cfg.provider.bai.models = bModels;
        console.log(`B.AI: ${Object.keys(bModels).length} models synced from API`);
      }
    } catch (e) {
      console.warn(`B.AI API failed: ${e.message}`);
      console.warn('Fallback to docs sitemap list (50 models)');
      const bModels = {};
      fallbackBai.forEach(id=> bModels[id]={name:id});
      cfg.provider.bai = cfg.provider.bai || { name: "B.AI", npm: "@ai-sdk/openai-compatible", options: {} };
      cfg.provider.bai.options.baseURL = "https://api.b.ai/v1";
      cfg.provider.bai.options.apiKey = "{env:BAI_API_KEY}";
      cfg.provider.bai.models = bModels;
    }
  } else {
    console.log('BAI_API_KEY not set -> using fallback docs list (50 models). Set env and re-run for live API list.');
    const bModels = {};
    fallbackBai.forEach(id=> bModels[id]={name:id});
    cfg.provider.bai = cfg.provider.bai || { name: "B.AI", npm: "@ai-sdk/openai-compatible", options: {} };
    cfg.provider.bai.options.baseURL = "https://api.b.ai/v1";
    cfg.provider.bai.options.apiKey = "{env:BAI_API_KEY}";
    cfg.provider.bai.models = bModels;
  }

  fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2));
  console.log(`\nUpdated ${configPath}`);
  console.log('Restart opencode to see changes: quit opencode and run `opencode` again, then `/models`');
}

main().catch(e=>{console.error(e); process.exit(1)});
