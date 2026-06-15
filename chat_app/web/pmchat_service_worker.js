'use strict';
// pmchat_service_worker.js — 安全版/自愈版 (源码, 取代之前的激进预缓存)
// 历史教训: 之前这里做 cacheFirst 预缓存 app shell, 缓存键不随构建版本变 -> 缓存的旧
//   main.dart.js 与网络拿的新 flutter_bootstrap.js 版本错位 -> Flutter boot 卡死(全网转圈)。
// 现状策略: SW 只做 Web Push, 不拦截 fetch(一律走网络); 静态大文件的缓存交给 nginx 的
//   immutable 响应头 + 浏览器自身 HTTP 缓存(已生效), 不再用 SW 预缓存(太脆、会版本错位)。
// activate 时清掉任何残留的 pmchat-shell-* 旧缓存 + 自动重载现有页面, 让历史坏版客户端零操作自愈。

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(names.map((name) => caches.delete(name))))
      .then(() => self.clients.claim())
      .then(() => self.clients.matchAll({ type: 'window', includeUncontrolled: true }))
      .then((clients) => {
        clients.forEach((client) => {
          if ('navigate' in client && client.url) {
            client.navigate(client.url).catch(() => {});
          }
        });
      })
  );
});

// 故意不注册 'fetch' 处理器 —— 所有请求直接走网络/浏览器默认缓存。

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
