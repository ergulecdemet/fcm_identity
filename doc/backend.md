# Backend guide

`fcm_identity` only *registers* devices. Your backend stores them and sends notifications with the Firebase Admin SDK.

## 1. Credentials

Firebase Console → Project settings → **Service accounts** → **Generate new private key**.
Keep the JSON secret (environment variable or secret manager). Never ship it in an app.

The legacy FCM server key no longer works. Use the Admin SDK, which calls the HTTP v1 API.

## 2. Storage

One row per device:

| column | note |
|---|---|
| `token` | primary key |
| `user_id` | nullable |
| `platform`, `app_id`, `locale` | for targeting |
| `properties` | JSON |
| `updated_at` | to prune stale tokens |

## 3. Node.js / Express example

```js
const express = require('express');
const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SA)),
});

const app = express();
app.use(express.json());

// Replace with your database.
const devices = new Map(); // token -> record

app.post('/devices', auth, (req, res) => {
  const { token, userId, platform, appId, locale, properties } = req.body;
  if (!token) return res.status(400).end();
  // Never trust userId from the body alone; take it from the session.
  if (userId && userId !== req.user.id) return res.status(403).end();
  devices.set(token, { token, userId, platform, appId, locale, properties, updatedAt: Date.now() });
  res.status(204).end();
});

app.delete('/devices', auth, (req, res) => {
  devices.delete(req.body.token);
  res.status(204).end();
});

async function sendToUser(userId, { title, body, data = {} }) {
  const tokens = [...devices.values()].filter(d => d.userId === userId).map(d => d.token);
  if (tokens.length === 0) return;

  const result = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data, // values must be strings
    android: { notification: { channelId: 'fcm_identity_default' } },
  });

  // Remove tokens of uninstalled apps.
  result.responses.forEach((r, i) => {
    const code = r.error?.code;
    if (code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token') {
      devices.delete(tokens[i]);
    }
  });
}

// Example
// await sendToUser('12345', { title: 'Order shipped', body: 'Tap to track', data: { route: '/orders/7' } });
```

`sendEachForMulticast` accepts up to 500 tokens per call.

## 4. Broadcasts

Either send to a topic (`admin.messaging().send({ topic: 'news', ... })`) or query your device table by `properties`, `locale`, `platform` and send in batches of 500.

Topics can also be managed server-side:

```js
await admin.messaging().subscribeToTopic(tokens, 'news');
```

## 5. Security checklist

* Authenticate `/devices` and take the user id from the session, not the body.
* Rate-limit the endpoint.
* Prune tokens not updated for ~60 days.
