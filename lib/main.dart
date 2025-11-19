import 'package:flutter/material.dart'; // подключаем flutter ui-библиотеку, без неё виджеты и темы недоступны
import 'package:shared_preferences/shared_preferences.dart'; // подключаем хранилище простых настроек на устройстве (key-value)
import 'package:supabase_flutter/supabase_flutter.dart'; // подключаем клиент supabase для работы с бэкендом, базой и хранилищем
// supabase: базовая конфигурация и клиент
const String supabaseUrl = 'https://azccbwduobbulgdgucjj.supabase.co'; // const потому что это неизменяемый адрес проекта supabase, он известен на этапе компиляции
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF6Y2Nid2R1b2JidWxnZGd1Y2pqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk4MDUyNzgsImV4cCI6MjA3NTM4MTI3OH0.x9jEzJnHg_fiX0dFXpWD70kKH848QZC4uELlMpL1yos';
// const потому что публичный ключ авторизации "anon" тоже фиксирован и не меняется во время работы приложения
// PUBLIC бакеты
const String postBucketName = 'post-images'; // тут имя бакета в storage supabase для фотографий постов, const так как это постоянное строковое значение
const String avatarsBucketName = 'avatars';// тут имя бакета для аватаров пользователей, const по той же причине — это константный идентификатор
late final SupabaseClient supabase; // late final потому что объект клиента создаём один раз после инициализации и больше не меняем (final), но значение присвоится чуть позже, не сразу при объявлении (late)
extension StringX on String {
  bool get isHttpUrl => startsWith('http://') || startsWith('https://');// геттер проверяет, начинается ли строка с http/https, то есть является ли она url
}
String _clean(String s) => s.replaceAll(RegExp(r'^/+'), ''); // приватная функция убирает ведущие слэши в начале строки, чтобы нормализовать путь
// Публичная ссылка на объект (корень бакета)
String publicUrl({required String bucket, required String objectKey}) => // функция собирает публичный url к объекту в storage supabase
Supabase.instance.client.storage.from(bucket).getPublicUrl(_clean(objectKey));// тут обращаемся к клиенту supabase и просим публичную ссылку к объекту, предварительно чистим путь
class ThemeController extends ChangeNotifier { // контроллер темы, наследуемся от ChangeNotifier, чтобы уведомлять ui о смене темы
  ThemeMode _mode = ThemeMode.system; // приватное поле текущего режима темы, по умолчанию брать системный
  ThemeMode get mode => _mode; // публичный геттер, чтобы только читать текущее значение темы снаружи
  Future<void> load() async { // метод загружает сохранённый режим темы из локального хранилища
    final v = (await SharedPreferences.getInstance()).getString('theme_mode');  // получаем экземпляр shared preferences и читаем ключ theme_mode
    _mode = v == 'light'  // выбираем режим по сохранённой строке
        ? ThemeMode.light // если записано light — включаем светлую тему
        : v == 'dark'  // иначе если dark — тёмную
        ? ThemeMode.dark // соответствующее значение
        : ThemeMode.system;  // иначе оставляем системную по умолчанию
    notifyListeners();  // уведомляем слушателей (виджеты), что состояние изменилось
  }
  Future<void> toggle() async {  // метод переключает светлая/тёмная тема и сохраняет выбор
    _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;  // если было light — делаем dark и наоборот
    notifyListeners(); // уведомляем ui, чтобы он перерисовался с новой темой
    final prefs = await SharedPreferences.getInstance();  // берём доступ к локальному хранилищу
    await prefs.setString('theme_mode', _mode == ThemeMode.light ? 'light' : 'dark');  // сохраняем выбранный режим строкой, чтобы восстановить при следующем запуске
  }
}
class AuthService { // обёртка над supabase.auth и профилями public.users
  static SupabaseClient get _supa => Supabase.instance.client; // короткий доступ к клиенту

  static User? get currentUser => _supa.auth.currentUser; // текущий пользователь (или null)

  static Future<void> signOut() async { // выход из аккаунта
    await _supa.auth.signOut(); // очищаем сессию и токены
  }

