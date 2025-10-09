import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String supabaseUrl = 'https://azccbwduobbulgdgucjj.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF6Y2Nid2R1b2JidWxnZGd1Y2pqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk4MDUyNzgsImV4cCI6MjA3NTM4MTI3OH0.x9jEzJnHg_fiX0dFXpWD70kKH848QZC4uELlMpL1yos';
const String postBucketName = 'post-images';
const String avatarsBucketName = 'avatars';

late final SupabaseClient supabase;

final FlutterLocalNotificationsPlugin fln = FlutterLocalNotificationsPlugin();
const AndroidNotificationChannel fcmChannel = AndroidNotificationChannel(
  'default_channel',
  'General',
  description: 'Main channel',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> _showLocal(RemoteMessage m) async {
  final n = m.notification;
  if (n == null) return;
  const android = AndroidNotificationDetails(
    'default_channel',
    'General',
    importance: Importance.high,
    priority: Priority.high,
  );
  const notif = NotificationDetails(android: android);
  await fln.show(n.hashCode, n.title ?? '', n.body ?? '', notif, payload: m.data.isNotEmpty ? m.data.toString() : null);
}

Future<void> initPush(String userId) async {
  final fm = FirebaseMessaging.instance;
  await fm.requestPermission();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await fln.initialize(const InitializationSettings(android: androidInit));
  final androidFln = fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidFln?.createNotificationChannel(fcmChannel);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  final token = await fm.getToken();
  if (token != null) {
    await supabase.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'last_seen_at': DateTime.now().toIso8601String(),
    }, onConflict: 'token');
  }
  FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
    await supabase.from('device_tokens').upsert({
      'user_id': userId,
      'token': t,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'last_seen_at': DateTime.now().toIso8601String(),
    }, onConflict: 'token');
  });
  FirebaseMessaging.onMessage.listen(_showLocal);
  FirebaseMessaging.onMessageOpenedApp.listen((msg) {});
}

class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('theme_mode');
    if (v == 'light') _mode = ThemeMode.light;
    if (v == 'dark') _mode = ThemeMode.dark;
    notifyListeners();
  }
  Future<void> toggle() async {
    _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', _mode == ThemeMode.light ? 'light' : 'dark');
  }
}

class SimpleAuth {
  static const _prefsKey = 'current_user_id';
  static Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }
  static Future<void> setCurrentUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, userId);
  }
  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
  static Future<String?> signIn(String login, String password) async {
    final row = await supabase
        .from('users')
        .select('id')
        .eq('login', login.trim().toLowerCase())
        .eq('password', password.trim().toLowerCase())
        .maybeSingle();
    return row?['id'];
  }
}

class UserModel {
  final String id;
  final String login;
  final String fullName;
  final String? avatarUrl;
  UserModel({required this.id, required this.login, required this.fullName, this.avatarUrl});
}

class PostModel {
  final String id;
  final String authorId;
  final String authorLogin;
  final String authorName;
  final String? authorAvatarUrl;
  final DateTime createdAt;
  final String text;
  final List<String> imageUrls;
  PostModel({
    required this.id,
    required this.authorId,
    required this.authorLogin,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.createdAt,
    required this.text,
    required this.imageUrls,
  });
}

String _clean(String s) => s.replaceAll(RegExp(r'^/+'), '');
String publicUrl({required String bucket, required String objectKey}) {
  final key = _clean(objectKey);
  return Supabase.instance.client.storage.from(bucket).getPublicUrl(key);
}

