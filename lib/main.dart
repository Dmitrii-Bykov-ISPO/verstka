import 'package:flutter/material.dart'; // подключаем flutter ui-библиотеку, без неё виджеты и темы недоступны
import 'package:shared_preferences/shared_preferences.dart'; // подключаем хранилище простых настроек на устройстве (key-value)
import 'package:supabase_flutter/supabase_flutter.dart'; // подключаем клиент supabase для работы с бэкендом, базой и хранилищем
import 'package:table_calendar/table_calendar.dart'; // календарь
import 'package:postgrest/postgrest.dart'; // типы билдера запросов для корректной типизации gte/lte

import 'package:file_picker/file_picker.dart'; // кроссплатформенный выбор любых файлов
import 'dart:typed_data'; // для Uint8List (web и mobile)
import 'dart:io' show File; // для чтения файла на mobile/desktop
import 'package:flutter/foundation.dart' show kIsWeb; // чтобы различать web и всё остальное

// supabase: базовая конфигурация и клиент
const String supabaseUrl = 'https://azccbwduobbulgdgucjj.supabase.co'; // const потому что это неизменяемый адрес проекта supabase, он известен на этапе компиляции
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF6Y2Nid2R1b2JidWxnZGd1Y2pqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk4MDUyNzgsImV4cCI6MjA3NTM4MTI3OH0.x9jEzJnHg_fiX0dFXpWD70kKH848QZC4uELlMpL1yos';
// const потому что публичный ключ авторизации "anon" тоже фиксирован и не меняется во время работы приложения
// PUBLIC бакеты
const String postBucketName = 'post-images'; // тут имя бакета в storage supabase для фотографий постов, const так как это постоянное строковое значение
const String avatarsBucketName = 'avatars';// тут имя бакета для аватаров пользователей, const по той же причине — это константный идентификатор
const String eventImagesBucketName = 'event-images'; // бакет картинок событий
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

    if (mode == 'none') { // без 2FA — оставляем созданную сессию
      return _TwoFactorPlan.none(user.id);
    }
    //2FA Email
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

  _TwoFactorPlan(this.userId, this.kind, this.target);

  factory _TwoFactorPlan.none(String userId) =>
      _TwoFactorPlan(userId, _TwoFactorKind.none, null);

  factory _TwoFactorPlan.email(String userId, String email) =>
      _TwoFactorPlan(userId, _TwoFactorKind.email, email);
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

//Events
class EventModel { // модель события для UI
  final String id; // id события
  final String title; // название
  final String? description; // описание
  final String? place; // место
  final String? imagePath; // относительный путь в bucket event-images
  final DateTime startAt; // начало
  final DateTime endAt; // конец
  final String? createdBy; // uid автора (может быть null у системных)
  final bool isSystem; // флаг системного события
  final int attendees; // количество участников
  final bool iAmJoined; // я записан?
  final bool iAmOwner; // я автор?

  const EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.place,
    required this.imagePath,
    required this.startAt,
    required this.endAt,
    required this.createdBy,
    required this.isSystem,
    required this.attendees,
    required this.iAmJoined,
    required this.iAmOwner,
  });

  String? get coverUrl => // публичный URL обложки события
  imagePath == null || imagePath!.isEmpty
      ? null
      : publicUrl(bucket: eventImagesBucketName, objectKey: imagePath!);
}

// маленькая модель для счётчика событий пользователя
class MyEventsStats { // класс вместо записи (record), совместим с Dart 2/3
  final int total; // всего событий
  final bool hasToday; // есть ли событие сегодня
  const MyEventsStats(this.total, this.hasToday); // конструктор
}

class EventsRepository { // инкапсулирует чтение/запись событий
  final SupabaseClient supa; // клиент supabase
  EventsRepository(this.supa); // конструктор

  String? get _uid => supa.auth.currentUser?.id; // мой uid (или null)

