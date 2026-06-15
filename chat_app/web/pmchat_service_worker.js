'use strict';

const CACHE_VERSION = new URL(self.location.href).searchParams.get('v') || 'dev';
const CACHE_PREFIX = 'pmchat-shell-';
const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;
const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/flutter.js',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/manifest.json',
  '/version.json',
  '/canvaskit/canvaskit.js',
  '/canvaskit/canvaskit.wasm',
  '/canvaskit/chromium/canvaskit.js',
  '/canvaskit/chromium/canvaskit.wasm',
  '/assets/AssetManifest.bin.json',
  '/assets/AssetManifest.bin',
  '/assets/FontManifest.json',
  '/assets/NOTICES',
  '/assets/fonts/MaterialIcons-Regular.otf',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/icons/Icon-maskable-192.png',
  '/icons/Icon-maskable-512.png',
];
const MUTABLE_PATHS = new Set([
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/manifest.json',
  '/version.json',
]);
const IMMUTABLE_EXTENSIONS = /\.(?:js|css|wasm|woff2?|png|jpg|jpeg|svg|ico|otf|ttf)$/i;

self.addEventListener('install', (event) => {
  event.waitUntil(precacheAppShell().then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys
        .filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
        .map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname.startsWith('/api/')) return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request, '/index.html'));
    return;
  }

  if (MUTABLE_PATHS.has(url.pathname)) {
    event.respondWith(networkFirst(request, url.pathname));
    return;
  }

  if (isImmutableAsset(url.pathname)) {
    event.respondWith(cacheFirst(request, url.pathname));
  }
});

self.addEventListener('push', (event) => {
  const payload = safePayload(event.data);
  const title = payload.title || 'PM chat';
  const data = Object.assign({}, payload.data || {}, {
    url: payload.url || (payload.data && payload.data.url) || '/#/home/chats',
  });
  const options = {
    body: payload.body || '你有一条新消息',
    icon: payload.icon || '/icons/Icon-192.png',
    badge: payload.badge || '/icons/Icon-192.png',
    tag: notificationTag(data),
    renotify: true,
    data: data,
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const targetUrl = new URL(data.url || '/#/home/chats', self.location.origin).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if (!client.url || new URL(client.url).origin !== self.location.origin) {
            continue;
          }
          if ('navigate' in client) {
            return client.navigate(targetUrl).then((navigated) => {
              return (navigated || client).focus();
            });
          }
          return client.focus();
        }
        if (self.clients.openWindow) {
          return self.clients.openWindow(targetUrl);
        }
        return undefined;
      })
  );
});

function safePayload(data) {
  if (!data) return {};
  try {
    return data.json();
  } catch (error) {
    return { body: data.text() };
  }
}

function notificationTag(data) {
  if (data && data.chatRoomId) {
    return 'pm-chat-room-' + data.chatRoomId;
  }
  return 'pm-chat-message';
}

function isImmutableAsset(pathname) {
  return pathname.startsWith('/assets/') ||
    pathname.startsWith('/canvaskit/') ||
    pathname.startsWith('/fonts/') ||
    pathname.startsWith('/icons/') ||
    pathname === '/flutter.js' ||
    pathname === '/main.dart.js' ||
    IMMUTABLE_EXTENSIONS.test(pathname);
}

function precacheAppShell() {
  return caches.open(CACHE_NAME).then((cache) => {
    return Promise.allSettled(PRECACHE_URLS.map((url) => {
      return cache.add(new Request(url, { cache: 'reload' }));
    }));
  });
}

function networkFirst(request, cacheKey) {
  return caches.open(CACHE_NAME).then((cache) => {
    return fetch(request)
      .then((response) => {
        if (response && response.ok) {
          cache.put(cacheKey, response.clone());
        }
        return response;
      })
      .catch(() => cache.match(cacheKey).then((cached) => {
        return cached || cache.match('/index.html');
      }));
  });
}

function cacheFirst(request, cacheKey) {
  return caches.open(CACHE_NAME).then((cache) => {
    return cache.match(cacheKey)
      .then((cached) => {
        if (cached) return cached;
        return cache.match(request).then((requestCached) => {
          if (requestCached) return requestCached;
          return fetch(request).then((response) => {
            if (response && response.ok) {
              cache.put(cacheKey, response.clone());
            }
            return response;
          });
        });
      });
  });
}