class PostsRepository {
  final SupabaseClient supa;
  PostsRepository(this.supa);
  static const Map<String, List<String>> _legacyCaptionToNames = {
    'Красота то какая! Ляпота!🌅 -  © Казенов Эдуард': ['photo3.jpg'],
    'Поход в лес! 🌳🏔️🌲': ['photo1.jpg', 'photo2.jpg'],
    'Мой отдых 🌊🌊🌊': ['photo4.jpg', 'photo5.jpg', 'photo21.jpg'],
    'Красиво, однако!': ['photo6.jpg', 'photo7.jpg', 'photo8.jpg', 'photo9.jpg', 'photo24.jpg', 'photo25.jpg'],
  };
  List<String> _publicUrlsOrAssets(List<String> names) {
    return names.map((n) {
      final key = _clean(n);
      return publicUrl(bucket: postBucketName, objectKey: key);
    }).toList();
  }
  String _postImagePublicUrlFromStoragePath(String storagePath) {
    final clean = _clean(storagePath);
    final fixed = clean.startsWith('post-images/') ? clean.substring('post-images/'.length) : clean;
    return publicUrl(bucket: postBucketName, objectKey: fixed);
  }
  String? _authorAvatarPublicUrl(String? avatarUrlFromDb, String authorLogin) {
    if (avatarUrlFromDb != null && avatarUrlFromDb.startsWith('http')) return avatarUrlFromDb;
    if (avatarUrlFromDb != null && avatarUrlFromDb.isNotEmpty) return publicUrl(bucket: avatarsBucketName, objectKey: avatarUrlFromDb);
    return publicUrl(bucket: avatarsBucketName, objectKey: '$authorLogin.jpg');
  }
  Future<List<PostModel>> loadPosts() async {
    final posts = await supa.from('posts').select('id,user_id,created_at,text').order('created_at', ascending: false);
    final result = <PostModel>[];
    for (final p in posts) {
      final postId = p['id'] as String;
      final userId = p['user_id'] as String;
      final createdAt = DateTime.parse(p['created_at'] as String);
      final text = (p['text'] ?? '') as String;
      final author = await supa.from('users').select('login, full_name, avatar_url').eq('id', userId).single();
      final authorLogin = (author['login'] ?? '') as String;
      final authorName = (author['full_name'] ?? '') as String;
      final authorAvatarDb = author['avatar_url'] as String?;
      final authorAvatarUrl = _authorAvatarPublicUrl(authorAvatarDb, authorLogin);
      final imgs = await supa.from('post_images').select('storage_path, sort_order').eq('post_id', postId).order('sort_order');
      List<String> photoUrls = [];
      if (imgs.isNotEmpty) {
        for (final row in imgs) {
          final sp = row['storage_path'] as String;
          final url = _postImagePublicUrlFromStoragePath(sp);
          photoUrls.add(url);
        }
      } else {
        final legacy = _legacyCaptionToNames[text];
        if (legacy != null) {
          photoUrls = _publicUrlsOrAssets(legacy);
        }
      }
      result.add(PostModel(
        id: postId,
        authorId: userId,
        authorLogin: authorLogin,
        authorName: authorName,
        authorAvatarUrl: authorAvatarUrl,
        createdAt: createdAt,
        text: text,
        imageUrls: photoUrls,
      ));
    }
    return result;
  }
}