  // Загрузить события в диапазоне дат (для календаря) либо все будущие (для списка)
  Future<List<EventModel>> loadEvents({DateTime? from, DateTime? to}) async {
    // ВАЖНО: типизируем как PostgrestFilterBuilder, чтобы дальше были доступны gte/lte
    PostgrestFilterBuilder<dynamic> q = supa
        .from('events')
        .select(
        'id,title,description,place,image_path,start_at,end_at,created_by,is_system,'
            'event_attendees!left(user_id)');

    if (from != null) {
      q = q.gte('start_at', from.toIso8601String()); // фильтр от
    }
    if (to != null) {
      q = q.lte('start_at', to.toIso8601String()); // фильтр до
    }

    final rows = await q.order('start_at'); // сортировка и выполнение

    return (rows as List).map<EventModel>((r) {
      final attendees = (r['event_attendees'] as List?) ?? []; // список участников
      final cnt = attendees.length; // количество участников
      final me = _uid;
      final iAmJoined = me != null && attendees.any((a) => a['user_id'] == me); // записан ли я
      final owner = r['created_by'] as String?; // автор
      final iAmOwner = me != null && me == owner; // я автор?
      return EventModel( // собираем модель
        id: r['id'] as String,
        title: (r['title'] ?? '') as String,
        description: r['description'] as String?,
        place: r['place'] as String?,
        imagePath: r['image_path'] as String?,
        startAt: DateTime.parse(r['start_at'] as String),
        endAt: DateTime.parse(r['end_at'] as String),
        createdBy: owner,
        isSystem: (r['is_system'] ?? false) as bool,
        attendees: cnt,
        iAmJoined: iAmJoined,
        iAmOwner: iAmOwner,
      );
    }).toList();
  }

  // Счётчик событий пользователя и флажок "есть сегодня?"
  Future<MyEventsStats> myStats() async {
    final uid = _uid;
    if (uid == null) return const MyEventsStats(0, false); // если не залогинен — ничего

    final now = DateTime.now(); // текущее время
    final dayStart = DateTime(now.year, now.month, now.day); // начало дня
    final dayEnd = dayStart.add(const Duration(days: 1)); // конец дня

    // всего, где я участник (берём id и считаем длину ответа)
    final totalRows = await supa
        .from('event_attendees')
        .select('event_id')
        .eq('user_id', uid);
    final total = (totalRows as List).length; // всего

    // есть ли событие сегодня (inner join с участниками)
    final todayRows = await supa
        .from('events')
        .select('id, event_attendees!inner(user_id)')
        .gte('start_at', dayStart.toIso8601String())
        .lt('start_at', dayEnd.toIso8601String())
        .eq('event_attendees.user_id', uid);
    final hasToday = (todayRows as List).isNotEmpty; // на сегодня есть?

    return MyEventsStats(total, hasToday); // возвращаем объект
  }

  // Создать событие (обычный пользователь; is_system = false)
  Future<String> createEvent({
    required String title, // проверка на непусто
    required DateTime startAt, // начало
    required DateTime endAt, // конец
    String? description, // описание
    String? place, // место
    String? imagePath, // относительный путь в бакете event-images
  }) async {
    if (title.trim().isEmpty) throw Exception('Введите название'); // валидация
    if (!endAt.isAfter(startAt)) throw Exception('Окончание должно быть позже начала'); // валидация: строго >

    final row = await supa
        .from('events')
        .insert({
      'title': title.trim(),
      'description': (description ?? '').trim().isEmpty ? null : description,
      'place': (place ?? '').trim().isEmpty ? null : place,
      'image_path': (imagePath ?? '').trim().isEmpty ? null : imagePath,
      'start_at': startAt.toIso8601String(),
      'end_at': endAt.toIso8601String(),
      'created_by': _uid, // автор = текущий пользователь
      'is_system': false, // обычное событие
    })
        .select('id')
        .single(); // получаем id

    return row['id'] as String; // возвращаем id события
  }

  // Записаться на событие
  Future<void> joinEvent(String eventId) async {
    final uid = _uid;
    if (uid == null) throw Exception('Не авторизован');
    await supa.from('event_attendees').insert({
      'event_id': eventId, // id события
      'user_id': uid, // я (не null)
    });
  }