  // Регистрация (если понадобится)
  static Future<AuthResponse> signUp({
    required String email,// email для входа
    required String password,// пароль
    required String login,// логин (фамилия+инициалы)
    required String fullName,// ФИО
  }) async {
    return _supa.auth.signUp(
      email: email,// почта
      password: password,// пароль
      data: {// метаданные → пойдут в public.users через триггер
        'login': login,
        'full_name': fullName,
      },
    );
  }
  // Вход по логину/email + пароль, с опциональной 2FA по email-коду
  static Future<_TwoFactorPlan> signInWithPasswordAndPlan2FA({
    required String identifier,// логин ИЛИ email
    required String password, //пароль
  }) async {
    final idNorm = identifier.trim().toLowerCase(); // нормализуем ввод

    String? email;// сюда положим email

    if (idNorm.contains('@')) {// если похоже на email
      email = idNorm;
    } else {// иначе считаем, что это login
      final row = await _supa
          .from('users')
          .select('email')
          .eq('login', idNorm)
          .maybeSingle();// ищем профиль по login
      email = row?['email'] as String?;
    }
    if (email == null || email.isEmpty) {
      throw AuthException('Пользователь не найден или не задан email');
    }
    // 1) Проверяем пароль (Supabase создаст СЕССИЮ)
    final res = await _supa.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = res.user;
    if (user == null) {
      throw AuthException('Не удалось войти');
    }
    // 2) Читаем профиль, чтобы понять режим 2FA
    final profile = await _supa
        .from('users')
        .select('two_factor_type, email')
        .eq('id', user.id)
        .maybeSingle();
    final mode = (profile?['two_factor_type'] as String?) ?? 'auto';// auto/email/none
    final profileEmail = (profile?['email'] as String?) ?? email;// email из профиля или auth
    if (mode == 'none') {
      // Оставляем созданную сессию → пользователь уже полностью залогинен
      return _TwoFactorPlan.none(user.id);
    }

    // === Вариант с 2FA по email ===
    if ((mode == 'auto' || mode == 'email') &&
        profileEmail != null &&
        profileEmail.isNotEmpty) {
      // ВАЖНО: пароль прошёл, но мы НЕ доверяем этой сессии до ввода кода
      await _supa.auth.signOut();// убираем сессию от signInWithPassword
      await _supa.auth.signInWithOtp(// отправляем одноразовый код на email
        email: profileEmail,
        shouldCreateUser: false,// не создаём нового пользователя
      );
      // Сейчас НЕТ активной сессии. Она появится только после verifyOTP.
      return _TwoFactorPlan.email(user.id, profileEmail);
    }
    // Если ни email, ни валидный режим — считаем, что 2FA недоступна, оставляем вход по паролю
    return _TwoFactorPlan.none(user.id);
  }

  // Подтверждение одноразового кода (email 2FA)
  static Future<void> verifyOtp({
    required _TwoFactorPlan plan,// план, полученный на первом шаге
    required String code,// код из письма
  }) async {
    if (plan.kind == _TwoFactorKind.none) {
      return;// если 2FA не нужна — ничего не делаем
    }

    if (plan.kind == _TwoFactorKind.email) {
      // verifyOTP создаст НОВУЮ полноценную сессию, если код верный
      await _supa.auth.verifyOTP(
        token: code.trim(),// введённый код
        type: OtpType.email,// подтверждаем по email
        email: plan.target,// адрес, на который слали код
      );
      return;
    }
  }
}

// Варианты 2FA для плана
enum _TwoFactorKind { none, email }

// Описание "плана" 2FA
class _TwoFactorPlan {
  final String userId;// uid пользователя (из успешного password-логина)
  final _TwoFactorKind kind;// вид 2FA
  final String? target;// email для кода

  _TwoFactorPlan._(this.userId, this.kind, this.target);

  factory _TwoFactorPlan.none(String userId) =>
      _TwoFactorPlan._(userId, _TwoFactorKind.none, null);

  factory _TwoFactorPlan.email(String userId, String email) =>
      _TwoFactorPlan._(userId, _TwoFactorKind.email, email);
}