Future<void> registerFcmTokenIfAvailable(String userId) async {
  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;
  await supabase.from('device_tokens').upsert({
    'user_id': userId,
    'token': token,
    'platform': Platform.isIOS ? 'ios' : 'android',
    'last_seen_at': DateTime.now().toIso8601String(),
  }, onConflict: 'token');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  supabase = Supabase.instance.client;
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  final ThemeController? themeController;
  final String? initialUserId;
  const MyApp({super.key, this.themeController, this.initialUserId});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ThemeController _theme;
  String? _userId;
  bool _themeReady = false;

  @override
  void initState() {
    super.initState();
    _theme = widget.themeController ?? ThemeController();
    _userId = widget.initialUserId;
    _theme.load().whenComplete(() {
      if (mounted) setState(() => _themeReady = true);
    });
    _ensureInitialUser();
  }

  Future<void> _ensureInitialUser() async {
    if (_userId == null) {
      _userId = await SimpleAuth.getCurrentUserId();
      if (_userId != null) {
        await initPush(_userId!);
      }
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_themeReady) {
      return MaterialApp(debugShowCheckedModeBanner: false, home: Container(color: Colors.white));
    }
    return AnimatedBuilder(
      animation: _theme,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: _theme.mode,
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF5EEDC),
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
          snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        ),
        home: _userId == null
            ? LoginScreen(onSignedIn: (u) async {
                await SimpleAuth.setCurrentUserId(u);
                await initPush(u);
                setState(() => _userId = u);
              })
            : HomeScreen(
                currentUserId: _userId!,
                onSignOut: () async {
                  await SimpleAuth.signOut();
                  setState(() => _userId = null);
                },
                themeController: _theme,
              ),
        routes: {'/photo': (_) => const PhotoViewScreen()},
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final ValueChanged<String> onSignedIn;
  const LoginScreen({super.key, required this.onSignedIn});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final loginCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> _doLogin() async {
    setState(() { loading = true; error = null; });
    try {
      final userId = await SimpleAuth.signIn(loginCtrl.text, passCtrl.text);
      if (userId != null) {
        await registerFcmTokenIfAvailable(userId);
        widget.onSignedIn(userId);
      } else {
        setState(() => error = 'Неверный логин или пароль');
      }
    } catch (e) {
      setState(() => error = 'Ошибка входа: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Вход', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(controller: loginCtrl, decoration: const InputDecoration(labelText: 'Логин (фамилия+инициалы)')),
              const SizedBox(height: 8),
              TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Пароль'), obscureText: true),
              const SizedBox(height: 16),
              if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: loading ? null : _doLogin,
                child: loading ? const CircularProgressIndicator() : const Text('Войти'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String currentUserId;
  final VoidCallback onSignOut;
  final ThemeController themeController;
  const HomeScreen({super.key, required this.currentUserId, required this.onSignOut, required this.themeController});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  late final PostsRepository repo;
  List<PostModel> posts = [];
  bool loading = true;

  UserModel? me;

  @override
  void initState() {
    super.initState();
    repo = PostsRepository(supabase);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    try {
      final u = await supabase
          .from('users')
          .select('id, login, full_name, avatar_url')
          .eq('id', widget.currentUserId)
          .single();
      me = UserModel(
        id: u['id'] as String,
        login: (u['login'] ?? '') as String,
        fullName: (u['full_name'] ?? '') as String,
        avatarUrl: u['avatar_url'] as String?,
      );

      posts = await repo.loadPosts();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 60) return '${d.inMinutes} минут назад';
    if (d.inHours < 24) return '${d.inHours} часов назад';
    return '${d.inDays} дн. назад';
  }

  String _greeting(UserModel? u) {
    if (u == null || u.fullName.trim().isEmpty) return 'Здравствуйте!';
    final h = DateTime.now().hour;
    final g = (h>=4 && h<12) ? 'Доброе утро' : (h<17) ? 'Добрый день' : (h<22) ? 'Добрый вечер' : 'Доброй ночи';
    return '$g, ${u.fullName}!';
  }

  void _goHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _stub(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final list = loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              Row(children: const [
                Expanded(child: InfoCard(icon: Icons.notifications, iconColor: Colors.yellow, title: '10 новостей')),
                Expanded(child: InfoCard(icon: Icons.event, iconColor: Colors.green, title: '15 событий')),
              ]),
              const SizedBox(height: 16),
              for (final p in posts) ...[
                PostCard.buildFromData(
                  context: context,
                  profileAsset: p.authorAvatarUrl ?? 'assets/profile0.jpg',
                  name: p.authorName,
                  time: _timeAgo(p.createdAt),
                  caption: p.text,
                  photos: p.imageUrls,
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 80),
            ],
          );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              greeting: _greeting(me),
              currentUserLogin: me?.login,
              currentUserAvatarUrl: me?.avatarUrl,
              onToggleTheme: widget.themeController.toggle,
              onSignOut: widget.onSignOut,
            ),
            const SizedBox(height: 12),
            Expanded(child: list),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.home), onPressed: () => _goHome(context)),
              IconButton(icon: const Icon(Icons.search), onPressed: () => _stub(context, 'Поиск (заглушка)')),
              IconButton(icon: const Icon(Icons.person), onPressed: () => _stub(context, 'Профиль (заглушка)')),
            ]),
          ]),
        ),
      ),
    );
  }
}

class AppHeader extends StatelessWidget {
  final String greeting;
  final String? currentUserLogin;
  final String? currentUserAvatarUrl;
  final VoidCallback onToggleTheme;
  final VoidCallback onSignOut;

  const AppHeader({
    super.key,
    required this.greeting,
    required this.currentUserLogin,
    required this.currentUserAvatarUrl,
    required this.onToggleTheme,
    required this.onSignOut,
  });

  bool _isHttp(String? s) => s != null && (s.startsWith('http://') || s.startsWith('https://'));