  // Отказаться (если не автор и событие не началось — RLS это проверит)
  Future<void> leaveEvent(String eventId) async {
    final uid = _uid;
    if (uid == null) throw Exception('Не авторизован');
    await supa
        .from('event_attendees')
        .delete()
        .match({'event_id': eventId, 'user_id': uid}); // удаляем мою запись (uid non-null)
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
  int myEventsCount = 0; // сколько событий у пользователя
  bool hasTodayEvent = false; // есть ли событие сегодня
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
      final statsRepo = EventsRepository(supabase); // создаём репозиторий событий
      final stats = await statsRepo.myStats(); // получаем объект со статистикой
      myEventsCount = stats.total; // количество
      hasTodayEvent = stats.hasToday; // флажок на сегодня
    } finally {  // выполняется в любом случае — и при успехе, и при ошибке
      if (mounted) setState(() => loading = false);  // выключаем индикатор, если экран ещё смонтирован
    }
  }

  String _timeAgo(DateTime dt) {  // преобразует дату создания поста в "н минут/часов/дней назад"
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

  void _openEvents() { // открыть экран событий
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventsScreen()));
  }

  @override
  Widget build(BuildContext context) {// строим визуальную часть главного экрана
    final list = loading// если идёт загрузка
        ? const Center(child: CircularProgressIndicator())// показываем крутилку по центру
        : ListView( // иначе рисуем список
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),// отступы вокруг списка
      children: [// элементы списка
        Row(children: [
          const Expanded(child: InfoCard(icon: Icons.notifications, iconColor: Colors.yellow, title: '10 новостей')),// карточка "новости"
          Expanded(
            child: Stack( // чтобы нарисовать красную точку поверх
              children: [
                // карточка "события" с динамическим цветом и числом
                InfoCard(
                  icon: Icons.event,
                  iconColor: myEventsCount > 0 ? Colors.green : Colors.grey, // зелёный если >0, иначе серый
                  title: '$myEventsCount событ${myEventsCount == 1 ? "ие" : (myEventsCount>=2 && myEventsCount<=4 ? "ия" : "ий")}', // русское склонение
                ),
                if (hasTodayEvent) // если есть событие сегодня
                  Positioned( // рисуем красную точку справа-сверху
                    right: 12, // отступ справа
                    top: 8, // отступ сверху
                    child: Container(
                      width: 10, height: 10, // размер точки
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), // красный кружок
                    ),
                  ),
                // делаем всю карточку кликабельной — откроем экран событий
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(onTap: _openEvents), // тап по карточке
                  ),
                ),
              ],
            ),
          ),
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
              IconButton(icon: const Icon(Icons.event), onPressed: _openEvents), // новая кнопка "События"
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
  final String? imageAsset; // путь/ссылка на изображение (optional)
  final Uint8List? imageBytes; //bytes для предпросмотра до загрузки
  const PhotoViewScreen({super.key, this.imageAsset, this.imageBytes}); // конструктор принимает опциональные параметры

  bool get _hasUrl => (imageAsset ?? '').isHttpUrl || (imageAsset != null && imageAsset!.isNotEmpty);

  @override
  Widget build(BuildContext context) { // строим интерфейс просмотра
    final child = Builder(builder: (_) {
      if (imageBytes != null) { // если переданы байты — показываем их
        return Center(child: InteractiveViewer(child: Image.memory(imageBytes!, fit: BoxFit.contain)));
      }
      if (!_hasUrl) { // если ничего не передали
        return const Center(child: Text('Нет изображения', style: TextStyle(color: Colors.white))); // показываем сообщение
      }
      final isUrl = (imageAsset ?? '').isHttpUrl;// проверяем, является ли строка http/https url
      return Center(child: InteractiveViewer(child: isUrl ? Image.network(imageAsset!, fit: BoxFit.contain) : Image.asset(imageAsset!, fit: BoxFit.contain))); // иначе показываем картинку с возможностью зума
    });

    return Scaffold( // каркас экрана
      backgroundColor: Colors.black, // тёмный фон для фото
      appBar: AppBar( //только кнопка "Назад" через AppBar; без "Домой"
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Назад',
        ),
      ),
      body: SafeArea(child: child),
    );
  }
}

class EventsScreen extends StatefulWidget { // экран событий
  const EventsScreen({super.key}); // конструктор без параметров
  @override
  State<EventsScreen> createState() => _EventsScreenState(); // состояние экрана
}

