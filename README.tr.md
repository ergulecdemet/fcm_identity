# fcm_identity

[English](README.md) | **Türkçe**

**Firebase Cloud Messaging** üzerine kurulu, OneSignal tarzı bildirim paketi. Kontrol tamamen **senin backend'inde**.

```dart
await FcmIdentity.instance.init(FcmIdentityConfig(
  firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  registrar: HttpRegistrar(
    registerUrl: Uri.parse('https://api.example.com/devices'),
  ),
));

await FcmIdentity.instance.login('12345');   // kullanıcı giriş yapınca
await FcmIdentity.instance.logout();         // kullanıcı çıkış yapınca
```

Firebase kullanıcıları değil, sadece cihazları tanır. `fcm_identity`, `OneSignal.login()` gibi *kullanıcı ↔ cihaz* eşleşmesini senin backend'inle senkronize tutar:

* FCM token'ını alır ve yeniler (iOS'ta APNs token'ını bekler),
* giriş yapıldığında, token yenilendiğinde ve property'ler değiştiğinde `{ token, userId, platform, locale, properties }` bilgisini API'ne gönderir; sadece bir şey değiştiğinde istek atar,
* başarısız olan gönderimleri uygulamanın bir sonraki açılışında tekrar dener,
* çıkışta cihaz kaydını siler ve token'ı geçersiz kılar,
* Android'de uygulama açıkken de bildirim gösterir,
* bildirime tıklanmasını bildirir, uygulamayı kapalıyken açan bildirim dahil.

Paket hiçbir gizli anahtar barındırmaz. Bildirimleri, kendi Firebase service account dosyasıyla senin backend'in gönderir.

| OneSignal | fcm_identity |
|---|---|
| `OneSignal.initialize(appId)` | `FcmIdentity.instance.init(config)` |
| `OneSignal.login(externalId)` | `FcmIdentity.instance.login(userId)` |
| `OneSignal.logout()` | `FcmIdentity.instance.logout()` |
| `OneSignal.User.addTags({...})` | `FcmIdentity.instance.setProperties({...})` |
| `OneSignal.Notifications.requestPermission()` | `FcmIdentity.instance.requestPermission()` |
| Sunucudaki REST API key | Sunucudaki Firebase service account JSON dosyası |

## Kurulum

```bash
flutter pub add fcm_identity
dart pub global activate flutterfire_cli
flutterfire configure
```

### Android

`flutter_local_notifications` paketi için core library desugaring gereklidir.

`android/app/build.gradle.kts` (Kotlin DSL, yeni Flutter projelerinde varsayılan):

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

`android/app/build.gradle` (Groovy, eski projeler):

```gradle
android {
    compileOptions {
        coreLibraryDesugaringEnabled true
    }
}
dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
```

`AndroidManifest.xml` içinde, `<application>` etiketinin altına:

```xml
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="fcm_identity_default" />
```

Değer, `FcmIdentityConfig.androidChannelId` ile aynı olmalıdır.

### iOS

1. Xcode'da **Push Notifications** ve **Background Modes → Remote notifications** yeteneklerini ekle.
2. Firebase Console → Proje ayarları → Cloud Messaging bölümüne APNs anahtarını (.p8) yükle.
3. Gerçek bir cihazda test et. Simülatörde bildirimler güvenilir çalışmaz.

## Kullanım

### Başlatma

```dart
await FcmIdentity.instance.init(FcmIdentityConfig(
  firebaseOptions: DefaultFirebaseOptions.currentPlatform,
  registrar: HttpRegistrar(
    registerUrl: Uri.parse('https://api.example.com/devices'),
    // Her istekten önce çağrılır, böylece süresi dolmuş token gönderilmez.
    headers: () async => {'Authorization': 'Bearer ${await auth.idToken()}'},
  ),
  onMessageOpened: (m) => router.push(m.route ?? '/'),
));
```

`init` hızlıca tamamlanır. Token alma ve senkronizasyon arka planda yapılır.

### İzin

```dart
final granted = await FcmIdentity.instance.requestPermission();
```

İzni ilk açılışta değil, kullanıcıya nedenini anlattıktan sonra iste. İzni `init` sırasında istemek için `requestPermissionOnInit: true` ayarını kullan.

### Kullanıcılar ve property'ler

```dart
await FcmIdentity.instance.login('12345', properties: {'plan': 'pro'});
await FcmIdentity.instance.setProperty('city', 'gaziantep');
await FcmIdentity.instance.setProperty('city', null); // siler
await FcmIdentity.instance.logout();
```

Kullanıcı ID'si ve property'ler cihazda saklanır. Her açılışta `login` çağırmana gerek yoktur.

Property'lere kişisel veri (ad, e-posta, telefon numarası gibi) koymaktan kaçın. Backend kullanıcıyı `userId` ile zaten tanır, ayrıca property'ler cihazda şifrelenmeden saklanır.

### Bildirimden ekran açma

Backend'den `data: { route: '/orders/7' }` gönder.

```dart
// Uygulama açıkken ya da arka plandayken
FcmIdentity.instance.onMessageOpened.listen((m) => router.push(m.route!));

// Uygulama kapalıyken açıldıysa: router hazır olduktan sonra bir kez çağır
final initial = FcmIdentity.instance.takeInitialMessage();
if (initial?.route != null) router.go(initial!.route!);
```

### Uygulama açıkken gelen mesajlar

```dart
FcmIdentity.instance.onMessage.listen((m) => showSnackBar(m.title));
```

### Topic'ler (isteğe bağlı)

```dart
await FcmIdentity.instance.subscribe('news'); // "<topicPrefix>news"
```

Birden fazla uygulama aynı Firebase projesini paylaşıyorsa `topicPrefix` kullan.

### Farklı backend formatları

```dart
HttpRegistrar(
  registerUrl: Uri.parse('https://api.example.com/push-token'),
  unregisterUrl: Uri.parse('https://api.example.com/push-token/remove'),
  bodyBuilder: (r) => {'pushToken': r.token, 'device': r.platform},
)
```

Ya da istediğin istemciyi kullan:

```dart
CallbackRegistrar(
  onRegister: (r) async {
    await supabase.from('devices').upsert(r.toJson());
  },
  onUnregister: (r) async {
    await supabase.from('devices').delete().eq('token', r.token);
  },
)
```

## Backend sözleşmesi

Varsayılan `HttpRegistrar` ile:

| Olay | İstek | Gövde |
|---|---|---|
| Giriş, token yenilenmesi, property değişikliği | `POST registerUrl` | `{ token, userId, platform, appId?, locale?, properties? }` |
| Çıkış | `DELETE registerUrl` (ya da `POST unregisterUrl`) | Aynı |

2xx dışındaki her yanıt başarısız sayılır ve uygulamanın bir sonraki açılışında tekrar denenir.

Backend kayıtları **token'a göre eklemeli ya da güncellemelidir (upsert)**. Bir token tek bir cihaza aittir; yeni bir `userId` ile gelirse, cihaz yeni kullanıcıya devredilmiştir. Kullanıcı ID'si her zaman doğrulanmış oturumdan alınmalı, sadece istek gövdesine güvenilmemelidir.

Kullanıcıya bildirim gönderme ve geçersiz token'ları temizleme dahil eksiksiz bir Node.js örneği için [doc/backend.md](doc/backend.md) dosyasına bak (İngilizce).

## Lisans

MIT
