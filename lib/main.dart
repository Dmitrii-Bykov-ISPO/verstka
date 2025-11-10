import 'package:flutter/material.dart'; // подключаем flutter ui-библиотеку, без неё виджеты и темы недоступны
import 'package:shared_preferences/shared_preferences.dart'; // подключаем хранилище простых настроек на устройстве (key-value)
import 'package:supabase_flutter/supabase_flutter.dart'; // подключаем клиент supabase для работы с бэкендом, базой и хранилищем
import 'package:go_router/go_router.dart'; // для варианта 3 (GoRouter)

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
class SimpleAuth {  // очень простая "аутентификация" через таблицу users без безопасных токенов
  static const _prefsKey = 'current_user_id';  // const потому что ключ хранения фиксированный и не меняется
  static Future<String?> getCurrentUserId() async =>  // метод читает текущий id пользователя из настроек
  (await SharedPreferences.getInstance()).getString(_prefsKey);  // достаём строку по ключу, может быть null если не входили
  static Future<void> setCurrentUserId(String userId) async => // метод сохраняет текущий id пользователя в настройки
  (await SharedPreferences.getInstance()).setString(_prefsKey, userId); // кладём строку по ключу
  static Future<void> signOut() async =>  // метод "выход" — просто удаляет id из настроек
  (await SharedPreferences.getInstance()).remove(_prefsKey); // убираем ключ из локального хранилища
  static Future<String?> signIn(String login, String password) async  { // метод "вход" — проверяет логин/пароль в таблице users и возвращает id или null
    String norm(String s) => s.trim().toLowerCase(); // локальная функция нормализует строку: убираем пробелы по краям и приводим к нижнему регистру
    final row = await supabase  // обращаемся к базе supabase
        .from('users')  // выбираем таблицу users
        .select('id') // запрашиваем только поле id (нам его достаточно)
        .eq('login', norm(login)) // условие: login равен нормализованному введённому логину
        .eq('password', norm(password)) // условие: password равен нормализованному введённому паролю (в проде так не надо будет делать, нужен хэш, но мне лень))))
        .maybeSingle(); // берём одну запись или null, если ничего не найдено
    return row?['id'] as String?; // если запись есть — достаём поле id как строку, иначе вернётся null
  }
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
    'Красиво, однако!': ['photo6.jpg', 'photo7.jpg', 'photo8.jpg', 'photo9.jpg', 'photo24.jpg', 'photo25.jpg'], // используем как запасной источник, если в post_images нет записей / проблемы с инетом
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
Future<void> main() async {  // точка входа в приложение, async потому что нужно дождаться инициализации supabase перед runApp
  WidgetsFlutterBinding.ensureInitialized();// инициализируем движок flutter до выполнения асинхронных операций, чтобы всё работало корректно
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey); // инициализируем sdk supabase, передаём адрес и публичный ключ
  supabase = Supabase.instance.client;// присваиваем глобальной late final переменной готовый клиент, делаем это один раз на запуске
  runApp(const MyApp());// запускаем само приложение, передаём корневой виджет, const потому что экземпляр без состояния на входе
}
class MyApp extends StatefulWidget {// корневой виджет-приложение со стейтом, чтобы можно было реагировать на смену темы и пользователя
  final ThemeController? themeController;// final — ссылка на контроллер темы, если передадут извне, меняться не должна
  final String? initialUserId;  // final — начальный id пользователя можно передать извне, после создания не меняем
  const MyApp({super.key, this.themeController, this.initialUserId});  // конструктор с именованными параметрами, key передаём вверх по иерархии
  @override
  State<MyApp> createState() => _MyAppState();  // создаём объект состояния для этого виджета
}
class _MyAppState extends State<MyApp> { // состояние приложения, тут живут тема и текущий пользователь
  late final ThemeController _theme; // late final — инициализируем контроллер темы в initState и больше не меняем ссылку
  String? _userId; // текущий id пользователя, может быть null, когда не вошли
  bool _themeReady = false; // флаг "тема загружена", чтобы не мигало при старте
  @override
  void initState() { // метод вызывается один раз при создании состояния
    super.initState();  // всегда вызываем super, чтобы flutter сделал свою часть инициализации
    _theme = widget.themeController ?? ThemeController(); // если контроллер темы передали — используем его, иначе создаём свой
    _userId = widget.initialUserId;  // если начальный пользователь передан — запоминаем
    _theme.load().whenComplete(() => mounted ? setState(() => _themeReady = true) : null); // загружаем сохранённую тему и после завершения ставим флаг и перерисовываемся, если ещё смонтированы
    _ensureInitialUser(); // проверяем/подтягиваем id пользователя из локального хранилища
  }
  Future<void> _ensureInitialUser() async { // приватный метод подтверждает, что у нас есть id пользователя при старте
    _userId ??= await SimpleAuth.getCurrentUserId(); // если _userId пока null — читаем из shared preferences
    if (mounted) setState(() {}); // если виджет на экране — просим перерисовать, чтобы отобразить правильный экран
  }
  @override
  Widget build(BuildContext context) { // метод рисует дерево виджетов в зависимости от состояния
    if (!_themeReady) {  // если тема ещё не загрузилась
      return MaterialApp(debugShowCheckedModeBanner: false, home: Container(color: Colors.white));  // временно показываем пустой белый экран
    }
    return AnimatedBuilder(  // используем AnimatedBuilder, чтобы автоматически реагировать на notifyListeners() от ThemeController
      animation: _theme, // подписываемся на контроллер темы
      builder: (_, __) => MaterialApp( // строим приложение с темами
        debugShowCheckedModeBanner: false, // убираем надпись debug
        themeMode: _theme.mode, // выбираем текущий режим (light/dark/system)
        theme: ThemeData( // светлая тема
          brightness: Brightness.light, // базовая яркость — светлая
          scaffoldBackgroundColor: const Color(0xFFF5EEDC),// фон экранов в светлой теме
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), // палитра цветов
          snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),// стиль снекбаров — всплывающие
        ),
        darkTheme: ThemeData(  // тёмная тема
          brightness: Brightness.dark, // базовая яркость — тёмная
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark), // палитра под тёмную тему
          snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating), // такой же стиль снекбаров
        ),
        home: _userId == null // выбираем, какой экран показывать в зависимости от того, вошёл ли пользователь
            ? LoginScreen(onSignedIn: (u) => setState(() => _userId = u)) // если не вошёл — экран логина, по успешному входу записываем id и перерисовываемся
            : HomeScreen( // если вошёл — главный экран
          currentUserId: _userId!,  // передаём текущий id пользователя (восклицательный знак потому что уже проверили на null)
          onSignOut: () async { // колбэк выхода из аккаунта
            await SimpleAuth.signOut(); // чистим локальное хранилище от id
            setState(() => _userId = null); // переключаемся обратно на экран логина
          },
          themeController: _theme, // передаём контроллер темы для быстрого переключения в ui
        ),
        routes: {
          '/photo': (_) => const PhotoViewScreen(), // регистрируем именованный маршрут на экран просмотра фото

          // ===== Лабораторная: Named Routes в реальном приложении =====
          '/settings': (context) => const SettingsScreen(), // экран настроек, открываем через pushNamed
          '/about': (context) => const AboutAppScreen(), // экран "О приложении", тоже через pushNamed
        },

      ),
    );
  }
}
class LoginScreen extends StatefulWidget {  // экран входа — есть внутреннее состояние (поля ввода и загрузка)
  final ValueChanged<String> onSignedIn; // final — внешний колбэк, который должен быть неизменным после создания виджета
  const LoginScreen({super.key, required this.onSignedIn}); // конструктор, onSignedIn обязателен, так как без него нельзя продолжить навигацию
  @override
  State<LoginScreen> createState() => _LoginScreenState(); // создаём состояние экрана входа
}
class _LoginScreenState extends State<LoginScreen> { // состояние экрана логина
  final loginCtrl = TextEditingController();  // final — контроллер ввода логина создаётся один раз на жизнь стейта
  final passCtrl = TextEditingController();// final — контроллер ввода пароля также постоянный в рамках этого состояния
  bool loading = false;  // флаг показывает, идёт ли попытка входа
  String? error;  // текст ошибки, если вход не удался
  Future<void> _doLogin() async {  // приватный метод — обработчик кнопки "войти"
    setState(() { // перед началом запроса обновляем состояние
      loading = true; // показываем индикатор загрузки
      error = null; // сбрасываем прежнюю ошибку
    });
    try { // блок try/catch для обработки возможных ошибок сети/базы
      final userId = await SimpleAuth.signIn(loginCtrl.text, passCtrl.text); // вызываем простой вход и получаем id пользователя или null
      if (userId != null) {  // если id есть — вход успешен
        await SimpleAuth.setCurrentUserId(userId); // сохраняем id локально, чтобы помнить сессию
        widget.onSignedIn(userId);  // уведомляем родителя, что вход выполнен, переключаем экран
      } else { // если id не вернулся
        setState(() => error = 'Неверный логин или пароль');  // показываем сообщение об ошибке
      }
    } catch (e) { // если что-то пошло не так на уровне запроса
      setState(() => error = 'Ошибка входа: $e');  // показываем текст ошибки
    } finally { // код, который выполняется в любом случае
      if (mounted) setState(() => loading = false);  // если экран ещё на экране — отключаем индикатор загрузки
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold( // строим разметку экрана входа
    body: Center(  // центрируем содержимое по экрану
      child: ConstrainedBox( // ограничиваем ширину для приятного вида на широких экранах
        constraints: const BoxConstraints(maxWidth: 420), // максимум 420 пикселей по ширине
        child: Padding(  // добавляем отступы
          padding: const EdgeInsets.all(24),  // равномерный внутренний отступ 24
          child: Column(mainAxisSize: MainAxisSize.min, children: [ // вертикальная колонка, по высоте занимает минимально возможное
            const Text('Вход', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)), // заголовок экрана входа
            const SizedBox(height: 16), // вертикальный отступ
            TextField(controller: loginCtrl, decoration: const InputDecoration(labelText: 'Логин (фамилия+инициалы)')), // поле ввода логина с подписью
            const SizedBox(height: 8),// отступ
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Пароль'), obscureText: true), // поле ввода пароля, скрываем ввод
            const SizedBox(height: 16), // отступ
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),  // если есть ошибка — показываем её красным текстом
            const SizedBox(height: 8),// отступ
            ElevatedButton( // кнопка "Войти"
              onPressed: loading ? null : _doLogin,  // блокируем кнопку, пока идёт загрузка, иначе вызываем _doLogin
              child: loading ? const CircularProgressIndicator() : const Text('Войти'),// внутри показываем индикатор или текст
            ),
          ]),
        ),
      ),
    ),
  );
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
        // ===== Лабораторная: демонстрация трёх способов навигации в реальном приложении =====
        Container( // контейнер-карточка в стиле приложения
          padding: const EdgeInsets.all(16), // внутренние отступы
          margin: const EdgeInsets.symmetric(horizontal: 8), // внешний отступ по бокам
          decoration: BoxDecoration( // оформление блока
            color: Theme.of(context).cardColor, // фон берём из текущей темы
            borderRadius: BorderRadius.circular(16), // скругляем углы как в InfoCard/PostCard
          ),
          child: Column( // вертикальное расположение содержимого
            crossAxisAlignment: CrossAxisAlignment.start, // выравниваем текст по левому краю
            children: [
              const Text( // заголовок блока
                'Лабораторная: навигация внутри проекта',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8), // вертикальный отступ
              const Text( // пояснение к блоку
                'Ниже три кнопки показывают три разных подхода навигации:',
              ),
              const SizedBox(height: 12), // отступ
              Wrap( // используем Wrap, чтобы кнопки красиво переносились по строкам
                spacing: 8, // горизонтальный отступ между кнопками
                runSpacing: 8, // вертикальный отступ между строками кнопок
                children: [
                  ElevatedButton( // КНОПКА 1: прямой Navigator.push/pop
                    onPressed: () {
                      // ВАРИАНТ 1: прямой переход через MaterialPageRoute
                      // Открываем экран настроек темы/пользователя как пример
                      Navigator.of(context).push(
                        MaterialPageRoute( // создаём маршрут "на лету"
                          builder: (_) => const SettingsScreen(), // целевой экран
                        ),
                      );
                    },
                    child: const Text('1) Navigator.push/pop'),
                  ),
                  ElevatedButton( // КНОПКА 2: Named Routes
                    onPressed: () {
                      // ВАРИАНТ 2: переход по именованному маршруту
                      // Маршрут '/about' зарегистрирован в MaterialApp.routes
                      Navigator.of(context).pushNamed('/about');
                    },
                    child: const Text('2) Named Routes'),
                  ),
                  ElevatedButton( // КНОПКА 3: GoRouter
                    onPressed: () {
                      // ВАРИАНТ 3: GoRouter как под-модуль
                      // Открываем отдельный экран, внутри которого навигация уже на GoRouter
                      Navigator.of(context).push(
                        MaterialPageRoute( // обычный Navigator твоего приложения
                          builder: (_) => const RouterDemoShell(), // внутри — GoRouter
                        ),
                      );
                    },
                    child: const Text('3) GoRouter'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16), // отступ перед следующим контентом

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
// ============================================================================
// ЭКРАН НАСТРОЕК — демонстрация прямого Navigator.push / pop (способ 1)
// ============================================================================

class SettingsScreen extends StatelessWidget { // экран настроек, открываем напрямую через MaterialPageRoute (Navigator.push)
  const SettingsScreen({super.key}); // конструктор, super.key пробрасываем в базовый StatelessWidget

  @override
  Widget build(BuildContext context) => Scaffold( // Scaffold — стандартный каркас экрана
    appBar: AppBar( // верхняя панель приложения
      title: const Text('Настройки (Navigator.push)'), // заголовок, подчёркиваем способ навигации
    ),
    body: Center( // центрируем содержимое по экрану
      child: Column( // вертикальная колонка элементов
        mainAxisSize: MainAxisSize.min, // колонка занимает минимум по высоте
        children: [
          const Text(
            'Этот экран открыт через прямой Navigator.push(MaterialPageRoute).',
          ), // пояснение к лабораторной
          const SizedBox(height: 16), // отступ
          const Text(
            'Здесь логично показывать настройки темы, профиля и т.п.',
          ), // привязка к реальному приложению
          const SizedBox(height: 24), // отступ
          ElevatedButton(
            onPressed: () => Navigator.pop(context), // возвращаемся назад (pop с текущего экрана)
            child: const Text('Назад'), // подпись на кнопке
          ),
        ],
      ),
    ),
  );
}

// ============================================================================
// ЭКРАН "О ПРИЛОЖЕНИИ" — демонстрация Named Routes (способ 2)
// ============================================================================

class AboutAppScreen extends StatelessWidget { // экран "О приложении", для демонстрации Navigator.pushNamed
  const AboutAppScreen({super.key}); // конструктор со стандартным key

  @override
  Widget build(BuildContext context) => Scaffold( // Scaffold — основа экрана
    appBar: AppBar( // верхняя панель
      title: const Text('О приложении (Named Route)'), // показываем, что мы тут по Named Route
    ),
    body: Center( // содержимое по центру
      child: Column( // вертикальное расположение
        mainAxisSize: MainAxisSize.min, // минимально возможная высота
        crossAxisAlignment: CrossAxisAlignment.center, // выравнивание по центру
        children: [
          const Text(
            'Этот экран открыт через Navigator.pushNamed(context, \'/about\').',
          ), // пояснение, что это пример Named Route
          const SizedBox(height: 12), // отступ
          const Text(
            'Используем routes в MaterialApp для централизованной конфигурации.',
          ), // пояснение преимущества
          const SizedBox(height: 24), // отступ
          ElevatedButton(
            onPressed: () => Navigator.pop(context), // закрываем экран по pop()
            child: const Text('Назад'), // подпись
          ),
        ],
      ),
    ),
  );

// ============================================================================
// ДЕМОНСТРАЦИЯ GoRouter — способ 3 (продвинутая навигация)
// Важно: мы не ломаем текущее приложение, а встраиваем отдельный "под-модуль".
// Он открывается из HomeScreen через обычный Navigator.push,
// а внутри уже работает GoRouter со своими путями.
// ============================================================================

// Конфигурация GoRouter для демонстрационного модуля
  final GoRouter _demoRouter = GoRouter( // создаём экземпляр GoRouter
    routes: [ // список маршрутов внутри демо-модуля
      GoRoute( // первый маршрут — "главный" экран демо
        path: '/', // корневой путь внутри этого под-приложения
        builder: (_, __) => const RouterDemoHomeScreen(), // экран со списком кнопок
      ),
      GoRoute( // второй маршрут
        path: '/feed', // путь для "ленты"
        builder: (_, __) => const RouterDemoFeedScreen(), // экран-демо ленты
      ),
      GoRoute( // третий маршрут
        path: '/profile', // путь для профиля
        builder: (_, __) => const RouterDemoProfileScreen(), // экран-демо профиля
      ),
    ],
  );

// Обёртка над GoRouter, которую мы открываем из основного приложения
  class RouterDemoShell extends StatelessWidget { // отдельный виджет-оболочка для GoRouter
  const RouterDemoShell({super.key}); // стандартный конструктор

  @override
  Widget build(BuildContext context) { // строим вложенный MaterialApp.router
  return MaterialApp.router( // отдельный MaterialApp для демо-модуля
  debugShowCheckedModeBanner: false, // убираем надпись DEBUG
  routerConfig: _demoRouter, // передаём нашу конфигурацию GoRouter
  );
  }
  }

// Главный экран демо GoRouter
  class RouterDemoHomeScreen extends StatelessWidget { // стартовый экран демо-навигации на GoRouter
  const RouterDemoHomeScreen({super.key}); // конструктор

  @override
  Widget build(BuildContext context) => Scaffold( // Scaffold стандартный
  appBar: AppBar( // верхняя панель
  title: const Text('GoRouter демо'), // заголовок
  leading: IconButton( // левая кнопка в AppBar
  icon: const Icon(Icons.close), // иконка "крестик"
  onPressed: () {
  // Закрываем весь демо-модуль и возвращаемся в основное приложение
  Navigator.of(context).pop(); // выходим из RouterDemoShell
  },
  ),
  ),
  body: Center( // содержимое по центру
  child: Column( // вертикальная колонка
  mainAxisSize: MainAxisSize.min, // минимальная высота
  children: [
  const Text(
  'Внутри этого экрана маршрутизация управляется GoRouter.',
  ), // пояснение
  const SizedBox(height: 16), // отступ
  ElevatedButton(
  onPressed: () {
  // Переход на экран "ленты" через GoRouter
  context.push('/feed'); // используем context.push из go_router
  },
  child: const Text('Перейти на экран ленты (/feed)'),
  ),
  ElevatedButton(
  onPressed: () {
  // Переход на экран "профиля"
  context.push('/profile'); // тоже через GoRouter
  },
  child: const Text('Перейти на экран профиля (/profile)'),
  ),
  ],
  ),
  ),
  );
  }

// Экран "ленты" в демо GoRouter
  class RouterDemoFeedScreen extends StatelessWidget { // демонстрационный экран
  const RouterDemoFeedScreen({super.key}); // конструктор

  @override
  Widget build(BuildContext context) => Scaffold(
  appBar: AppBar( // верхняя панель
  title: const Text('GoRouter: Лента'), // заголовок
  ),
  body: Center( // содержимое по центру
  child: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
  const Text('Это демонстрационный экран "ленты" внутри GoRouter.'), // пояснение
  const SizedBox(height: 16),
  ElevatedButton(
  onPressed: () => context.pop(), // возвращаемся на RouterDemoHomeScreen
  child: const Text('Назад'),
  ),
  ],
  ),
  ),
  );
  }

// Экран "профиля" в демо GoRouter
  class RouterDemoProfileScreen extends StatelessWidget { // ещё один демонстрационный экран
  const RouterDemoProfileScreen({super.key}); // конструктор

  @override
  Widget build(BuildContext context) => Scaffold(
  appBar: AppBar( // верхняя панель
  title: const Text('GoRouter: Профиль'), // заголовок
  ),
  body: Center(
  child: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
  const Text('Это демонстрационный экран "профиля" внутри GoRouter.'), // пояснение
  const SizedBox(height: 16),
  ElevatedButton(
  onPressed: () => context.pop(), // назад к RouterDemoHomeScreen
  child: const Text('Назад'),
  ),
  ],
  ),
  ),
  );
