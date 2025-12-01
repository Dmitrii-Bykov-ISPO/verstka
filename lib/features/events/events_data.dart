import 'package:flutter/material.dart'; // ChangeNotifier
import 'package:supabase_flutter/supabase_flutter.dart'; // SupabaseClient
import '../../core/app_services.dart'; // publicUrl, eventImagesBucketName
import 'package:postgrest/postgrest.dart'; // PostgrestFilterBuilder

class EventModel { // модель события для UI
  final String id; // id события
  final String title; // название
  final String? description; // описание
  final String? place; // место
  final String? imagePath; // относительный путь в bucket event-images
  final DateTime startAt; // начало
  final DateTime endAt; // конец
  final String? createdBy; // uid автора (может быть null)
  final bool isSystem; // флаг системного события
  final int attendees; // количество участников
  final bool iAmJoined; // я записан?
  final bool iAmOwner; // я автор?
  final String? ownerFullName; // ФИО автора из таблицы users
  final String? ownerLogin; // логин автора

  const EventModel({ // конструктор неизменяемой модели
    required this.id, // обязательный id
    required this.title, // обязательное название
    required this.description, // необязательное описание
    required this.place, // необязательное место
    required this.imagePath, // необязательный путь к картинке
    required this.startAt, // дата/время начала
    required this.endAt, // дата/время окончания
    required this.createdBy, // автор
    required this.isSystem, // системное ли событие
    required this.attendees, // количество участников
    required this.iAmJoined, // признак, что текущий пользователь записан
    required this.iAmOwner, // признак, что текущий пользователь автор
    required this.ownerFullName, // ФИО автора
    required this.ownerLogin, // логин автора
  });

  String? get coverUrl => // публичный URL обложки события
  imagePath == null || imagePath!.isEmpty // если путь пустой или null
      ? null // тогда обложки нет
      : publicUrl(bucket: eventImagesBucketName, objectKey: imagePath!); // иначе собираем публичную ссылку из бакета
}

class MyEventsStats { // класс вместо записи (record), совместим с Dart 2/3
  // класс вместо записи (record), совместим с Dart 2/3
  final int total; // всего будущих/активных событий
  final bool hasToday; // есть ли событие сегодня
  const MyEventsStats(this.total, this.hasToday); // конструктор
}

class EventsRepository { // инкапсулирует чтение/запись событий
  final SupabaseClient supa; // клиент supabase
  EventsRepository(this.supa); // конструктор

  String? get _uid => supa.auth.currentUser?.id; // мой uid (или null)

