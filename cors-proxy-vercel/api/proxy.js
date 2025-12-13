// In-memory cookie store (note: this resets on cold starts in serverless)
const cookieStore = new Map();

// Set CORS headers helper
function setCorsHeaders(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', '*');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Expose-Headers', '*');
  res.setHeader('Access-Control-Max-Age', '86400');
}

// Helper to get raw body as buffer
async function getRawBody(req) {
  // If body is already available (parsed by Vercel)
  if (req.body) {
    if (Buffer.isBuffer(req.body)) {
      return req.body;
    }
    if (typeof req.body === 'string') {
      return Buffer.from(req.body);
    }
    if (typeof req.body === 'object') {
      // It's already parsed as JSON or form data
      return null; // Signal to use parsed body
    }
  }
  
  // Read raw body from stream
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

module.exports = async (req, res) => {
  // Set CORS headers for ALL responses including errors
  setCorsHeaders(res);

  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const targetUrl = req.query.url;

  if (!targetUrl) {
    return res.status(400).json({ error: 'Missing url parameter' });
  }

  try {
    console.log(`Proxying ${req.method} request to: ${targetUrl}`);

    // Get session ID from header
    const sessionId = req.headers['x-session-id'] || 'default';

    // Get stored cookies for this session
    const storedCookies = cookieStore.get(sessionId) || '';

    const contentType = req.headers['content-type'] || '';
    const isMultipart = contentType.includes('multipart/form-data');
    const isFormUrlEncoded = contentType.includes('application/x-www-form-urlencoded');

    // Build headers for the target request
    const headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
      'Accept': req.headers['accept'] || 'application/json, text/javascript, */*; q=0.01',
      'Accept-Language': 'en-US,en;q=0.5',
    };

    // Add content-type for POST requests
    if (req.method === 'POST' && contentType) {
      headers['Content-Type'] = contentType;
    }

    // Add referer if provided
    if (req.headers['x-target-referer']) {
      headers['Referer'] = req.headers['x-target-referer'];
      try {
        headers['Origin'] = new URL(req.headers['x-target-referer']).origin;
      } catch (e) {}
    }

    // Add stored cookies
    if (storedCookies) {
      headers['Cookie'] = storedCookies;
      console.log('Sending cookies');
    }

    // Prepare body for POST requests
    let body;
    if (req.method === 'POST') {
      const rawBody = await getRawBody(req);
      
      if (rawBody === null) {
        // Body was parsed by Vercel as object, convert back to form data
        if (typeof req.body === 'object') {
          body = new URLSearchParams(req.body).toString();
          console.log(`Parsed form body: ${body}`);
        }
      } else if (rawBody.length > 0) {
        body = rawBody;
        console.log(`Raw body size: ${rawBody.length} bytes`);
      }
    }

    // Make the request to the target URL using native fetch
    const response = await fetch(targetUrl, {
      method: req.method,
      headers,
      body: req.method === 'POST' ? body : undefined,
      redirect: 'follow',
    });

    console.log(`Response status: ${response.status}`);

    // Extract and store cookies from response
    const setCookieHeader = response.headers.get('set-cookie');
    if (setCookieHeader) {
      const cookieMap = new Map();

      // Parse existing cookies
      if (storedCookies) {
        storedCookies.split('; ').forEach(cookie => {
          const [key, ...value] = cookie.split('=');
          if (key) cookieMap.set(key, value.join('='));
        });
      }

      // Parse set-cookie header
      const cookiePart = setCookieHeader.split(';')[0];
      const [key, ...value] = cookiePart.split('=');
      if (key) cookieMap.set(key, value.join('='));

      // Build final cookie string
      const finalCookies = Array.from(cookieMap.entries())
        .map(([k, v]) => `${k}=${v}`)
        .join('; ');

      cookieStore.set(sessionId, finalCookies);
      res.setHeader('X-Set-Cookies', finalCookies);
    }

    // Get response body
    const responseContentType = response.headers.get('content-type') || '';
    
    // Check if response is an image
    const isImage = responseContentType.startsWith('image/');
    
    if (isImage) {
      // For images, return binary data
      const buffer = await response.arrayBuffer();
      console.log(`Proxied image response (${buffer.byteLength} bytes)`);
      
      res.setHeader('Content-Type', responseContentType);
      return res.status(response.status).send(Buffer.from(buffer));
    } else {
      // For text/JSON/HTML, return as text
      const text = await response.text();
      console.log(`Proxied response (${text.length} bytes): ${text.substring(0, 200)}`);
      
      res.setHeader('Content-Type', responseContentType || 'text/plain');
      return res.status(response.status).send(text);
    }

  } catch (error) {
    console.error('Proxy error:', error.message, error.stack);
    return res.status(500).json({ error: error.message });
  }
};

// Disable body parsing to handle multipart correctly
module.exports.config = {
  api: {
    bodyParser: false,
  },
};