class _EventsScreenState extends State<EventsScreen> {
  late final EventsRepository repo; // репозиторий событий
  bool asCalendar = false; // режим отображения: список/календарь
  DateTime focusedDay = DateTime.now(); // текущий день в календаре
  List<EventModel> events = []; // события, загруженные из БД
  bool loading = true; // флаг загрузки
  String? error; // текст ошибки

  @override
  void initState() {
    super.initState(); // базовая инициализация
    repo = EventsRepository(supabase); // создаём репозиторий
    _load(); // первая загрузка
  }

  Future<void> _load() async { // загрузка событий
    setState(() { loading = true; error = null; }); // включаем индикатор, сбрасываем ошибку
    try {
      // если календарь — грузим только ближние месяцы вокруг focusedDay, иначе — будущее
      final from = asCalendar
          ? DateTime(focusedDay.year, focusedDay.month - 1, 1)
          : DateTime.now().subtract(const Duration(days: 1)); // для списка берём всё будущее
      final to = asCalendar
          ? DateTime(focusedDay.year, focusedDay.month + 2, 0)
          : null;

      events = await repo.loadEvents(from: from, to: to); // тянем события
    } catch (e) {
      error = 'Не удалось загрузить события: $e'; // сохраняем ошибку
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор
    }
  }

  Future<void> _join(String id) async { // записаться
    try {
      await repo.joinEvent(id); // пишем в БД
      await _load(); // обновляем список
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы записались')));
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка записи: $e')));
    }
  }

  Future<void> _leave(String id) async { // отказаться
    try {
      await repo.leaveEvent(id); // удаляем запись
      await _load(); // обновляем список
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы отказались от участия')));
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка отказа: $e')));
    }
  }

  Widget _modeSwitch() => Row( // переключатель режимов
    mainAxisAlignment: MainAxisAlignment.end, // прижимаем вправо
    children: [
      const Text('Список'), // подпись
      Switch( // сам переключатель
        value: asCalendar, // текущее значение
        onChanged: (v) async { // обработчик
          setState(() { asCalendar = v; }); // меняем режим
          await _load(); // перезагружаем данные
        },
      ),
      const Text('Календарь'), // подпись
    ],
  );