  Future<List<EventModel>> loadEvents({DateTime? from, DateTime? to}) async { // загрузка списка событий с необязательными границами
    // тип PostgrestFilterBuilder
    PostgrestFilterBuilder<dynamic> q = supa // начинаем строить запрос
        .from('events') // таблица events
        .select(
        'id,title,description,place,image_path,start_at,end_at,created_by,is_system,' // базовые поля события
            'event_attendees!left(user_id)'); // джойн с таблицей участников (left join)

    if (from != null) { // если передана нижняя граница
      q = q.gte('start_at', from.toIso8601String()); // фильтр от
    }
    if (to != null) { // если передана верхняя граница
      q = q.lte('start_at', to.toIso8601String()); // фильтр до
    }

    final rows = await q.order('start_at'); // сортировка по дате начала и выполнение запроса

    final listRows = rows as List; // приводим к List
    final ownerIds = <String>{}; // набор авторов
    for (final r in listRows) { // пробегаемся по всем событиям
      final owner = r['created_by'] as String?; // читаем поле created_by
      if (owner != null) ownerIds.add(owner); // собираем уникальные id авторов
    }

    Map<String, dynamic> usersById = {}; // индекс авторов
    if (ownerIds.isNotEmpty) { // если есть, кого запрашивать
      final usersRows = await supa // запрос к таблице users
          .from('users')
          .select('id,login,full_name') // берём только нужные поля
          .inFilter('id', ownerIds.toList()); // выбираем только авторов по id
      usersById = {
        for (final u in (usersRows as List)) u['id'] as String: u, // строим map id -> строка пользователя
      };
    }

    return listRows.map<EventModel>((r) { // отображаем каждую строку в EventModel
      final attendees =
          (r['event_attendees'] as List?) ?? []; // список участников
      final cnt = attendees.length; // количество участников
      final me = _uid; // текущий uid
      final iAmJoined =
          me != null && attendees.any((a) => a['user_id'] == me); // записан ли я
      final owner = r['created_by'] as String?; // автор
      final iAmOwner = me != null && me == owner; // я автор?
      final user = owner != null
          ? usersById[owner] as Map<String, dynamic>?
          : null; // данные автора
      final ownerFullName = user?['full_name'] as String?; // ФИО
      final ownerLogin = user?['login'] as String?; // логин

      return EventModel( // создаём модель события
        id: r['id'] as String, // id
        title: (r['title'] ?? '') as String, // название (или пустая строка)
        description: r['description'] as String?, // описание
        place: r['place'] as String?, // место
        imagePath: r['image_path'] as String?, // путь к картинке
        startAt: DateTime.parse(r['start_at'] as String), // дата начала
        endAt: DateTime.parse(r['end_at'] as String), // дата окончания
        createdBy: owner, // автор
        isSystem: (r['is_system'] ?? false) as bool, // системное ли событие
        attendees: cnt, // кол-во участников
        iAmJoined: iAmJoined, // я участвую?
        iAmOwner: iAmOwner, // я автор?
        ownerFullName: ownerFullName, // ФИО автора
        ownerLogin: ownerLogin, // логин автора
      );
    }).toList(); // превращаем в обычный список
  }