  Future<ImageProvider> _resolveAvatar() async {
    if (_isHttp(currentUserAvatarUrl)) {
      return NetworkImage(currentUserAvatarUrl!);
    }
    if (currentUserAvatarUrl != null && currentUserAvatarUrl!.isNotEmpty) {
      final url = publicUrl(bucket: avatarsBucketName, objectKey: currentUserAvatarUrl!);
      return NetworkImage(url);
    }
    if ((currentUserLogin ?? '').isNotEmpty) {
      final url = publicUrl(bucket: avatarsBucketName, objectKey: '${currentUserLogin!}.jpg');
      return NetworkImage(url);
    }
    return const AssetImage('assets/profile0.jpg');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ImageProvider>(
      future: _resolveAvatar(),
      builder: (context, snap) {
        final avatar = snap.data ?? const AssetImage('assets/profile0.jpg');
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Text(
                greeting,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Row(children: [
              IconButton(tooltip: 'Тема', onPressed: onToggleTheme, icon: const Icon(Icons.brightness_6)),
              IconButton(tooltip: 'Выход', onPressed: onSignOut, icon: const Icon(Icons.logout)),
              CircleAvatar(radius: 28, backgroundImage: avatar),
            ]),
          ]),
        );
      },
    );
  }
}

class InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  const InfoCard({super.key, required this.icon, required this.iconColor, required this.title});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: iconColor), const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class PostCard extends StatelessWidget {
  final String profileAsset;
  final String name;
  final String time;
  final String caption;
  final List<String> photos;

  const PostCard({
    super.key,
    required this.profileAsset,
    required this.name,
    required this.time,
    required this.caption,
    required this.photos,
  });

  static Widget buildFromData({
    required BuildContext context,
    required String profileAsset,
    required String name,
    required String time,
    required String caption,
    required List<String> photos,
  }) =>
      PostCard(profileAsset: profileAsset, name: name, time: time, caption: caption, photos: photos);

  bool _isUrl(String p) => p.startsWith('http://') || p.startsWith('https://');

  void _openPhoto(BuildContext context, String p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewScreen(imageAsset: p)));
  }

  Widget _img(BuildContext context, String p, {BorderRadius? r}) {
    final w = _isUrl(p) ? Image.network(p, fit: BoxFit.cover) : Image.asset(p, fit: BoxFit.cover);
    return GestureDetector(
      onTap: () => _openPhoto(context, p),
      child: ClipRRect(borderRadius: r ?? BorderRadius.circular(16), child: w),
    );
  }

  Widget _photos(BuildContext context) {
    const gap = 8.0;
    if (photos.isEmpty) return const SizedBox.shrink();
    if (photos.length == 1) {
      return SizedBox(height: 500, width: double.infinity, child: _img(context, photos[0]));
    }
    if (photos.length == 2) {
      return SizedBox(
        height: 500,
        child: Row(
          children: [
            Expanded(child: _img(context, photos[0])),
            const SizedBox(width: gap),
            Expanded(child: _img(context, photos[1])),
          ],
        ),
      );
    }
    if (photos.length == 3) {
      return SizedBox(
        height: 500,
        child: Row(
          children: [
            Expanded(child: _img(context, photos[0])),
            const SizedBox(width: gap),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _img(context, photos[1])),
                  const SizedBox(height: gap),
                  Expanded(child: _img(context, photos[2])),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
        childAspectRatio: 1,
      ),
      itemCount: photos.length,
      itemBuilder: (context, i) => _img(context, photos[i], r: BorderRadius.circular(10)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _isUrl(profileAsset) ? NetworkImage(profileAsset) : AssetImage(profileAsset) as ImageProvider;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 24, backgroundImage: avatar),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(time, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6))),
          ]),
          const Spacer(),
          const Icon(Icons.more_vert),
        ]),
        const SizedBox(height: 12),
        Text(caption, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        _photos(context),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: const [
          Icon(Icons.favorite_border),
          Icon(Icons.chat_bubble_outline),
          Icon(Icons.share),
        ]),
      ]),
    );
  }
}

class PhotoViewScreen extends StatelessWidget {
  final String? imageAsset;
  const PhotoViewScreen({super.key, this.imageAsset});
  bool _isUrl(String p) => p.startsWith('http://') || p.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    final child = imageAsset == null
        ? const Center(child: Text('Нет изображения', style: TextStyle(color: Colors.white)))
        : Center(child: InteractiveViewer(child: _isUrl(imageAsset!) ? Image.network(imageAsset!, fit: BoxFit.contain) : Image.asset(imageAsset!, fit: BoxFit.contain)));
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.home, color: Colors.white),
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