  @override
  Widget build(BuildContext context) {
    final body = loading // если идёт загрузка
        ? const Center(child: CircularProgressIndicator()) // показываем индикатор
        : error != null // если ошибка
        ? Center(child: Text(error!, style: const TextStyle(color: Colors.red))) // показываем ошибку
        : asCalendar // если режим календаря
        ? _calendar() // показываем календарь
        : _list(); // иначе список

    return Scaffold(
      appBar: AppBar(title: const Text('События')), // заголовок
      body: Padding( // контент с отступами
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _modeSwitch(), // переключатель
            const SizedBox(height: 8), // отступ
            Expanded(child: body), // основной контент
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton( // кнопка "создать"
        onPressed: _openCreateEvent, // открываем форму создания
        child: const Icon(Icons.add), // плюсик
      ),
    );
  }

  Widget _list() => ListView.separated( // список событий
    itemCount: events.length, // количество
    separatorBuilder: (_, __) => const SizedBox(height: 8), // отступы
    itemBuilder: (_, i) => EventTile( // одна карточка
      e: events[i], // модель события
      onJoin: () => _join(events[i].id), // записаться
      onLeave: () => _leave(events[i].id), // отказаться
      onOpen: () => _openDetails(events[i]), // открыть детали
    ),
  );

  Widget _calendar() { // вид календаря
    // группируем события по датам
    final byDay = <DateTime, List<EventModel>>{}; // словарь дата -> список событий
    for (final e in events) { // пробегаем все события
      final d = DateTime(e.startAt.year, e.startAt.month, e.startAt.day); // только дата
      byDay.putIfAbsent(d, () => []).add(e); // добавляем в список дня
    }

    final selectedDay = DateTime(focusedDay.year, focusedDay.month, focusedDay.day); // нормализованная выбранная дата
    final ofDay = byDay[selectedDay] ?? const <EventModel>[]; // события конкретного дня

    return Column(
      children: [
        TableCalendar<EventModel> ( // сам календарь
          firstDay: DateTime.utc(2020,1,1), // минимальная дата
          lastDay: DateTime.utc(2035,12,31), // максимальная дата
          focusedDay: focusedDay, // текущая фокус-дата
          eventLoader: (day) { // функция: какие события у даты
            final d = DateTime(day.year, day.month, day.day); // нормализуем
            return byDay[d] ?? const []; // возвращаем список или пусто
          },
          calendarFormat: CalendarFormat.month, // формат "месяц"
          onPageChanged: (fd) async { // при перелистывании месяцев
            focusedDay = fd; // обновляем фокус
            await _load(); // подгружаем события для нового месяца
          },
          selectedDayPredicate: (d) => DateTime(d.year, d.month, d.day) == selectedDay, // выделяем выбранный день
          onDaySelected: (sel, foc) => setState(() => focusedDay = foc), // кликом меняем выбранную дату
        ),
        const SizedBox(height: 8), // отступ
        Expanded( // ниже список событий текущего дня
          child: ListView(
            children: ofDay
                .map((e) => EventTile( // карточки событий выбранного дня
              e: e,
              onJoin: () => _join(e.id),
              onLeave: () => _leave(e.id),
              onOpen: () => _openDetails(e),
            ))
                .toList(),
          ),
        ),
      ],
    );
  }

  void _openDetails(EventModel e) { // открыть экран деталей
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailsScreen(event: e)));
  }

  Future<void> _openCreateEvent() async { // открыть форму создания
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CreateEventScreen()));
    if (created == true) { // если вернулись с флагом "создано"
      await _load(); // перезагружаем события
    }
  }
}
class EventTile extends StatelessWidget { // карточка события в списке
  final EventModel e; // само событие
  final VoidCallback onJoin; // обработчик "записаться"
  final VoidCallback onLeave; // обработчик "отказаться"
  final VoidCallback onOpen; // обработчик "детали"
  const EventTile({super.key, required this.e, required this.onJoin, required this.onLeave, required this.onOpen});

  static String _fmt(DateTime dt) { // формат "дд.мм чч:мм"
    final d = dt.day.toString().padLeft(2,'0'); // день
    final m = dt.month.toString().padLeft(2,'0'); // месяц
    final hh = dt.hour.toString().padLeft(2,'0'); // часы
    final mm = dt.minute.toString().padLeft(2,'0'); // минуты
    return '$d.$m $hh:$mm'; // итог
  }

  @override
  Widget build(BuildContext context) {
    final started = DateTime.now().isAfter(e.startAt); // уже началось?
    final canLeave = !started && !e.iAmOwner && e.iAmJoined; // можно отказаться?
    final canJoin = !started && !e.iAmJoined; // можно записаться?
    final cover = e.coverUrl; // обложка

    // мини-превью обложки: фиксированное соотношение 1:1 (квадрат) и ClipRRect — чтобы не растягивалось
    final coverWidget = cover != null
        ? GestureDetector( // по тапу открываем на весь экран
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewScreen(imageAsset: cover))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1, // квадрат — как мини-иконка события
          child: Image.network(cover, fit: BoxFit.cover),
        ),
      ),
    )
        : const Icon(Icons.event, size: 48); // иконка по умолчанию

    return InkWell( // кликабельная карточка
      onTap: onOpen, // открываем детали
      child: Container(
        padding: const EdgeInsets.all(12), // внутренние отступы
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, // фон карточки
          borderRadius: BorderRadius.circular(16), // скругления
        ),
        child: Row(
          children: [
            SizedBox(width: 72, height: 72, child: coverWidget), //фиксируем контейнер, внутри — AspectRatio
            const SizedBox(width: 12), // отступ
            Expanded( // текстовая часть
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold)), // название
                const SizedBox(height: 4), // отступ
                Text('${_fmt(e.startAt)} — ${_fmt(e.endAt)}'), // время
                if ((e.place ?? '').isNotEmpty) Text(e.place!), // место
                Text('Участников: ${e.attendees}'), // количество
              ]),
            ),
            const SizedBox(width: 8), // отступ
            Column( // кнопки действий
              children: [
                if (canJoin)
                  TextButton(onPressed: onJoin, child: const Text('Записаться')),
                if (canLeave)
                  TextButton(onPressed: onLeave, child: const Text('Отказаться')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EventDetailsScreen extends StatelessWidget { // экран деталей события
  final EventModel event; // событие
  const EventDetailsScreen({super.key, required this.event}); // конструктор

  @override
  Widget build(BuildContext context) {
    final cover = event.coverUrl; // ссылка на обложку
    return Scaffold(
      appBar: AppBar(title: Text(event.title)), // заголовок
      body: ListView(
        padding: const EdgeInsets.all(16), // отступы
        children: [
          if (cover != null) // большая обложка
            GestureDetector( // тап по обложке -> полный экран
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewScreen(imageAsset: cover))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9, //аккуратная обложка 16:9, без "растягивания"
                  child: Image.network(cover, fit: BoxFit.cover),
                ),
              ),
            ),
          const SizedBox(height: 12), // отступ
          Text('${EventTile._fmt(event.startAt)} — ${EventTile._fmt(event.endAt)}',
              style: const TextStyle(fontWeight: FontWeight.bold)), // время
          if ((event.place ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.place, size: 16),
              const SizedBox(width: 4),
              Flexible(child: Text(event.place!)),
            ]),
          ],
          const SizedBox(height: 12),
          Text(event.description ?? 'Без описания'), // описание
          const SizedBox(height: 12),
          Text('Участников: ${event.attendees}'), // количество участников
        ],
      ),
    );
  }
}

