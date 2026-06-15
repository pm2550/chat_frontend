'use strict';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
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