class UserModel { // простая модель пользователя для удобной передачи данных
  final String id; // final потому что после создания объекта id пользователя не должен меняться
  final String login; // final по той же причине — логин фиксируется при создании модели
  final String fullName;  // final — полное имя, в модели неизменно
  final String? avatarUrl;  // может быть null или относительным путём, final — модель неизменяемая после конструирования
  const UserModel({required this.id, required this.login, required this.fullName, this.avatarUrl}); // конструктор с const, чтобы экземпляры можно было создавать как неизменяемые литералы где возможно
}
class PostModel { // модель поста с полями автора и медиа
  final String id; // final — идентификатор поста неизменяем
  final String authorId; // final — ссылка на автора фиксирована
  final String authorLogin; // final — кэшируем логин автора для быстрого доступа
  final String authorName; // final — кэшируем имя автора
  final String? authorAvatarUrl; // final  — ссылка на аватар может быть null, но после создания модели не меняется
  final DateTime createdAt; // final — время создания поста постоянное
  final String text;  // final — текст поста в модели неизменяем
  final List<String> imageUrls;  // final — список ссылок на изображения, сам список не переназначаем (но, его содержимое теоретически можно менять, если не сделать unmodifiable)
  const PostModel({  // конструктор с const, так модель поста можно использовать как неизменяемый объект
    required this.id,  // обязательные поля
    required this.authorId,
    required this.authorLogin,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.createdAt,
    required this.text,
    required this.imageUrls,
  });
}
class PostsRepository {  // репозиторий инкапсулирует всю логику чтения постов и связанных данных
  final SupabaseClient supa;  // final — ссылка на клиент базы задаётся при создании репозитория и не меняется
  PostsRepository(this.supa);  // простой конструктор, принимаем клиент извне (внедрение зависимости)
  static const Map<String, List<String>> _legacyCaptionToNames = { // const-карта "старый текст подписи -> список имён файлов", const потому что это заранее известные соответствия
    'Красота то какая! Ляпота!🌅 -  © Казенов Эдуард': ['photo3.jpg'], // если в старых данных встретится такая подпись — подставим эти файлы
    'Поход в лес! 🌳🏔️🌲': ['photo1.jpg', 'photo2.jpg'], // та же идея для других подписей
    'Мой отдых 🌊🌊🌊': ['photo4.jpg', 'photo5.jpg', 'photo21.jpg'], // сопоставление подписи и имён изображений
    'Красиво, однако!': ['photo6.jpg', 'photo7.jpg', 'photo8.jpg', 'photo9.jpg','photo10.jpg', 'photo11.jpg','photo24.jpg', 'photo25.jpg'], // используем как запасной источник, если в post_images нет записей / проблемы с инетом
  };
  List<String> _publicUrlsOrAssets(List<String> names) => // приватный метод превращает имена файлов в публичные url к бакету постов
  names.map((n) => publicUrl(bucket: postBucketName, objectKey: n)).toList(); // для каждого имени строим публичную ссылку и собираем в список
  String _postImagePublicUrlFromStoragePath(String storagePath) {  // приватный метод нормализует путь вида "post-images/xxx" и делает из него публичный url
    final clean = _clean(storagePath); // сначала убираем лишние слэши в начале
    final fixed = clean.startsWith('post-images/') ? clean.substring('post-images/'.length) : clean;  // если путь содержит префикс бакета — отрезаем его, чтобы не дублировать при сборке url
    return publicUrl(bucket: postBucketName, objectKey: fixed); // собираем и возвращаем публичную ссылку на объект
  }
  // Публичный URL для аватара автора (абсолютный -> как есть; относительный -> из avatars; иначе <login>.jpg)
  String _authorAvatarPublicUrl(String? avatarUrlFromDb, String authorLogin) => // определяем публичный url на аватар автора с учётом разных форматов
  (avatarUrlFromDb?.isHttpUrl ?? false) // если в базе уже сохранён абсолютный http/https url
      ? avatarUrlFromDb!  // тогда возвращаем его как есть
      : publicUrl(  // иначе строим ссылку через бакет avatars
    bucket: avatarsBucketName, // используем бакет для аватаров
    objectKey: (avatarUrlFromDb != null && avatarUrlFromDb.isNotEmpty) // если в базе лежит относительный путь
        ? avatarUrlFromDb // берём его
        : '$authorLogin.jpg', // иначе пробуем дефолт: файл с именем логина и расширением .jpg
  );
  Future<List<PostModel>> loadPosts() async {  // основной метод: грузим посты, пользователей и картинки "пачками", чтобы избежать n+1 запросов
    final postsRaw = await supa // первый запрос: сами посты
        .from('posts') // таблица posts
        .select('id,user_id,created_at,text') // берём нужные поля, чтобы не тащить лишнее
        .order('created_at', ascending: false);  // сортируем по дате создания по убыванию, свежие первыми
    if (postsRaw.isEmpty) return const []; // если постов нет — сразу возвращаем пустой неизменяемый список
    final postIds = postsRaw.map<String>((p) => p['id'] as String).toList(); // собираем список id постов для последующих запросов (список меняемый нам не нужен, но toList удобен)
    final userIds = postsRaw.map<String>((p) => p['user_id'] as String).toSet().toList(); // собираем уникальные id пользователей (toSet убирает дубликаты), потом снова в список для фильтра .inFilter
    final usersRaw = await supa // второй запрос: все пользователи, на которых ссылаются посты
        .from('users') // таблица users
        .select('id,login,full_name,avatar_url') // только нужные поля для построения автора поста
        .inFilter('id', userIds);  // фильтруем по множеству id, чтобы одним запросом взять всех авторов
    final imagesRaw = await supa // третий запрос: все изображения для всех постов
        .from('post_images') // таблица со связью пост -> картинки
        .select('post_id,storage_path,sort_order') // берём id поста, путь в storage и порядок сортировки
        .inFilter('post_id', postIds) // фильтруем по всем нашим постам сразу
        .order('sort_order');  // сортируем картинки внутри поста по полю sort_order
    // Индексы:
    final usersById = {  // строим индекс: словарь id пользователя -> модель пользователя
      for (final u in usersRaw)  // пробегаем все записи пользователей
        (u['id'] as String): UserModel( // ключ — строковый id
          id: u['id'] as String, // приводим тип к String
          login: (u['login'] ?? '') as String,  // если логина нет — подставляем пустую строку, чтобы избежать null
          fullName: (u['full_name'] ?? '') as String, // аналогично для полного имени
          avatarUrl: u['avatar_url'] as String?,// аватар может быть null, оставляем как опциональный
        )
    }; // в итоге получаем удобный быстрый доступ к данным пользователя по id
    final imagesByPost = <String, List<String>>{}; // готовим индекс: id поста -> список публичных url картинок
    for (final row in imagesRaw) { // пробегаем все строки с картинками
      final pid = row['post_id'] as String;// достаём id поста
      final sp = row['storage_path'] as String;// достаём путь в хранилище
      imagesByPost.putIfAbsent(pid, () => []).add(_postImagePublicUrlFromStoragePath(sp));// создаём список, если его ещё не было, и добавляем туда публичный url картинки
    }
    // Сборка PostModel
    return postsRaw.map<PostModel>((p) {  // преобразуем сырые данные постов в список моделей PostModel
      final postId = p['id'] as String;// берём id текущего поста
      final userId = p['user_id'] as String; // берём id автора
      final createdAt = DateTime.parse(p['created_at'] as String);// парсим дату создания из строки в DateTime
      final text = (p['text'] ?? '') as String;// берём текст поста, если null — подставляем пустую строку
      final author = usersById[userId];// достаём модель автора из индекса по id
      final authorLogin = author?.login ?? '';// логин автора или пустая строка, если по какой-то причине автора не нашли
      final authorName = author?.fullName ?? '';// полное имя автора или пустая строка
      final authorAvatarUrl = _authorAvatarPublicUrl(author?.avatarUrl, authorLogin);// строим корректный публичный url на аватар с учётом вариантов хранения
      final photoUrls = (imagesByPost[postId] ?? [])// берём список картинок для поста, если нет — пустой список
          .let((list) => list.isNotEmpty ? list : (_legacyCaptionToNames[text]?.let(_publicUrlsOrAssets) ?? const [])); // если список пуст — пробуем подобрать картинки по "старой" подписи, иначе оставляем как есть
      return PostModel( // создаём модель поста
        id: postId,// присваиваем id
        authorId: userId,// присваиваем id автора
        authorLogin: authorLogin,// логин автора
        authorName: authorName,// имя автора
        authorAvatarUrl: authorAvatarUrl,// публичный url аватара
        createdAt: createdAt,// дата создания
        text: text,// текст поста
        imageUrls: photoUrls,// список публичных ссылок на изображения поста
      );
    }).toList(); // преобразуем итерируемую коллекцию в список
  }
}
extension _Let<T> on T { // небольшое расширение let, для удобной цепочки действий
  R let<R>(R Function(T it) f) => f(this);  // вызывает переданную функцию с текущим значением и возвращает её результат, упрощая ветвления
}
Future<void> main() async {// точка входа приложения
  WidgetsFlutterBinding.ensureInitialized();// инициализируем Flutter до асинхронщины
  await Supabase.initialize(// инициализируем Supabase SDK
    url: supabaseUrl,// адрес проекта
    anonKey: supabaseAnonKey,// публичный anon key
  );
  supabase = Supabase.instance.client;// сохраняем клиент в глобальную переменную

  final current = supabase.auth.currentUser;// читаем текущего пользователя из локальной сессии (если есть)
  runApp(MyApp(initialUserId: current?.id));// если уже залогинен — сразу в Home, иначе Login
}