class CreateEventScreen extends StatefulWidget { // экран создания события
  const CreateEventScreen({super.key}); // конструктор
  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState(); // состояние
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final titleCtrl = TextEditingController(); // заголовок
  final descCtrl = TextEditingController(); // описание
  final placeCtrl = TextEditingController(); // место
  final imageCtrl = TextEditingController(); // относительный путь в bucket (заполняется автоматически после загрузки)
  DateTime startAt = DateTime.now().add(const Duration(hours: 2)); // дефолт
  DateTime endAt   = DateTime.now().add(const Duration(hours: 3)); // дефолт
  bool loading = false; // индикатор
  String? error; // ошибка
  late final EventsRepository repo; // репозиторий

  Uint8List? _pickedBytes; // байты выбранного файла (web и mobile)
  String? _pickedName; // исходное имя файла (для расширения/превью)

  @override
  void initState() {
    super.initState(); // базовая инициализация
    repo = EventsRepository(supabase); // создаём репозиторий
  }

  // утилита: является ли выбранный файл картинкой (по расширению)
  bool get _pickedIsImage {
    final name = (_pickedName ?? '').toLowerCase();
    return name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.gif') || name.endsWith('.webp');
  }

  // выбрать файл в любом формате
  Future<void> _pickFile() async { // диалог выбора
    final res = await FilePicker.platform.pickFiles( // открываем системный пикер
      allowMultiple: false, // один файл
      type: FileType.any, // любой формат
      withData: kIsWeb, // на web берём bytes сразу
    );
    if (res == null || res.files.isEmpty) return; // пользователь отменил
    final f = res.files.single; // выбранный файл

    Uint8List? bytes = f.bytes; // web — уже здесь
    if (bytes == null && f.path != null && !kIsWeb) { // mobile/desktop — читаем из пути
      bytes = await File(f.path!).readAsBytes();
    }
    if (bytes == null) { // перестраховка
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось прочитать файл')));
      }
      return;
    }

