const pushDatabaseName = "ente-space-web-push";
const pushDatabaseVersion = 1;
const pushTargetStoreName = "targets";

self.addEventListener("push", (event) => {
    let payload = {};
    try {
        payload = event.data ? event.data.json() : {};
    } catch {
        payload = {};
    }

    event.waitUntil(
        notificationURL(payload).then((url) =>
            self.registration.showNotification(notificationTitle(payload), {
                actions: notificationActions(payload),
                body: notificationBody(payload),
                data: { url },
                icon: "/images/pwa-icon-192.png",
            }),
        ),
    );
});

self.addEventListener("notificationclick", (event) => {
    event.notification.close();
    event.waitUntil(
        notificationURL(event.notification.data).then(async (url) => {
            const destination = new URL(url, self.location.origin).href;
            const windows = await self.clients.matchAll({
                includeUncontrolled: true,
                type: "window",
            });
            const client = windows.find(
                (candidate) =>
                    new URL(candidate.url).origin == self.location.origin,
            );
            if (client) {
                await client.navigate(destination);
                return client.focus();
            }
            return self.clients.openWindow(destination);
        }),
    );
});

const notificationTitle = (payload) =>
    typeof payload?.title == "string" && payload.title.trim()
        ? payload.title.trim()
        : "Ente Space";

const notificationBody = (payload) =>
    typeof payload?.body == "string" ? payload.body.trim() : "";

const notificationActions = (payload) =>
    typeof payload?.action == "string" && payload.action.trim()
        ? [{ action: "open", title: payload.action.trim() }]
        : [];

const notificationURL = async (payload) => {
    if (typeof payload?.targetId == "string" && payload.targetId) {
        const route = await routeForTarget(payload.targetId);
        if (route) return safeRoute(route);
    }
    return safeRoute(payload?.url);
};

const safeRoute = (value) => {
    if (typeof value != "string") return "/app";
    try {
        const url = new URL(value, self.location.origin);
        if (url.origin != self.location.origin) return "/app";
        return `${url.pathname}${url.search}${url.hash}`;
    } catch {
        return "/app";
    }
};

const routeForTarget = async (targetId) => {
    try {
        const database = await openPushDatabase();
        return await new Promise((resolve, reject) => {
            const transaction = database.transaction(
                pushTargetStoreName,
                "readonly",
            );
            const request = transaction
                .objectStore(pushTargetStoreName)
                .index("targetId")
                .get(targetId);
            request.onerror = () => reject(request.error);
            request.onsuccess = () => resolve(request.result?.route);
        });
    } catch {
        return undefined;
    }
};

const openPushDatabase = () =>
    new Promise((resolve, reject) => {
        const request = indexedDB.open(pushDatabaseName, pushDatabaseVersion);
        request.onupgradeneeded = () => {
            const database = request.result;
            if (!database.objectStoreNames.contains(pushTargetStoreName)) {
                const store = database.createObjectStore(pushTargetStoreName, {
                    keyPath: "key",
                });
                store.createIndex("targetId", "targetId");
            }
        };
        request.onerror = () => reject(request.error);
        request.onsuccess = () => resolve(request.result);
    });