class MyApp extends StatefulWidget {// корневой виджет c состоянием
  final ThemeController? themeController;// опциональный внешний контроллер темы
  final String? initialUserId;// uid, если пользователь уже залогинен
  const MyApp({super.key, this.themeController, this.initialUserId});

  @override
  State<MyApp> createState() => _MyAppState();// создаём состояние
}

class _MyAppState extends State<MyApp> {
  late final ThemeController _theme;// контроллер темы
  String? _userId;// текущий uid пользователя (auth.users.id)
  bool _themeReady = false; //флаг готовности темы

  @override
  void initState() {
    super.initState();// базовая инициализация
    _theme = widget.themeController ?? ThemeController(); // берём переданный контроллер или создаём свой
    _userId = widget.initialUserId;// если при старте уже есть пользователь — запоминаем
    _initTheme();// запускаем загрузку сохранённой темы
  }

  Future<void> _initTheme() async {// приватный метод загрузки темы
    await _theme.load();// читаем режим из SharedPreferences
    if (!mounted) return;// если виджет уже уничтожен — выходим
    setState(() => _themeReady = true);// отмечаем, что тема готова
  }

  @override
  Widget build(BuildContext context) {
    if (!_themeReady) {// пока тема не загрузилась
      return MaterialApp(// рисуем пустое светлое приложение-заглушку
        debugShowCheckedModeBanner: false,
        home: Container(color: Colors.white),
      );
    }

    return AnimatedBuilder(// AnimatedBuilder слушает изменения темы
      animation: _theme,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,// убираем плашку DEBUG
        themeMode: _theme.mode,// текущий режим темы
        theme: ThemeData(// светлая тема
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF5EEDC),
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        ),
        darkTheme: ThemeData(// тёмная тема
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
          snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        ),
        home: _userId == null// если пользователь не залогинен
            ? LoginScreen(// показываем экран входа
          onSignedIn: (uid) => setState(() => _userId = uid), // при успешном входе сохраняем uid
        )
            : HomeScreen(// иначе показываем главный экран
          currentUserId: _userId!,// передаём uid
          onSignOut: () async {// обработчик выхода
            await AuthService.signOut();// выходим из supabase.auth
            if (mounted) {
              setState(() => _userId = null); // возвращаемся на экран входа
            }
          },
          themeController: _theme,// прокидываем контроллер темы
        ),
        routes: {
          '/photo': (_) => const PhotoViewScreen(),// маршрут просмотра фото
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final ValueChanged<String> onSignedIn;// сообщает uid при успешном логине
  const LoginScreen({super.key, required this.onSignedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final loginCtrl = TextEditingController();// логин или email
  final passCtrl = TextEditingController();// пароль
  final otpCtrl = TextEditingController();// код 2FA

  bool loading = false;// идёт ли запрос
  String? error;// текст ошибки
  _TwoFactorPlan? _plan;// текущий план 2FA
  bool get _waitingOtp => _plan != null && _plan!.kind != _TwoFactorKind.none;// ждём ли код

  void _reset2FA() {// сброс ожидания кода
    setState(() {
      _plan = null;// план очищаем
      otpCtrl.clear();// поле кода чистим
      error = null;// ошибки убираем
    });
  }

  Future<void> _startLogin() async {// шаг 1: логин+пароль
    _reset2FA();// на всякий случай сбрасываем старый план
    setState(() {
      loading = true;// включаем индикатор
      error = null;// очищаем ошибку
    });
    try {
      final plan = await AuthService.signInWithPasswordAndPlan2FA(
        identifier: loginCtrl.text,// логин или email
        password: passCtrl.text,// пароль
      );

      if (plan.kind == _TwoFactorKind.none) {// если 2FA не требуется
        widget.onSignedIn(plan.userId);// сразу пускаем в приложение
      } else {// иначе ждём код с почты
        setState(() {
          _plan = plan;// сохраняем план
          // login/password останутся, но будут заблокированы (см. enabled)
        });
      }
    } on AuthException catch (e) {// ошибки авторизации
      setState(() => error = e.message);
    } catch (e) {// другие ошибки
      setState(() => error = 'Ошибка входа: $e');
    } finally {
      if (mounted) {
        setState(() => loading = false);// выключаем индикатор
      }
    }
  }

  Future<void> _confirmOtp() async {// шаг 2: подтверждение кода
    final plan = _plan;
    if (plan == null || plan.kind == _TwoFactorKind.none) {
      return;// если плана нет — ничего не делаем
    }
    setState(() {
      loading = true;// индикатор
      error = null;// убираем ошибку
    });
    try {
      await AuthService.verifyOtp(
        plan: plan,// план 2FA
        code: otpCtrl.text,// введённый код
      );
      // После успешного verifyOTP Supabase создаст полноценную сессию.
      widget.onSignedIn(plan.userId);// пускаем пользователя
    } on AuthException catch (e) {// неверный/просроченный код
      setState(() => error = 'Неверный код: ${e.message}');
    } catch (e) {// другие ошибки
      setState(() => error = 'Ошибка подтверждения кода: $e');
    } finally {
      if (mounted) {
        setState(() => loading = false);// выключаем индикатор
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final waitingOtp = _waitingOtp;// локальная копия для удобства

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420), // ограничиваем ширину
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Вход',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                // ЛОГИН / EMAIL
                TextField(
                  controller: loginCtrl,
                  enabled: !waitingOtp && !loading, // при ожидании кода блокируем изменение
                  decoration: const InputDecoration(
                    labelText: 'Логин или Email',
                  ),
                ),
                const SizedBox(height: 8),

                // ПАРОЛЬ
                TextField(
                  controller: passCtrl,
                  enabled: !waitingOtp && !loading, // тоже блокируем при 2FA
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                  ),
                ),
                const SizedBox(height: 16),

                // ПОЛЕ ДЛЯ КОДА 2FA
                if (waitingOtp) ...[
                  TextField(
                    controller: otpCtrl,
                    enabled: !loading,// можно вводить, пока не отправляем
                    decoration: const InputDecoration(
                      labelText: 'Код из письма',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Мы отправили код на вашу почту. '
                        'Введите его, чтобы завершить вход.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                ],

                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),

                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(
                      onPressed: loading || waitingOtp
                          ? null// пока ждём код — не даём заново жать "Войти"
                          : _startLogin,
                      child: loading && !waitingOtp
                          ? const CircularProgressIndicator()
                          : const Text('Войти'),
                    ),

                    if (waitingOtp) ...[
                      ElevatedButton(
                        onPressed: loading ? null : _confirmOtp,
                        child: loading
                            ? const CircularProgressIndicator()
                            : const Text('Подтвердить'),
                      ),
                      TextButton(
                        onPressed: loading
                            ? null
                            : _reset2FA,// сброс процесса 2FA
                        child: const Text('Отмена'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class HomeScreen extends StatefulWidget { // главный экран после входа, со стейтом (нужно хранить посты и пользователя)
  final String currentUserId; // final — id текущего пользователя задаётся при создании и не меняется
  final VoidCallback onSignOut;  // final — колбэк выхода, ссылка постоянна
  final ThemeController themeController;  // final — контроллер темы, ссылка постоянна
  const HomeScreen({super.key, required this.currentUserId, required this.onSignOut, required this.themeController}); // конструктор с обязательными параметрами
  @override
  State<HomeScreen> createState() => _HomeScreenState(); // создаём состояние экрана
}
class _HomeScreenState extends State<HomeScreen> { // состояние главного экрана
  late final PostsRepository repo; // late final — создаём репозиторий один раз в initState, ссылка не меняется
  List<PostModel> posts = const []; // список постов, изначально пустой неизменяемый список
  bool loading = true; // флаг индикатора загрузки
  UserModel? me; // данные текущего пользователя, могут отсутствовать до загрузки
  @override
  void initState() { // инициализация состояния
    super.initState();// вызываем базовую инициализацию
    repo = PostsRepository(supabase); // создаём репозиторий, передаём клиент supabase
    _loadAll(); // запускаем загрузку данных (пользователь и посты)
  }
  Future<void> _loadAll() async { // приватный метод загружает пользователя и посты
    setState(() => loading = true);  // включаем индикатор загрузки
    try { // перехватываем возможные ошибки
      final u = await supabase // запрос к таблице users для текущего пользователя
          .from('users')// выбираем таблицу
          .select('id, login, full_name, avatar_url') // нужные поля
          .eq('id', widget.currentUserId)  // фильтр по id из параметров экрана
          .single(); // ожидаем ровно одну строку (иначе будет ошибка)
      me = UserModel(  // собираем модель текущего пользователя
        id: u['id'] as String,// приводим к String
        login: (u['login'] ?? '') as String, // логин или пустая строка
        fullName: (u['full_name'] ?? '') as String, // фио или пустая строка
        avatarUrl: u['avatar_url'] as String?, // ссылка на аватар или null
      );
      posts = await repo.loadPosts(); // загружаем посты через репозиторий
    } finally {  // выполняется в любом случае — и при успехе, и при ошибке
      if (mounted) setState(() => loading = false);  // выключаем индикатор, если экран ещё смонтирован
    }
  }
  String _timeAgo(DateTime dt) {  // преобразует дату создания поста в "n минут/часов/дней назад"
    final d = DateTime.now().difference(dt);  // разница между текущим временем и датой поста
    return d.inMinutes < 60  // если меньше часа
        ? '${d.inMinutes} минут назад'  // показываем минуты
        : d.inHours < 24  // если меньше суток
        ? '${d.inHours} часов назад'// показываем часы
        : '${d.inDays} дн. назад';  // иначе показываем дни
  }
  String _greeting(UserModel? u) { // формирует приветствие в шапке по времени суток и имени пользователя
    final name = (u?.fullName ?? '').trim();// берём имя пользователя или пустую строку
    final h = DateTime.now().hour; // текущий час
    final g = (h >= 4 && h < 12) // подбираем фразу в зависимости от часа
        ? 'Доброе утро'
        : (h < 17)
        ? 'Добрый день'
        : (h < 22)
        ? 'Добрый вечер'
        : 'Доброй ночи';
    return name.isEmpty ? 'Здравствуйте!' : '$g, $name!';// если имени нет — нейтральное приветствие, иначе с именем
  }
  void _goHome(BuildContext context) => Navigator.of(context).popUntil((route) => route.isFirst);// возвращаемся на корневой экран, закрывая вложенные
  void _stub(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg))); // показываем временную заглушку через снекбар
  @override
  Widget build(BuildContext context) {// строим визуальную часть главного экрана
    final list = loading// если идёт загрузка
        ? const Center(child: CircularProgressIndicator())// показываем крутилку по центру
        : ListView( // иначе рисуем список
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),// отступы вокруг списка
      children: [// элементы списка
        Row(children: const [// ряд с двумя информационными карточками
          Expanded(child: InfoCard(icon: Icons.notifications, iconColor: Colors.yellow, title: '10 новостей')),// карточка "новости"
          Expanded(child: InfoCard(icon: Icons.event, iconColor: Colors.green, title: '15 событий')),// карточка "события"
        ]),
        const SizedBox(height: 16), // отступ
        ...posts.expand((p) sync* { // разворачиваем посты в последовательность виджетов: карточка поста + отступ
          yield PostCard.buildFromData(// создаём карточку поста из модели
            context: context, // передаём контекст для навигации
            profileAsset: p.authorAvatarUrl ?? 'assets/profile0.jpg',// если нет url аватара — используем локальный ассет-заглушку
            name: p.authorName,// имя автора
            time: _timeAgo(p.createdAt), // "сколько времени назад"
            caption: p.text,// текст поста
            photos: p.imageUrls,// список ссылок на фото
          );
          yield const SizedBox(height: 16); // отступ между карточками
        }),
        const SizedBox(height: 80),// нижний отступ, чтобы контент не прятался за нижней панелью
      ],
    );
    return Scaffold(// каркас экрана с app-body и нижней панелью
      body: SafeArea(// контент внутри безопасной области (без вырезов и статус-бара)
        child: Column(// вертикальная колонка
          children: [
            AppHeader( // шапка приложения с приветствием и кнопками
              greeting: _greeting(me),// текст приветствия
              currentUserLogin: me?.login,// логин пользователя для поиска аватара по умолчанию
              currentUserAvatarUrl: me?.avatarUrl, // прямая ссылка на аватар, если есть
              onToggleTheme: widget.themeController.toggle,// обработчик переключения темы
              onSignOut: widget.onSignOut,// обработчик выхода из аккаунта
            ),
            const SizedBox(height: 12),// отступ под шапкой
            Expanded(child: list),// основная область — список постов или индикатор
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(// нижняя панель с кнопками
        shape: const CircularNotchedRectangle(), // форма с вырезом под плавающую кнопку (на будущее)
        child: Padding( // внутренние отступы
          padding: const EdgeInsets.symmetric(horizontal: 8.0),// слева/справа по 8
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [// распределяем элементы по краям
            Row(children: [// группа иконок слева
              IconButton(icon: const Icon(Icons.home), onPressed: () => _goHome(context)), // кнопка "домой"
              IconButton(icon: const Icon(Icons.search), onPressed: () => _stub(context, 'Поиск (заглушка)')),// кнопка "поиск" (пока заглушка)
              IconButton(icon: const Icon(Icons.person), onPressed: () => _stub(context, 'Профиль (заглушка)')),// кнопка "профиль" (пока заглушка)
            ]),
          ]),
        ),
      ),
    );
  }
}
class AppHeader extends StatelessWidget {// виджет шапки (без состояния), показывает приветствие и аватар
  final String greeting; // "Добрый день, ФИО!" + final — текст приветствия задаётся снаружи и не меняется
  final String? currentUserLogin; // для avatars/<login>.jpg  + final — логин пользователя может быть null, используется для поиска аватара по умолчанию
  final String? currentUserAvatarUrl;  // final — ссылка на аватар (абсолютная или относительная), тоже не меняется
  final VoidCallback onToggleTheme; // final — обработчик переключения темы, ссылка постоянна
  final VoidCallback onSignOut; // final — обработчик выхода, ссылка постоянна
  const AppHeader({ // конструктор шапки
    super.key,// передаём key в базовый класс
    required this.greeting, // обязательные параметры
    required this.currentUserLogin, // обязательные параметр
    required this.currentUserAvatarUrl,// обязательные параметр
    required this.onToggleTheme,// обязательные параметр
    required this.onSignOut,// обязательные параметр
  });
  ImageProvider _resolveAvatar() {// внутренний метод определяет, откуда грузить картинку аватара
    if ((currentUserAvatarUrl?.isHttpUrl ?? false)) {// если передан абсолютный url http/https
      return NetworkImage(currentUserAvatarUrl!);// грузим из сети по прямой ссылке
    }
    if (currentUserAvatarUrl != null && currentUserAvatarUrl!.isNotEmpty) { // если относительный путь внутри бакета
      return NetworkImage(publicUrl(bucket: avatarsBucketName, objectKey: currentUserAvatarUrl!));// собираем публичный url из бакета avatars
    }
    final login = (currentUserLogin ?? '').trim(); // берём логин, если есть
    return login.isNotEmpty // если логин не пустой
        ? NetworkImage(publicUrl(bucket: avatarsBucketName, objectKey: '$login.jpg')) // пробуем дефолтный файл <логин>.jpg
        : const AssetImage('assets/profile0.jpg'); // иначе — локальный ассет-заглушка
  }
  @override
  Widget build(BuildContext context) { // рисуем шапку
    final avatar = _resolveAvatar(); // получаем источник картинки для аватара
    return Padding( // контейнер с отступами
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // по 16 по бокам и 8 по вертикали
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ // важное camelCase: spaceBetween
        Expanded(// блок текста занимает доступное место слева
          child: Text(// приветствие
            greeting, // сам текст
            maxLines: 2, // максимум две строки
            overflow: TextOverflow.ellipsis,  // обрезаем с троеточием, если не влезает
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),  // крупный жирный шрифт
          ),
        ),
        const SizedBox(width: 8), // небольшой горизонтальный отступ
        Row(children: [ // кнопки справа
          IconButton(tooltip: 'Тема', onPressed: onToggleTheme, icon: const Icon(Icons.brightness_6)),  // переключение темы
          IconButton(tooltip: 'Выход', onPressed: onSignOut, icon: const Icon(Icons.logout)), // выход из аккаунта
          CircleAvatar(radius: 28, backgroundImage: avatar), // сам аватар пользователя
        ]),
      ]),
    );
  }
}
class InfoCard extends StatelessWidget { // простая карточка с иконкой и заголовком
  final IconData icon;  // final потому что иконка задаётся при создании и не меняется
  final Color iconColor; // final потому что цвет иконки задаётся при создании и не меняется
  final String title;  // final потому что заголовок задаётся при создании и не меняется
  const InfoCard({super.key, required this.icon, required this.iconColor, required this.title});// конструктор с обязательными параметрами
  @override
  Widget build(BuildContext context) => Container(// корневой контейнер карточки
    padding: const EdgeInsets.all(16),// внутренние отступы
    margin: const EdgeInsets.symmetric(horizontal: 8), // внешние отступы по бокам
    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)), // фон по теме и скругления
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [// вертикальная колонка
      Icon(icon, color: iconColor),// иконка нужного цвета
      const SizedBox(height: 8),// отступ
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // заголовок карточки
    ]),
  );
}
class PostCard extends StatelessWidget { // карточка отдельного поста
  final String profileAsset; // URL/asset — аватар АВТОРА ПОСТА + final потому что источник аватара задаётся при создании и не меняется
  final String name; // ФИО автора + final потому что имя автора фиксируется при создании
  final String time; // final потому что строка времени фиксируется при создании
  final String caption; // final потому что текст поста фиксируется при создании
  final List<String> photos; // публичные URL (или ассеты) final потому что ссылка на список не меняется
  const PostCard({  // конструктор карточки поста
    super.key, // ключ виджета
    required this.profileAsset, // обязательные параметры
    required this.name, // обязательные параметры
    required this.time, // обязательные параметры
    required this.caption, // обязательные параметры
    required this.photos, // обязательные параметры
  });
  static Widget buildFromData({ // удобная фабрика для создания PostCard
    required BuildContext context, // контекст нужен для навигации при тапе
    required String profileAsset, // источник аватара
    required String name, // имя автора
    required String time, // "сколько назад"
    required String caption, // текст поста
    required List<String> photos, // список картинок
  }) =>
      PostCard(profileAsset: profileAsset, name: name, time: time, caption: caption, photos: photos); // возвращаем инстанс PostCard
  bool _isUrl(String p) => p.isHttpUrl;  // утилита: является ли строка http/https url
  void _openPhoto(BuildContext context, String p) =>  // открывает экран просмотра фото
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewScreen(imageAsset: p)));  // пушим новый маршрут с PhotoViewScreen
  Widget _img(BuildContext context, String p, {BorderRadius? r}) {  // строим виджет картинки с возможностью тапнуть
    final w = _isUrl(p) ? Image.network(p, fit: BoxFit.cover) : Image.asset(p, fit: BoxFit.cover); // если url — грузим из сети, иначе — из ассетов
    return GestureDetector(// ловим тап по картинке
      onTap: () => _openPhoto(context, p),  // при тапе открываем полноэкранный просмотр
      child: ClipRRect(borderRadius: r ?? BorderRadius.circular(16), child: w), // скругляем углы и вставляем изображение
    );
  }
  // лэйаут фоток
  Widget _photos(BuildContext context) {// раскладка фото внутри карточки
    const gap = 8.0; // отступ между изображениями
    if (photos.isEmpty) return const SizedBox.shrink(); // если нет фото — ничего не рисуем
    if (photos.length == 1) {
      return SizedBox(height: 500, width: double.infinity, child: _img(context, photos[0])); // крупное фото на всю ширину
    }
    if (photos.length == 2) { // два фото
      return SizedBox( // фиксируем высоту
        height: 500,// высота блока с фото
        child: Row(children: [ // горизонтальное расположение двух фото
          Expanded(child: _img(context, photos[0])), // первое фото
          const SizedBox(width: gap),// отступ
          Expanded(child: _img(context, photos[1])), // второе фото
        ]),
      );
    }
    if (photos.length == 3) {// три фото
      return SizedBox( // фиксированная высота
        height: 500, // высота блока
        child: Row(children: [ // слева одно, справа два столбиком
          Expanded(child: _img(context, photos[0])), // левое большое фото
          const SizedBox(width: gap), // отступ
          Expanded( // правая колонка
            child: Column(children: [ // два фото друг под другом
              Expanded(child: _img(context, photos[1])), // верхнее правое
              const SizedBox(height: gap), // отступ
              Expanded(child: _img(context, photos[2])), // нижнее правое
            ]),
          ),
        ]),
      );
    }
    // 4+
    return GridView.builder( // если 4+ фото — рисуем сетку
      physics: const NeverScrollableScrollPhysics(), // у сетки отключаем скролл (прокручивает общий список)
      shrinkWrap: true, // занимаем высоту по контенту
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount( // параметры сетки
        crossAxisCount: 4, // по 4 колонки
        crossAxisSpacing: gap, // отступы по горизонтали
        mainAxisSpacing: gap, // отступы по вертикали
        childAspectRatio: 1, // квадратные ячейки
      ), // конец делегата
      itemCount: photos.length, // количество элементов
      itemBuilder: (context, i) => _img(context, photos[i], r: BorderRadius.circular(10)), // каждая ячейка — картинка со скруглением
    );
  }
  @override
  Widget build(BuildContext context) { // собираем карточку поста
    final avatar = _isUrl(profileAsset) ? NetworkImage(profileAsset) : AssetImage(profileAsset) as ImageProvider; // источник картинки для аватара автора
    return Container( // контейнер карточки
      padding: const EdgeInsets.all(16), // внутренние отступы
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)), // фоновый цвет из темы и скругления
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ // вертикальная колонка элементов
        Row(children: [ // шапка карточки: аватар, имя, время, меню
          CircleAvatar(radius: 24, backgroundImage: avatar), // аватар автора
          const SizedBox(width: 10), // отступ между аватаром и текстом
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ // имя + время
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)), // имя автора жирным
            Text(time, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6))), // приглушённый цвет для времени
          ]), // конец колонки
          const Spacer(), // выталкиваем иконку меню вправо
          const Icon(Icons.more_vert), // иконка "ещё"
        ]), // конец Row
        const SizedBox(height: 12), // отступ
        Text(caption, style: const TextStyle(fontSize: 16)), // текст поста
        const SizedBox(height: 12), // отступ
        _photos(context), // блок с фотографиями
        const SizedBox(height: 12), // отступ
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: const [ // панель действий под постом
          Icon(Icons.favorite_border), // "нравится"
          Icon(Icons.chat_bubble_outline), // "комментарии"
          Icon(Icons.share), // "поделиться"
        ]),
      ]),
    );
  }
}
class PhotoViewScreen extends StatelessWidget { // экран просмотра изображения
  final String? imageAsset; // final потому что путь/ссылка на изображение задаётся при создании и не меняется
  const PhotoViewScreen({super.key, this.imageAsset}); // конструктор принимает опциональный путь/ссылку