    setState(() {
      _pickedBytes = bytes; // сохраняем байты
      _pickedName = f.name; // имя файла (для расширения и отображения)
      // НЕ заполняем imageCtrl — это только после реальной загрузки в бакет (ниже)
    });
  }

  //  загрузить выбранный файл в бакет и подставить objectKey в форму
  Future<void> _uploadPickedFile() async {
    if (_pickedBytes == null) { // если файл не выбран
      await _pickFile(); // предлагаем выбрать
      if (_pickedBytes == null) return; // опять нет — выходим
    }
    setState(() { loading = true; error = null; }); // индикатор

    try {
      // вытаскиваем расширение из имени, по умолчанию bin
      String ext = 'bin';
      final name = (_pickedName ?? '').trim();
      final dot = name.lastIndexOf('.');
      if (dot > 0 && dot < name.length - 1) {
        ext = name.substring(dot + 1).toLowerCase();
      }

      // формируем уникальный objectKey: <userId>/<timestamp>.<ext>
      final uid = supabase.auth.currentUser?.id ?? 'anon';
      final objectKey = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext'; // относительный путь внутри бакета

      // загружаем в storage (upsert разрешаем — чтобы можно было перезалить при одинаковом ключе)
      await supabase.storage
          .from(eventImagesBucketName)
          .uploadBinary(objectKey, _pickedBytes!,
          fileOptions: const FileOptions(upsert: true)); // contentType можно не указывать — Supabase сам попытается определить

      // кладём путь в поле формы и рисуем предпросмотр
      setState(() {
        imageCtrl.text = objectKey; // теперь этот путь сохранится в events.image_path
      });

      // подсказка пользователю
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Картинка загружена')));
    } catch (e) {
      setState(() => error = 'Ошибка загрузки: $e'); // показываем ошибку
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор
    }
  }

  //  локальная проверка валидности дат (строго начало < окончание)
  bool get _datesValid => endAt.isAfter(startAt);

  Future<void> _submit() async { // отправка формы
    setState(() { loading = true; error = null; }); // включаем индикатор
    try {
      if (!_datesValid) { // защитимся до похода в сеть
        throw Exception('Дата/время окончания должны быть ПОЗЖЕ даты/времени начала');
      }
      await repo.createEvent( // создаём событие
        title: titleCtrl.text,
        description: descCtrl.text,
        place: placeCtrl.text,
        imagePath: imageCtrl.text, // сохраняем относительный путь в БД (если он не пуст)
        startAt: startAt,
        endAt: endAt,
      );
      if (mounted) Navigator.of(context).pop(true); // возвращаемся с флагом "создано"
    } catch (e) {
      setState(() => error = '$e'); // показываем ошибку
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор
    }
  }

  // виджет мини-превью как в списках событий
  Widget _asListPreview() {
    final cover = imageCtrl.text.trim().isNotEmpty
        ? publicUrl(bucket: eventImagesBucketName, objectKey: imageCtrl.text.trim())
        : null;

    final fake = EventModel( // собираем временную модель для превью
      id: 'preview',
      title: (titleCtrl.text.isEmpty ? 'Название события' : titleCtrl.text),
      description: descCtrl.text.isEmpty ? null : descCtrl.text,
      place: placeCtrl.text.isEmpty ? null : placeCtrl.text,
      imagePath: imageCtrl.text.isEmpty ? null : imageCtrl.text,
      startAt: startAt,
      endAt: endAt,
      createdBy: null,
      isSystem: false,
      attendees: 12,
      iAmJoined: false,
      iAmOwner: false,
    );

    return IgnorePointer( // чтобы превью не кликалось (показываем вид)
      ignoring: true,
      child: EventTile(
        e: fake,
        onJoin: () {},
        onLeave: () {},
        onOpen: () {},
      ),
    );
  }

  //  полноэкранное открытие выбранной (ещё не загруженной) картинки
  void _openPickedFull() {
    if (_pickedBytes != null && _pickedIsImage) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewScreen(imageBytes: _pickedBytes)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Новое событие')), // заголовок
    body: ListView(
      padding: const EdgeInsets.all(16), // отступы
      children: [
        TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Название*')), // заголовок
        const SizedBox(height: 8),
        TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Описание')), // описание
        const SizedBox(height: 8),
        TextField(controller: placeCtrl, decoration: const InputDecoration(labelText: 'Место проведения')), // место
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: imageCtrl,
              readOnly: true, // путь формируется автоматически после загрузки
              decoration: const InputDecoration(
                labelText: 'Картинка (загрузите любой формат)',
                helperText: 'Файл попадёт в bucket event-images, здесь — относительный путь',
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon( // кнопка выбора файла
            icon: const Icon(Icons.attach_file),
            label: Text(_pickedName == null ? 'Выбрать файл' : 'Выбрано: $_pickedName'),
            onPressed: loading ? null : _pickFile,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon( // кнопка загрузки в бакет
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Загрузить в бакет'),
            onPressed: loading ? null : _uploadPickedFile,
          ),
        ]),

        // предпросмотр локально выбранного файла (до загрузки): если изображение — покажем картинку, иначе — иконку файла
        if (_pickedBytes != null) ...[
          const SizedBox(height: 12),
          Text('Предпросмотр выбранного файла (до загрузки):', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _openPickedFull, //  тап по предпросмотру — фуллскрин
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Theme.of(context).cardColor,
                padding: const EdgeInsets.all(8),
                child: _pickedIsImage
                    ? Image.memory(_pickedBytes!, height: 160, fit: BoxFit.cover)
                    : Row(
                  children: [
                    const Icon(Icons.insert_drive_file, size: 32),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_pickedName ?? 'файл')),
                  ],
                ),
              ),
            ),
          ),
        ],

        // предпросмотр загруженной обложки (через публичный URL)
        if (imageCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Загруженная обложка (публичный URL):', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          GestureDetector( // клик по превью — открываем фуллскрин
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PhotoViewScreen(
                  imageAsset: publicUrl(bucket: eventImagesBucketName, objectKey: imageCtrl.text.trim()),
                ))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9, // аккуратная "обложка" 16:9
                child: Image.network(
                  publicUrl(bucket: eventImagesBucketName, objectKey: imageCtrl.text.trim()),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 16),
        // мини-превью "как карточка в списке событий"
        Text('Как это будет выглядеть в списке событий:', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        _asListPreview(),

        const SizedBox(height: 12),
        // выбор дат/времени простыми кнопками (можно заменить на любой date/time picker)
        Row(children: [
          Expanded(child: Text('Начало: ${EventTile._fmt(startAt)}')), // показываем выбранное начало
          TextButton(
            onPressed: () async { // выбираем дату начала
              final now = DateTime.now(); // текущая дата
              final picked = await showDatePicker( // диалог выбора даты
                context: context,
                initialDate: startAt,
                firstDate: DateTime(now.year-1),
                lastDate: DateTime(now.year+2),
              );
              if (picked != null) { // если выбранная дата не null
                setState(() => startAt = DateTime(picked.year, picked.month, picked.day, startAt.hour, startAt.minute));
              }
            },
            child: const Text('Дата'),
          ),
          TextButton(
            onPressed: () async { // выбираем время начала
              final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(startAt));
              if (picked != null) { // если выбрано
                setState(() => startAt = DateTime(startAt.year, startAt.month, startAt.day, picked.hour, picked.minute));
              }
            },
            child: const Text('Время'),
          ),
        ]),
        Row(children: [
          Expanded(child: Text('Окончание: ${EventTile._fmt(endAt)}')), // показываем выбранное окончание
          TextButton(
            onPressed: () async { // выбираем дату окончания
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: endAt,
                firstDate: DateTime(now.year-1),
                lastDate: DateTime(now.year+2),
              );
              if (picked != null) {
                setState(() => endAt = DateTime(picked.year, picked.month, picked.day, endAt.hour, endAt.minute));
              }
            },
            child: const Text('Дата'),
          ),
          TextButton(
            onPressed: () async { // выбираем время окончания
              final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(endAt));
              if (picked != null) {
                setState(() => endAt = DateTime(endAt.year, endAt.month, endAt.day, picked.hour, picked.minute));
              }
            },
            child: const Text('Время'),
          ),
        ]),

        // подсказка валидности дат (UI)
        if (!_datesValid) ...[
          const SizedBox(height: 6),
          const Text(
            '⚠️ Дата/время окончания должны быть ПОЗЖЕ даты/времени начала',
            style: TextStyle(color: Colors.red),
          ),
        ],

        const SizedBox(height: 12),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)), // показываем ошибку
        const SizedBox(height: 8),
        ElevatedButton( // кнопка "создать"
          onPressed: (loading || !_datesValid) ? null : _submit, // выключаем при загрузке и при неверных датах
          child: loading ? const CircularProgressIndicator() : const Text('Создать'),
        ),
      ],
    ),
  );
}
