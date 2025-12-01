import 'package:supabase_flutter/supabase_flutter.dart'; // SupabaseClient
import 'package:postgrest/postgrest.dart'; // PostgrestFilterBuilder типы (на будущее, если нужно)
import '../../core/app_services.dart'; // publicUrl, postBucketName, avatarsBucketName, LetX, StringX
import '../../models/user_model.dart'; // UserModel

class PostModel { // модель поста с полями автора и медиа
  // модель поста с полями автора и медиа
  final String id; // id поста
  final String authorId; // id автора
  final String authorLogin; // логин автора
  final String authorName; // имя автора
  final String? authorAvatarUrl; // url аватарки автора
  final DateTime createdAt; // время создания
  final String text; // текст поста
  final List<String> imageUrls; // список url картинок

  const PostModel({
    required this.id, // обязательный id
    required this.authorId, // обязательный id автора
    required this.authorLogin, // логин автора
    required this.authorName, // имя/ФИО автора
    required this.authorAvatarUrl, // ссылка на аватар (может быть null)
    required this.createdAt, // дата создания
    required this.text, // текст поста
    required this.imageUrls, // список ссылок на картинки
  });
}

class PostsRepository { // репозиторий инкапсулирует всю логику чтения постов и связанных данных
  final SupabaseClient supa; // клиент supabase
  PostsRepository(this.supa); // конструктор

  static const Map<String, List<String>> _legacyCaptionToNames = { // карта "старый текст подписи -> список имён файлов"
    // const-карта "старый текст подписи -> список имён файлов"
    'Красота то какая! Ляпота!🌅 -  © Казенов Эдуард': ['photo3.jpg'], // один файл для этой подписи
    'Поход в лес! 🌳🏔️🌲': ['photo1.jpg', 'photo2.jpg'], // два файла для похода
    'Мой отдых 🌊🌊🌊': ['photo4.jpg', 'photo5.jpg', 'photo21.jpg'], // три файла
    'Красиво, однако!': [ // несколько файлов для одной подписи
      'photo6.jpg',
      'photo7.jpg',
      'photo8.jpg',
      'photo9.jpg',
      'photo10.jpg',
      'photo11.jpg',
      'photo24.jpg',
      'photo25.jpg',
    ],
  };

  List<String> _publicUrlsOrAssets(List<String> names) => // приватный метод превращает имена файлов в публичные url к бакету постов
  // приватный метод превращает имена файлов в публичные url к бакету постов
  names
      .map(
        (n) => publicUrl(bucket: postBucketName, objectKey: n), // для каждого имени собираем публичный URL
  )
      .toList(); // возвращаем список ссылок

  String _postImagePublicUrlFromStoragePath(String storagePath) { // нормализация пути к картинке из post_images
    // приватный метод нормализует путь вида "post-images/xxx" и делает из него публичный url
    final clean =
    cleanStoragePath(storagePath); // сначала убираем лишние слэши
    final fixed = clean.startsWith('post-images/')
        ? clean.substring('post-images/'.length) // отрезаем префикс бакета, если есть
        : clean; // иначе оставляем как есть
    return publicUrl(
      bucket: postBucketName, // используем бакет постов
      objectKey: fixed, // относительный путь в бакете
    ); // собираем публичную ссылку
  }

  // Публичный URL для аватара автора (абсолютный -> как есть; относительный -> из avatars; )
  String _authorAvatarPublicUrl(String? avatarUrlFromDb, String authorLogin) => // выбор правильного url для аватарки
  (avatarUrlFromDb?.isHttpUrl ?? false) // если в БД уже лежит абсолютный http/https url
      ? avatarUrlFromDb! // возвращаем как есть
      : publicUrl( // иначе собираем url из бакета avatars
    bucket: avatarsBucketName, // бакет для аватарок
    objectKey:
    (avatarUrlFromDb != null && avatarUrlFromDb.isNotEmpty) // если в БД хранится относительный путь
        ? avatarUrlFromDb // берём его
        : '$authorLogin.jpg', // иначе fallback: <login>.jpg в бакете avatars
  );

  Future<List<PostModel>> loadPosts() async { // загрузка постов из БД
    final postsRaw = await supa
        .from('posts') // таблица posts
        .select('id,user_id,created_at,text') // выбираем базовые поля поста
        .order('created_at', ascending: false); // посты по убыванию даты

    if (postsRaw.isEmpty) return const []; // если нет постов — сразу пустой список

    final postIds =
    postsRaw.map<String>((p) => p['id'] as String).toList(); // список id постов
    final userIds = postsRaw
        .map<String>((p) => p['user_id'] as String) // берём id автора из каждого поста
        .toSet() // уникализируем
        .toList(); // превращаем в список

    final usersRaw = await supa
        .from('users') // таблица users
        .select('id,login,full_name,avatar_url') // нужные поля автора
        .inFilter('id', userIds); // авторы всех постов

    final imagesRaw = await supa
        .from('post_images') // таблица с привязкой картинок к постам
        .select('post_id,storage_path,sort_order') // id поста, путь к файлу и порядок
        .inFilter('post_id', postIds) // только для нужных постов
        .order('sort_order'); // картинки для постов по порядку

    final usersById = { // индекс: id -> UserModel
      for (final u in usersRaw)
        (u['id'] as String): UserModel( // строим UserModel из строки users
          id: u['id'] as String,
          login: (u['login'] ?? '') as String,
          fullName: (u['full_name'] ?? '') as String,
          avatarUrl: u['avatar_url'] as String?,
        )
    };

    final imagesByPost = <String, List<String>>{}; // индекс: пост -> список url
    for (final row in imagesRaw) { // обходим все строки из post_images
      final pid = row['post_id'] as String; // id поста
      final sp = row['storage_path'] as String; // путь в storage
      imagesByPost
          .putIfAbsent(pid, () => []) // если для поста ещё нет списка — создаём
          .add(_postImagePublicUrlFromStoragePath(sp)); // добавляем публичный url картинки
    }

    return postsRaw.map<PostModel>((p) { // сборка моделей PostModel
      // сборка моделей
      final postId = p['id'] as String; // id поста
      final userId = p['user_id'] as String; // id автора
      final createdAt = DateTime.parse(p['created_at'] as String); // парсим дату создания
      final text = (p['text'] ?? '') as String; // текст поста или пустая строка
      final author = usersById[userId]; // ищем автора в индексе
      final authorLogin = author?.login ?? ''; // логин автора
      final authorName = author?.fullName ?? ''; // ФИО автора
      final authorAvatarUrl =
      _authorAvatarPublicUrl(author?.avatarUrl, authorLogin); // получаем правильный url аватарки
      final photoUrls = (imagesByPost[postId] ?? []).let( // превращаем список ссылок на картинки
            (list) => list.isNotEmpty // если есть картинки в post_images
            ? list // используем их
            : (_legacyCaptionToNames[text]?.let(_publicUrlsOrAssets) ?? // иначе пытаемся найти по старой подписи
            const []), // если ничего нет — пустой список
      );
      return PostModel( // создаём модель поста
        id: postId, // id
        authorId: userId, // id автора
        authorLogin: authorLogin, // логин автора
        authorName: authorName, // ФИО автора
        authorAvatarUrl: authorAvatarUrl, // ссылка на аватар
        createdAt: createdAt, // дата создания
        text: text, // текст поста
        imageUrls: photoUrls, // список ссылок на картинки
      );
    }).toList(); // превращаем iterable в обычный List<PostModel>
  }
}