  // Счётчик событий пользователя и флажок "есть сегодня?"
  // ВАЖНО: считаем только будущие/текущие события: end_at >= now
  Future<MyEventsStats> myStats() async { // посчитать статистику для текущего пользователя
    final uid = _uid; // берём текущий uid
    if (uid == null) return const MyEventsStats(0, false); // если не залогинен — ничего

    final now = DateTime.now(); // текущее время
    final dayStart = DateTime(now.year, now.month, now.day); // начало дня
    final dayEnd = dayStart.add(const Duration(days: 1)); // конец дня (не включительно)

    // Берём только те события, где пользователь участвует и end_at >= now (то есть событие ещё не закончилось)
    final rows = await supa
        .from('events')
        .select('id,start_at,end_at,event_attendees!inner(user_id)') // события с участием пользователя
        .gte('end_at', now.toIso8601String()) // окончание не раньше текущего времени
        .eq('event_attendees.user_id', uid); // участвует текущий пользователь

    final list = rows as List; // приводим к списку
    final total = list.length; // всего будущих/активных событий
    bool hasToday = false; // есть ли событие, которое начинается сегодня
    for (final r in list) { // перебираем все события
      final startStr = r['start_at'] as String?; // строка с датой начала
      if (startStr == null) continue; // если null — пропускаем
      final start = DateTime.parse(startStr); // парсим дату
      // dayStart <= start < dayEnd
      if (!start.isBefore(dayStart) && start.isBefore(dayEnd)) { // проверяем, попадает ли в сегодняшний день
        hasToday = true; // отмечаем флаг
        break; // можно дальше не идти
      }
    }
    return MyEventsStats(total, hasToday); // возвращаем объект статистики
  }
  Future<String> createEvent({ // создать новое событие
    required String title, // проверка на непусто
    required DateTime startAt, // начало
    required DateTime endAt, // конец
    String? description, // описание
    String? place, // место
    String? imagePath, // относительный путь в бакете event-images
  }) async {
    if (title.trim().isEmpty) throw Exception('Введите название'); // валидация
    if (!endAt.isAfter(startAt)) {
      // строгая проверка: окончание должно быть ПОЗЖЕ начала
      throw Exception('Окончание должно быть позже начала'); // выбрасываем ошибку
    }

    final row = await supa // создаём запись в таблице events
        .from('events')
        .insert({
      'title': title.trim(), // название без пробелов
      'description':
      (description ?? '').trim().isEmpty ? null : description, // описание или null
      'place': (place ?? '').trim().isEmpty ? null : place, // место или null
      'image_path':
      (imagePath ?? '').trim().isEmpty ? null : imagePath, // путь к картинке или null
      'start_at': startAt.toIso8601String(), // начало в ISO
      'end_at': endAt.toIso8601String(), // конец в ISO
      'created_by': _uid, // автор = текущий пользователь
      'is_system': false, // обычное событие
    })
        .select('id') // просим вернуть id
        .single(); // получаем одну строку

    return row['id'] as String; // возвращаем id события
  }
  Future<void> updateEvent({ //   Изменить событие (для автора)
    required String id, // id события
    required String title, // новое название
    required DateTime startAt, // новое начало
    required DateTime endAt, // новый конец
    String? description, // новое описание
    String? place, // новое место
    String? imagePath, // новый путь к обложке
  }) async {
    if (title.trim().isEmpty) throw Exception('Введите название'); // валидация
    if (!endAt.isAfter(startAt)) {
      throw Exception('Окончание должно быть позже начала'); // защита от некорректного диапазона
    }

    await supa
        .from('events')
        .update({
      'title': title.trim(), // новое название
      'description':
      (description ?? '').trim().isEmpty ? null : description, // новое описание или null
      'place': (place ?? '').trim().isEmpty ? null : place, // новое место или null
      'image_path':
      (imagePath ?? '').trim().isEmpty ? null : imagePath, // новый путь или null
      'start_at': startAt.toIso8601String(), // новое начало
      'end_at': endAt.toIso8601String(), // новый конец
    })
        .eq('id', id); // RLS должен не дать править чужое
  }
  Future<void> joinEvent(String eventId) async { // записаться на событие
    final uid = _uid; // текущий uid
    if (uid == null) throw Exception('Не авторизован'); // если null — ошибка
    await supa.from('event_attendees').insert({ // вставляем запись в таблицу участников
      'event_id': eventId, // id события
      'user_id': uid, // я (не null)
    });
  }
  Future<void> leaveEvent(String eventId) async { // отказаться от участия
    final uid = _uid; // текущий uid
    if (uid == null) throw Exception('Не авторизован'); // если null — ошибка
    await supa
        .from('event_attendees')
        .delete()
        .match({'event_id': eventId, 'user_id': uid}); // удаляем мою запись
  }
}

// Глобальное состояние для событий пользователя (Provider)
class MyEventsState extends ChangeNotifier { // ChangeNotifier чтобы слушать изменения
  // ChangeNotifier чтобы слушать изменения
  final EventsRepository repo; // репозиторий событий
  MyEventsStats stats =
  const MyEventsStats(0, false); // текущая статистика
  bool loading = false; // идёт ли запрос

  MyEventsState(this.repo); // конструктор с репозиторием

  Future<void> reloadStats() async { // перезагрузить статистику из БД
    // перезагрузить статистику из БД
    loading = true; // включаем флаг
    notifyListeners(); // обновляем UI
    try {
      stats = await repo.myStats(); // запрос к БД
    } finally {
      loading = false; // выключаем флаг
      notifyListeners(); // обновляем UI после завершения
    }
  }

  Future<void> join(String eventId) async { // записаться и обновить счётчики
    // записаться и обновить счётчики
    await repo.joinEvent(eventId); // пишем в БД
    await reloadStats(); // перезагружаем статистику
  }

  Future<void> leave(String eventId) async { // отказаться и обновить счётчики
    // отказаться и обновить счётчики
    await repo.leaveEvent(eventId); // удаляем из БД
    await reloadStats(); // перезагружаем статистику
  }
}