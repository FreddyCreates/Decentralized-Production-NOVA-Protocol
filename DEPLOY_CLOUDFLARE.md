# 🚀 Deploy NOVA to Cloudflare Pages — Get Your Live URL

You have a paid Cloudflare account. Here's how to get your NOVA dashboard
live on the internet in under 2 minutes — like Fly.io gives you a URL,
Cloudflare Pages gives you `nova-protocol.pages.dev`.

---

## Quick Deploy (2 minutes)

### Step 1: Install Wrangler (Cloudflare's CLI)

```bash
npm install -g wrangler
```

### Step 2: Login to Your Cloudflare Account

```bash
wrangler login
```

This opens your browser — click "Allow" and you're authenticated.

### Step 3: Deploy

```bash
npm run deploy
```

That's it. Done. Your dashboard is now live at:

```
https://nova-protocol.pages.dev
```

The founder dashboard is at:
```
https://nova-protocol.pages.dev/founder-dashboard.html
```

---

## What You Get

| What | URL |
|------|-----|
| Main Dashboard | `https://nova-protocol.pages.dev` |
| Founder Dashboard | `https://nova-protocol.pages.dev/founder-dashboard.html` |
| Custom Domain | You can add your own domain in Cloudflare dashboard |

---

## Custom Domain (Optional)

If you want `nova.yourdomain.com` instead of `nova-protocol.pages.dev`:

1. Go to https://dash.cloudflare.com
2. Click **Pages** in the sidebar
3. Click your `nova-protocol` project
4. Go to **Custom domains** tab
5. Add your domain — Cloudflare handles SSL automatically

---

## Local Preview (Before Deploying)

Want to see it locally first?

```bash
npm run dev:local
```

Opens at `http://localhost:3000`

---

## Other Commands

| Command | What it does |
|---------|--------------|
| `npm run deploy` | Deploy to production (your live URL) |
| `npm run deploy:preview` | Deploy a preview version (separate URL) |
| `npm run dev:local` | Run locally on port 3000 |

---

## Updating Your Site

Made changes? Just run `npm run deploy` again. Cloudflare deploys in ~5 seconds.

---

## Project Name

The deploy uses project name `nova-protocol`. First time you run it,
Cloudflare creates the project automatically. If you want a different name,
edit `wrangler.toml` and the scripts in `package.json`.
