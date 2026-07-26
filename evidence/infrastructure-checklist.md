# TaleLah — Infrastructure & Accounts Checklist
# Sprint 0 · Day-0 Setup
#
# This file tracks every external account, API key, and service needed.
# Status: ❌ Not started · 🟡 In progress · ✅ Done · ⚠️ Blocked

## ── 1. Core AI APIs (P0 — needed immediately) ────────────────────────────

### 1.1 Alibaba Cloud + DashScope (Qwen LLM + Vision)
# URL: https://dashscope.console.aliyun.com/apiKey
# Needed for: Agents 1-4, 6 (Qwen-Max), Agent 1 (Qwen-VL-Max)
# Cost: Free tier available, pay-per-token
# Key env var: DASHSCOPE_API_KEY
# Status: ❌
# Notes: Sign up with Alibaba Cloud account → Model Studio → API Keys

### 1.2 Sarvam AI (Tamil ASR + TTS)
# URL: https://playground.sarvam.ai/
# Needed for: Tamil golden path (Saarika ASR + Bulbul TTS)
# Cost: Free tier (limited minutes)
# Key env var: SARVAM_API_KEY
# Status: ❌
# Notes: Critical for Day-1 risk test — sign up NOW

### 1.3 Google Cloud (Malay ASR + TTS)
# URL: https://console.cloud.google.com/
# Needed for: Malay ms-SG pack (Speech-to-Text + Text-to-Speech)
# Cost: $300 free credit for new accounts
# Key env var: GOOGLE_APPLICATION_CREDENTIALS (path to JSON)
# Status: ❌
# Notes: Enable Speech-to-Text API + Text-to-Speech API in console

## ── 2. Optional APIs (P1 — after golden path works) ──────────────────────

### 2.1 ElevenLabs (Voice Clone + Multilingual TTS)
# URL: https://elevenlabs.io/app/settings/api-keys
# Needed for: Parent voice narration (P1), TTS fallback
# Cost: Free tier (limited chars), $5/mo for Starter
# Key env var: ELEVENLABS_API_KEY
# Status: ❌ (P1 only)
# Notes: Go/no-go decision on Aug 1

## ── 3. Hosting & Deployment ──────────────────────────────────────────────

### 3.1 Backend Hosting
# Options (pick ONE):
#   a) Render.com — easiest, free tier, auto-deploy from GitHub
#      URL: https://render.com/ → New → Web Service → connect repo
#      Status: ❌
#   b) Railway.app — fast, good free tier
#      URL: https://railway.app/ → New Project → Deploy from GitHub
#      Status: ❌
#   c) Alibaba Cloud ECS/FC — judges may notice (but don't burn days on it)
#      Status: ❌
# Recommendation: Start with Render (fastest setup, free)
# Env var: RENDER_DEPLOY_HOOK (for CI/CD auto-deploy)

### 3.2 Frontend Hosting (Flutter Web)
# Options (pick ONE):
#   a) Vercel — free, fast, great DX
#      URL: https://vercel.com/
#      Status: ❌
#   b) Cloudflare Pages — free, fast CDN
#      URL: https://pages.cloudflare.com/
#      Status: ❌
#   c) Firebase Hosting — Google ecosystem
#      URL: https://console.firebase.google.com/
#      Status: ❌
# Recommendation: Vercel (if you already use it) or Cloudflare Pages

### 3.3 Database
# Options (pick ONE):
#   a) Supabase — PostgreSQL + Auth + Storage in one
#      URL: https://supabase.com/ → New Project
#      Status: ❌
#      Env var: DATABASE_URL=postgresql+asyncpg://...
#   b) Neon — serverless PostgreSQL, great free tier
#      URL: https://neon.tech/ → New Project
#      Status: ❌
#   c) Alibaba Cloud ApsaraDB — if optimizing for judge perception
#      Status: ❌
# Recommendation: Supabase (Postgres + Auth + Storage bundled)
# Notes: Dev uses SQLite (already configured), prod needs PostgreSQL

