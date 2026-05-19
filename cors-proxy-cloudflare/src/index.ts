/**
 * Cloudflare Worker CORS Proxy - ScholarDesk
 * TypeScript version
 */

export interface Env {
  SESSION_COOKIES: KVNamespace;
}

interface CookieMap {
  [key: string]: string;
}

// In-memory cookie store (same as Vercel version)
const cookieStore = new Map<string, string>();

function setCorsHeaders(): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Credentials': 'true',
    'Access-Control-Expose-Headers': '*',
    'Access-Control-Max-Age': '86400',
  };
}

function getStoredCookies(sessionId: string, env: Env | undefined): string {
  if (!env?.SESSION_COOKIES) {
    return cookieStore.get(sessionId) || '';
  }
  // KV is async, handled at call site
  return '';
}

async function getStoredCookiesFromKV(sessionId: string, env: Env): Promise<string> {
  if (env.SESSION_COOKIES) {
    return (await env.SESSION_COOKIES.get(sessionId)) || '';
  }
  return cookieStore.get(sessionId) || '';
}

function storeCookies(sessionId: string, cookies: string, env: Env | undefined): void {
  if (!env) {
    cookieStore.set(sessionId, cookies);
  }
  // KV store is async, handled at call site
}

async function storeCookiesToKV(sessionId: string, cookies: string, env: Env): Promise<void> {
  if (env.SESSION_COOKIES) {
    await env.SESSION_COOKIES.put(sessionId, cookies);
  } else {
    cookieStore.set(sessionId, cookies);
  }
}

function parseCookies(cookieString: string): CookieMap {
  const map: CookieMap = {};
  if (!cookieString) return map;

  cookieString.split('; ').forEach(cookie => {
    const [key, ...value] = cookie.split('=');
    if (key) {
      map[key.trim()] = value.join('=').trim();
    }
  });

  return map;
}

function mergeCookies(existing: string, newCookie: string): string {
  const map = parseCookies(existing);

  const cookiePart = newCookie.split(';')[0];
  const [key, ...value] = cookiePart.split('=');
  if (key) {
    map[key.trim()] = value.join('=').trim();
  }

  return Object.entries(map)
    .map(([k, v]) => `${k}=${v}`)
    .join('; ');
}

async function handlePreflight(): Promise<Response> {
  return new Response(null, {
    status: 200,
    headers: setCorsHeaders(),
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return handlePreflight();
    }

    // Get target URL from query parameter (same as Vercel)
    const targetUrl = url.searchParams.get('url');

    if (!targetUrl) {
      return new Response(JSON.stringify({ error: 'Missing url parameter' }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          ...setCorsHeaders(),
        },
      });
    }

    try {
      // Get session ID from header (same as Vercel)
      const sessionId = request.headers.get('x-session-id') || 'default';

      // Get stored cookies for this session
      let storedCookies = '';
      if (env.SESSION_COOKIES) {
        storedCookies = await env.SESSION_COOKIES.get(sessionId) || '';
      } else {
        storedCookies = cookieStore.get(sessionId) || '';
      }

      // Get content-type from request
      const contentType = request.headers.get('content-type') || '';

      // Build headers for target request (matches Vercel)
      const headers: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
        'Accept': request.headers.get('accept') || 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'en-US,en;q=0.5',
      };

      // Add content-type for POST requests
      if (request.method === 'POST' && contentType) {
        headers['Content-Type'] = contentType;
      }

      // Add referer if provided (same as Vercel)
      const targetReferer = request.headers.get('x-target-referer');
      if (targetReferer) {
        headers['Referer'] = targetReferer;
        try {
          headers['Origin'] = new URL(targetReferer).origin;
        } catch (_) {
          // Invalid URL, skip Origin
        }
      }

      // Add stored cookies (same as Vercel)
      if (storedCookies) {
        headers['Cookie'] = storedCookies;
      }

      // Prepare body for POST requests (same as Vercel)
      let body: BodyInit | undefined;
      if (request.method === 'POST') {
        const arrayBuffer = await request.arrayBuffer();
        if (arrayBuffer.byteLength > 0) {
          body = arrayBuffer;
        }
      }

      // Make request to target URL
      const response = await fetch(targetUrl, {
        method: request.method,
        headers,
        body,
        redirect: 'follow',
      });

      // Extract and store cookies from response (same as Vercel)
      const setCookieHeader = response.headers.get('set-cookie');
      let finalCookies = storedCookies;

      if (setCookieHeader) {
        finalCookies = mergeCookies(storedCookies, setCookieHeader);

        // Store cookies
        if (env.SESSION_COOKIES) {
          await env.SESSION_COOKIES.put(sessionId, finalCookies);
        } else {
          cookieStore.set(sessionId, finalCookies);
        }
      }

      // Get response content type
      const responseContentType = response.headers.get('content-type') || '';

      // Check if response is an image (same as Vercel)
      const isImage = responseContentType.startsWith('image/');

      if (isImage) {
        const buffer = await response.arrayBuffer();
        const corsHeaders = setCorsHeaders();
        corsHeaders['Content-Type'] = responseContentType;

        return new Response(buffer, {
          status: response.status,
          headers: corsHeaders,
        });
      }

      // For text/JSON/HTML, return as text
      const text = await response.text();
      const corsHeaders = setCorsHeaders();
      corsHeaders['Content-Type'] = responseContentType || 'text/plain';

      // Add X-Set-Cookies header (same as Vercel)
      if (finalCookies && finalCookies !== storedCookies) {
        corsHeaders['X-Set-Cookies'] = finalCookies;
      }

      return new Response(text, {
        status: response.status,
        headers: corsHeaders,
      });

    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      console.error('Proxy error:', message);

      return new Response(JSON.stringify({ error: message }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          ...setCorsHeaders(),
        },
      });
    }
  },
};