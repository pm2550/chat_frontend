'use strict';

// Replaced in the built release by tool/generate_web_release_manifest.dart.
const BUILD_ID = '__PMCHAT_BUILD_ID__';
const SHELL_CACHE = `pmchat-shell-${BUILD_ID}`;
const RUNTIME_CACHE = `pmchat-runtime-${BUILD_ID}`;
const BUILD_MANIFEST = '/pmchat_build_manifest.json';
const SHELL_PREFIX = 'pmchat-shell-';
const RUNTIME_PREFIX = 'pmchat-runtime-';

self.addEventListener('install', (event) => {
  event.waitUntil(installCompleteRelease());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    retainCurrentAndPreviousRelease()
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin ||
      url.pathname.startsWith('/api/') ||
      url.pathname.startsWith('/actuator/')) {
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(cacheFirstNavigation(request));
    return;
  }
  if (isMutableMetadata(url.pathname)) {
    event.respondWith(networkFirst(request));
    return;
  }
  if (isCacheableAsset(url.pathname)) {
    event.respondWith(cacheFirstAsset(request));
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
        return self.clients.openWindow
          ? self.clients.openWindow(targetUrl)
          : undefined;
      })
  );
});

async function installCompleteRelease() {
  const response = await fetch(`${BUILD_MANIFEST}?build=${encodeURIComponent(BUILD_ID)}`, {
    cache: 'no-store',
  });
  if (!response.ok) throw new Error('PM chat build manifest unavailable');
  const manifest = await response.json();
  if (!manifest || manifest.buildId !== BUILD_ID || !Array.isArray(manifest.requiredAssets)) {
    throw new Error('PM chat build manifest does not match this worker');
  }

  const cache = await caches.open(SHELL_CACHE);
  const assets = assetsForThisBrowser(manifest);
  for (const asset of assets) {
    const assetResponse = await fetch(asset.url, { cache: 'reload' });
    if (!assetResponse.ok) {
      throw new Error(`Required PM chat asset failed: ${asset.url}`);
    }
    await cache.put(asset.url, assetResponse);
  }
  await cache.put(BUILD_MANIFEST, new Response(JSON.stringify(manifest), {
    headers: { 'Content-Type': 'application/json' },
  }));
  await self.skipWaiting();
}

function assetsForThisBrowser(manifest) {
  const groups = manifest.assetGroups;
  if (!groups || !Array.isArray(groups.common)) {
    return manifest.requiredAssets;
  }
  const variant = supportsWasmGc() && Array.isArray(groups.wasm)
    ? groups.wasm
    : groups.js;
  return groups.common.concat(Array.isArray(variant) ? variant : []);
}

function supportsWasmGc() {
  try {
    return WebAssembly.validate(new Uint8Array([
      0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 95, 1, 120, 0
    ]));
  } catch (_) {
    return false;
  }
}

async function cacheFirstNavigation(request) {
  const cache = await caches.open(SHELL_CACHE);
  const cached = await cache.match('/index.html');
  if (cached) return cached;
  try {
    return await fetch(request);
  } catch (_) {
    return Response.error();
  }
}

async function networkFirst(request) {
  try {
    const response = await fetch(request, { cache: 'no-store' });
    if (response.ok && request.url.indexOf('pmchat_service_worker.js') === -1) {
      const cache = await caches.open(RUNTIME_CACHE);
      await cache.put(request, response.clone());
    }
    return response;
  } catch (_) {
    const runtime = await caches.open(RUNTIME_CACHE);
    const cached = await runtime.match(request, { ignoreSearch: true });
    if (cached) return cached;
    const shell = await caches.open(SHELL_CACHE);
    return (await shell.match(new URL(request.url).pathname)) || Response.error();
  }
}

async function cacheFirstAsset(request) {
  const shell = await caches.open(SHELL_CACHE);
  const path = new URL(request.url).pathname;
  const cached = await shell.match(path);
  if (cached) return cached;

  const runtime = await caches.open(RUNTIME_CACHE);
  const runtimeCached = await runtime.match(request, { ignoreSearch: true });
  if (runtimeCached) return runtimeCached;
  const response = await fetch(request);
  if (response.ok) await runtime.put(path, response.clone());
  return response;
}

async function retainCurrentAndPreviousRelease() {
  const keys = await caches.keys();
  const shellKeys = keys.filter((key) => key.startsWith(SHELL_PREFIX));
  const previousShell = shellKeys
    .filter((key) => key !== SHELL_CACHE)
    .slice(-1)[0];
  const keep = new Set([
    SHELL_CACHE,
    RUNTIME_CACHE,
    previousShell,
    previousShell ? previousShell.replace(SHELL_PREFIX, RUNTIME_PREFIX) : null,
  ].filter(Boolean));

  await Promise.all(keys
    .filter((key) =>
      (key.startsWith(SHELL_PREFIX) || key.startsWith(RUNTIME_PREFIX) ||
       key.startsWith('flutter-app-cache') || key.startsWith('flutter-temp-cache') ||
       key.startsWith('flutter-app-manifest')) && !keep.has(key))
    .map((key) => caches.delete(key)));
}

function isMutableMetadata(pathname) {
  return pathname === BUILD_MANIFEST ||
    pathname === '/version.json' ||
    pathname === '/manifest.json' ||
    pathname === '/.last_build_id' ||
    pathname === '/pmchat_service_worker.js';
}

function isCacheableAsset(pathname) {
  return pathname === '/main.dart.js' ||
    pathname === '/main.dart.mjs' ||
    pathname === '/main.dart.wasm' ||
    pathname === '/flutter.js' ||
    pathname === '/flutter_bootstrap.js' ||
    pathname === '/favicon.png' ||
    pathname.startsWith('/canvaskit/') ||
    pathname.startsWith('/assets/') ||
    pathname.startsWith('/fonts/') ||
    pathname.startsWith('/icons/');
}

function safePayload(data) {
  if (!data) return {};
  try {
    return data.json();
  } catch (_) {
    return { body: data.text() };
  }
}

function notificationTag(data) {
  return data && data.chatRoomId
    ? `pm-chat-room-${data.chatRoomId}`
    : 'pm-chat-message';
}