  @override
  Widget build(BuildContext context) { // строим интерфейс просмотра
    final isUrl = (imageAsset ?? '').isHttpUrl;// проверяем, является ли строка http/https url
    final child = imageAsset == null // если ничего не передали
        ? const Center(child: Text('Нет изображения', style: TextStyle(color: Colors.white)))// показываем сообщение
        : Center(child: InteractiveViewer(child: isUrl ? Image.network(imageAsset!, fit: BoxFit.contain) : Image.asset(imageAsset!, fit: BoxFit.contain))); // иначе показываем картинку с возможностью зума
    return Scaffold( // каркас экрана
      backgroundColor: Colors.black, // тёмный фон для фото
      body: SafeArea( // содержимое в безопасной области
        child: Stack(children: [ // накладываем панель на картинку
          child, // сам просмотрщик
          Positioned( // нижняя панель поверх
            left: 0, // от левого края
            right: 0, // до правого края
            bottom: 0, // у низа
            child: Container(// полупрозрачная подложка под кнопки
              color: Colors.black54, // тёмный полупрозрачный фон
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),// внутренние отступы
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ // кнопки по краям
                IconButton( // "домой"
                  icon: const Icon(Icons.home, color: Colors.white), // белая иконка
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), // возвращаемся на корневой экран
                ),
                IconButton( // "назад"
                  icon: const Icon(Icons.arrow_back, color: Colors.white), // белая иконка
                  onPressed: () => Navigator.of(context).maybePop(), // возвращаемся на предыдущий экран
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}