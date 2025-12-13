# ScholarDesk CORS Proxy for Vercel

This is a serverless CORS proxy designed to be deployed on Vercel. It helps bypass CORS restrictions when accessing the ScholarDesk API from web browsers.

## Deployment Steps

### 1. Install Vercel CLI
```bash
npm install -g vercel
```

### 2. Login to Vercel
```bash
vercel login
```

### 3. Deploy
```bash
cd cors-proxy-vercel
vercel
```

Follow the prompts:
- Set up and deploy? **Yes**
- Which scope? **Select your account**
- Link to existing project? **No** (first time) or **Yes** (update)
- What's your project's name? **scholardesk-cors-proxy** (or your choice)
- In which directory is your code located? **./** (press Enter)
- Override settings? **No**

### 4. Production Deployment
```bash
vercel --prod
```

## After Deployment

1. Copy the production URL (e.g., `https://scholardesk-cors-proxy.vercel.app`)

2. Update the Flutter app's API config in `/lib/services/api_config.dart`:
```dart
static const String corsProxyUrl = 'https://YOUR-VERCEL-URL.vercel.app/proxy';
```

## Usage

The proxy accepts requests with a `url` query parameter:

```
GET /proxy?url=https://example.com/api/endpoint
POST /proxy?url=https://example.com/api/endpoint
```

### Headers

- `X-Session-Id`: Session identifier for cookie storage
- `X-Target-Referer`: Referer header to send to target server

## Notes

- The in-memory cookie store resets on serverless cold starts
- For production with persistent sessions, consider using Vercel KV or similar
