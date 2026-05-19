# ScholarDesk CORS Proxy - Cloudflare Worker

Migrated from Vercel to Cloudflare Workers for better scalability.

## Quick Setup

### 1. Install Wrangler CLI
```bash
npm install -g wrangler
```

### 2. Login to Cloudflare
```bash
wrangler login
```

### 3. Deploy
```bash
cd cors-proxy-cloudflare
wrangler deploy
```

That's it! You'll get a URL like `https://scholardesk-cors-proxy.<your-subdomain>.workers.dev`

## Optional: Add KV for Persistent Cookies

### 1. Create a KV Namespace
```bash
wrangler kv:namespace create SESSION_COOKIES
```

### 2. Update wrangler.toml
```toml
[[kv_namespaces]]
binding = "SESSION_COOKIES"
id = "YOUR_KV_ID_FROM_PREVIOUS_COMMAND"
```

### 3. Redeploy
```bash
wrangler deploy
```

## Usage

Same as before:
```
GET https://your-worker.workers.dev/?url=https://example.com/api
```

## Compare: Vercel vs Cloudflare

| Feature | Vercel | Cloudflare |
|---------|--------|-----------|
| Free requests/day | Limited | 100,000 |
| Cold starts | Yes | No |
| Edge caching | Limited | Built-in |
| Persistent KV | $20/mo | Free (limited) |
| Bandwidth | 100GB/mo free | Unlimited |

## Switching Your App

Update your ScholarDesk app to point to the new Cloudflare URL instead of Vercel.