### 3.4 Object Storage (Media/Photos)
# Options (pick ONE):
#   a) Supabase Storage — included with Supabase
#      Status: ❌
#   b) Alibaba Cloud OSS — for judge perception
#      URL: https://oss.console.aliyun.com/
#      Status: ❌
#   c) Cloudflare R2 — S3-compatible, no egress fees
#      URL: https://dash.cloudflare.com/ → R2
#      Status: ❌
# Recommendation: Supabase Storage (bundled) or Cloudflare R2

### 3.5 Domain
# Options:
#   a) talelah.app / talelah.sg
#      Registrar: Namecheap, Cloudflare, or Porkbun
#      Status: ❌
#   b) Free subdomain from Vercel/Netlify for hackathon
#      Status: ❌ (fallback)
# Notes: Buy talelah.app if available (~$15)

## ── 4. GitHub & CI/CD ───────────────────────────────────────────────────

### 4.1 GitHub Repository
# URL: https://github.com/vinothjv/talelah
# Status: ❌ (not created yet)
# Actions needed:
#   - Create repo (public for hackathon visibility)
#   - Add branch protection on main (require PR + CI pass)
#   - Add secrets: DASHSCOPE_API_KEY, SARVAM_API_KEY, etc.

### 4.2 GitHub Secrets (add to repo Settings → Secrets → Actions)
# DASHSCOPE_API_KEY          → Alibaba Cloud Qwen key
# SARVAM_API_KEY             → Sarvam AI Tamil speech key
# GOOGLE_APPLICATION_CREDENTIALS → Google Cloud JSON key (base64)
# ELEVENLABS_API_KEY         → ElevenLabs key (P1)
# RENDER_DEPLOY_HOOK         → Render auto-deploy URL
# VERCEL_TOKEN               → Vercel deploy token
# VERCEL_ORG_ID              → Vercel org ID
# VERCEL_PROJECT_ID          → Vercel project ID
# DATABASE_URL               → Production database URL

## ── 5. Human Reviewers ──────────────────────────────────────────────────

### 5.1 Tamil Reviewer (P0 — CRITICAL)
# Needed for: Verify ta-SG golden path content before demo
# Status: ❌
# Notes: Must be a fluent Singapore Tamil speaker

### 5.2 Mandarin Reviewer (P0)
# Needed for: Verify zh-SG sample path
# Status: ❌
# Notes: At least 1 human-reviewed Mandarin sample

### 5.3 Malay Reviewer (P0)
# Needed for: Verify ms-SG sample path + spec-swap demo
# Status: ❌
# Notes: At least 1 human-reviewed Malay sample

## ── 6. Pilot & Consent ──────────────────────────────────────────────────

### 6.1 Parent-Child Pilot Sessions
# Needed: 3 consented sessions (you + twins is #1)
# Status: ❌
# Notes: Plain-language consent form needed before Aug 2

## ── 7. Marketing & Submission ───────────────────────────────────────────

### 7.1 Demo Video
# Length: 2-3 minutes
# Platform: YouTube (unlisted) or Loom
# Status: ❌
# Due: Aug 4

### 7.2 Social Post
# Platform: LinkedIn or X (Twitter)
# Must tag: @QoderOfficial, @AlibabaCloud
# Must include: #QoderHackathon, #BuildWithQoder
# Status: ❌
# Due: Aug 5

### 7.3 Hackathon Submission Form
# URL: (check hackathon page for submission link)
# Status: ❌
# Due: Aug 5 (before deadline)

## ── Quick Start Order ────────────────────────────────────────────────────
# 1. Sign up for DashScope (Alibaba Cloud) — unlocks all Qwen models
# 2. Sign up for Sarvam AI — Day-1 Tamil TTS/ASR risk test
# 3. Create GitHub repo + add secrets
# 4. Set up Render.com for backend deploy
# 5. Buy talelah.app domain (if available)
# 6. Sign up for Google Cloud (Malay speech)
# 7. Find Tamil/Mandarin/Malay reviewers
# 8. Everything else can wait until Sprint 2+
