import 'dart:typed_data'; // для Uint8List
import 'dart:io' show File; // для чтения файла (не web)

import 'package:flutter/foundation.dart' show kIsWeb; // чтобы отличать web от остального
import 'package:flutter/material.dart'; // базовый UI
import 'package:provider/provider.dart'; // для MyEventsState
import 'package:file_picker/file_picker.dart'; // выбор файлов
import 'package:table_calendar/table_calendar.dart'; // календарь
import 'package:supabase_flutter/supabase_flutter.dart'; // FileOptions для storage

import '../../core/app_services.dart'; // supabase, buckets, publicUrl
import 'events_data.dart'; // EventModel, EventsRepository, MyEventsState
import '../common/photo_view_screen.dart'; // экран просмотра фото

class EventsScreen extends StatefulWidget { // экран событий
  final VoidCallback onToggleTheme; // колбэк переключения темы
  const EventsScreen({ // конструктор экрана событий
    super.key, // пробрасываем key
    required this.onToggleTheme, // обязательный колбэк смены темы
  });

  @override
  State<EventsScreen> createState() => _EventsScreenState(); // создаём состояние
}

class _EventsScreenState extends State<EventsScreen> { // состояние экрана событий
  late final EventsRepository repo; // репозиторий событий
  bool asCalendar = false; // режим отображения: список/календарь
  bool showPast = false; // показывать ли прошедшие события в списке
  DateTime focusedDay = DateTime.now(); // текущий день в календаре
  List<EventModel> events = []; // события
  bool loading = true; // флаг загрузки
  String? error; // текст ошибки

  @override
  void initState() { // инициализация состояния
    super.initState(); // базовый initState
    repo = EventsRepository(supabase); // создаём репозиторий
    _load(); // первая загрузка
  }

  Future<void> _load() async { // загрузка событий
    setState(() {
      loading = true; // включаем индикатор
      error = null; // очищаем ошибку
    });
    try {
      final from = asCalendar // нижняя граница периода
          ? DateTime(focusedDay.year, focusedDay.month - 1, 1) // для календаря: месяц назад от текущего
          : (showPast // для списка
          ? null // если показываем прошедшие — без нижней границы
          : DateTime.now()
          .subtract(const Duration(days: 1))); // для списка — будущее (минус один день чтобы захватить сегодня)
      final to = asCalendar // верхняя граница периода
          ? DateTime(focusedDay.year, focusedDay.month + 2, 0) // для календаря: до конца следующего месяца
          : null; // для списка верхней границы нет

      events = await repo.loadEvents(from: from, to: to); // загружаем события через репозиторий
    } catch (e) {
      error = 'Не удалось загрузить события: $e'; // сохраняем текст ошибки
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор, если виджет жив
    }
  }

  Future<void> _join(String id) async { // записаться на событие
    try {
      await context.read<MyEventsState>().join(id); // обновляем БД и глобальный счётчик
      await _load(); // обновляем список
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Вы записались'))); // уведомляем пользователя
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка записи: $e'))); // показываем ошибку
    }
  }

  Future<void> _leave(String id) async { // отказаться от участия
    try {
      await context.read<MyEventsState>().leave(id); // обновляем БД и счётчик
      await _load(); // обновляем список
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы отказались от участия'))); // уведомление
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка отказа: $e'))); // ошибка
    }
  }

  Widget _modeSwitch() => Row( // переключатель режимов список/календарь
    mainAxisAlignment: MainAxisAlignment.end, // выравниваем по правому краю
    children: [
      const Text('Список'), // подпись слева
      Switch(
        value: asCalendar, // текущий режим
        onChanged: (v) async {
          setState(() {
            asCalendar = v; // переключаем флаг
          });
          await _load(); // перезагружаем события под новый режим
        },
      ),
      const Text('Календарь'), // подпись справа
    ],
  );

  Widget _pastSwitch() => Row( // галочка "показывать прошедшие"
    mainAxisAlignment: MainAxisAlignment.start, // выравниваем по левому краю
    children: [
      Checkbox(
        value: showPast, // текущее состояние чекбокса
        onChanged: asCalendar
            ? null // для календаря неактивна (но состояние сохраняется)
            : (v) async {
          setState(() {
            showPast = v ?? false; // обновляем флаг, если null — false
          });
          await _load(); // перезагружаем список
        },
      ),
      const Flexible(child: Text('Показывать прошедшие события (в списке)')), // текстовое описание
    ],
  );

  @override
  Widget build(BuildContext context) { // сборка основного экрана событий
    final body = loading // выбираем, что показать
        ? const Center(child: CircularProgressIndicator()) // индикатор загрузки
        : error != null // если есть ошибка
        ? Center(
      child: Text(
        error!, // текст ошибки
        style: const TextStyle(color: Colors.red), // красный цвет
      ),
    )
        : asCalendar // иначе по режиму — календарь или список
        ? _calendar() // вид календаря
        : _list(); // вид списка

    return Scaffold(
      appBar: AppBar(
        title: const Text('События'), // заголовок экрана
        actions: [
          IconButton(
            tooltip: 'Тема', // подсказка к кнопке
            icon: const Icon(Icons.brightness_6), // иконка темы
            onPressed: widget.onToggleTheme, // переключаем тему
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12), // общие отступы
        child: Column(
          children: [
            _modeSwitch(), // переключатель список/календарь
            const SizedBox(height: 4), // небольшой отступ
            if (!asCalendar) _pastSwitch(), // чекбокс виден только в режиме "Список"
            const SizedBox(height: 8), // отступ перед контентом
            Expanded(child: body), // сам контент (список или календарь)
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateEvent, // открыть экран создания события
        child: const Icon(Icons.add), // иконка "+"
      ),
    );
  }

  Widget _list() => ListView.separated( // список событий
    itemCount: events.length, // количество элементов
    separatorBuilder: (_, __) => const SizedBox(height: 8), // отступ между карточками
    itemBuilder: (_, i) => EventTile( // строим плитку события
      e: events[i], // модель события
      onJoin: () => _join(events[i].id), // обработчик "записаться"
      onLeave: () => _leave(events[i].id), // обработчик "отказаться"
      onOpen: () => _openDetails(events[i]), // обработчик "перейти к деталям"
    ),
  );

  Widget _calendar() { // режим календаря
    final byDay = <DateTime, List<EventModel>>{}; // карта: день -> список событий
    for (final e in events) { // пробегаем все события
      final d = DateTime(e.startAt.year, e.startAt.month, e.startAt.day); // нормализуем дату (без времени)
      byDay.putIfAbsent(d, () => []).add(e); // кладём событие в список для этого дня
    }
    final selectedDay =
    DateTime(focusedDay.year, focusedDay.month, focusedDay.day); // текущий выбранный день (без времени)
    final ofDay = byDay[selectedDay] ?? const <EventModel>[]; // события конкретного дня

    Widget _dayCell( // отрисовка отдельной "ячейки" дня
        BuildContext context,
        DateTime day,
        int eventsCount,
        bool isSelected,
        bool isToday,
        ) {
      final isDark = Theme.of(context).brightness == Brightness.dark; // тёмная ли тема
      Color? bg; // цвет фона дня
      if (eventsCount >= 3) { // если 3+ событий — выделяем поярче
        // если 3+ событий — красим день
        bg = isDark ? Colors.deepPurple : Colors.pinkAccent; // разные цвета для тёмной/светлой темы
      } else if (isSelected) { // если день выбран
        bg = Theme.of(context).colorScheme.primary; // основной цвет темы
      } else if (isToday) { // если это сегодня
        bg = Theme.of(context).colorScheme.secondary; // дополнительный цвет темы
      }
      final textColor =
      bg != null ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color; // цвет текста по фону
      return Container(
        decoration: BoxDecoration(
          color: bg ?? Colors.transparent, // фон или прозрачный
          shape: BoxShape.circle, // круглая ячейка
        ),
        alignment: Alignment.center, // выравнивание по центру
        child: Text(
          '${day.day}', // число дня
          style: TextStyle(color: textColor), // цвет текста
        ),
      );
    }

    return Column(
      children: [
        TableCalendar<EventModel>( // виджет календаря
          firstDay: DateTime.utc(2020, 1, 1), // минимально допустимая дата
          lastDay: DateTime.utc(2035, 12, 31), // максимально допустимая дата
          focusedDay: focusedDay, // текущий фокус календаря
          eventLoader: (day) { // загрузчик событий для конкретного дня
            final d = DateTime(day.year, day.month, day.day); // нормализуем дату
            return byDay[d] ?? const []; // возвращаем список событий
          },
          calendarFormat: CalendarFormat.month, // формат: месяц
          onPageChanged: (fd) async { // обработчик перелистывания месяцев
            focusedDay = fd; // обновляем фокус
            await _load(); // перезагружаем события для нового диапазона
          },
          selectedDayPredicate: (d) =>
          DateTime(d.year, d.month, d.day) == selectedDay, // как понять, что день выбран
          onDaySelected: (sel, foc) => setState(() => focusedDay = foc), // по клику на день обновляем focusedDay
          calendarStyle: CalendarStyle(
            markersMaxCount: 3, // максимум 3 точки под датой
          ),
          calendarBuilders: CalendarBuilders( // кастомная отрисовка ячеек
            defaultBuilder: (context, day, focused) { // обычный день
              final d = DateTime(day.year, day.month, day.day); // дата без времени
              final eventsCount = (byDay[d] ?? const []).length; // количество событий
              return _dayCell(context, day, eventsCount, false, false); // рисуем ячейку
            },
            todayBuilder: (context, day, focused) { // сегодняшний день
              final d = DateTime(day.year, day.month, day.day);
              final eventsCount = (byDay[d] ?? const []).length;
              return _dayCell(context, day, eventsCount, false, true); // помечаем как "сегодня"
            },
            selectedBuilder: (context, day, focused) { // выбранный день
              final d = DateTime(day.year, day.month, day.day);
              final eventsCount = (byDay[d] ?? const []).length;
              return _dayCell(context, day, eventsCount, true, false); // помечаем как выбранный
            },
          ),
        ),
        const SizedBox(height: 8), // отступ
        Expanded(
          child: ListView( // список событий выбранного дня
            children: ofDay
                .map(
                  (e) => EventTile( // плитка события
                e: e,
                onJoin: () => _join(e.id), // обработчик "записаться"
                onLeave: () => _leave(e.id), // обработчик "отказаться"
                onOpen: () => _openDetails(e), // обработчик "детали"
              ),
            )
                .toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _openDetails(EventModel e) async { // открыть экран деталей
    final changed = await Navigator.of(context).push<bool>( // открываем экран и ждём флаг
      MaterialPageRoute(
        builder: (_) => EventDetailsScreen(event: e), // экран деталей события
      ),
    );
    if (changed == true) {
      await _load(); // обновляем события
    }
  }

  Future<void> _openCreateEvent() async { // открыть форму создания
    // открыть форму создания
    final created = await Navigator.of(context).push<bool>( // открываем экран создания
      MaterialPageRoute(builder: (_) => const CreateEventScreen()), // экран "Новое событие"
    );
    if (created == true) {
      await context.read<MyEventsState>().reloadStats(); // обновляем счётчик после создания
      await _load(); // перегружаем список
    }
  }
}

class EventTile extends StatelessWidget { // карточка события в списке
  // карточка события в списке
  final EventModel e; // событие
  final VoidCallback onJoin; // обработчик "записаться"
  final VoidCallback onLeave; // обработчик "отказаться"
  final VoidCallback onOpen; // обработчик "детали"
  const EventTile({
    super.key, // пробрасываем key
    required this.e, // обязательное событие
    required this.onJoin, // обработчик записи
    required this.onLeave, // обработчик отказа
    required this.onOpen, // обработчик открытия деталей
  });

  static String _fmt(DateTime dt) { // форматирование даты/времени
    // формат "дд.мм чч:мм"
    final d = dt.day.toString().padLeft(2, '0'); // день с ведущим нулём
    final m = dt.month.toString().padLeft(2, '0'); // месяц с ведущим нулём
    final hh = dt.hour.toString().padLeft(2, '0'); // часы
    final mm = dt.minute.toString().padLeft(2, '0'); // минуты
    return '$d.$m $hh:$mm'; // итоговая строка
  }

  @override
  Widget build(BuildContext context) { // сборка плитки события
    final started = DateTime.now().isAfter(e.startAt); // уже началось?
    final canLeave = !started && !e.iAmOwner && e.iAmJoined; // можно отказаться?
    final canJoin = !started && !e.iAmJoined; // можно записаться?
    final cover = e.coverUrl; // обложка (публичный URL или null)

    final coverWidget = cover != null // виджет обложки
        ? GestureDetector(
      onTap: () => Navigator.of(context).push( // по нажатию открываем в полноэкранном просмотрщике
        MaterialPageRoute(
          builder: (_) => PhotoViewScreen(imageAsset: cover), // просмотр картинки по URL
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12), // скругляем углы
        child: AspectRatio(
          aspectRatio: 1, // квадратная обложка
          child: Image.network(cover, fit: BoxFit.cover), // загружаем картинку из сети
        ),
      ),
    )
        : const Icon(Icons.event, size: 48); // если нет обложки — иконка события

    return InkWell(
      onTap: onOpen, // при тапе по плитке открываем детали
      child: Container(
        padding: const EdgeInsets.all(12), // внутренние отступы
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, // фон как у карточки
          borderRadius: BorderRadius.circular(16), // скругления
        ),
        child: Row(
          children: [
            SizedBox(width: 72, height: 72, child: coverWidget), // место под обложку
            const SizedBox(width: 12), // отступ
            Expanded(
              child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title,
                    style:
                    const TextStyle(fontWeight: FontWeight.bold)), // заголовок события
                const SizedBox(height: 4), // отступ
                Text('${_fmt(e.startAt)} — ${_fmt(e.endAt)}'), // интервал времени
                if ((e.place ?? '').isNotEmpty) Text(e.place!), // место встречи, если есть
                Text('Участников: ${e.attendees}'), // количество участников
              ]),
            ),
            const SizedBox(width: 8), // отступ между текстом и кнопками
            Column(
              children: [
                if (canJoin)
                  TextButton(onPressed: onJoin, child: const Text('Записаться')), // кнопка "Записаться"
                if (canLeave)
                  TextButton(onPressed: onLeave, child: const Text('Отказаться')), // кнопка "Отказаться"
                if (e.iAmOwner)
                  const Text(
                    'Автор', // отметка "Автор"
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EventDetailsScreen extends StatelessWidget { // экран деталей события
  // экран деталей события
  final EventModel event; // событие
  const EventDetailsScreen({super.key, required this.event}); // конструктор с обязательным event

  String _shortName(String full) { // вернуть "Фамилия Имя" без отчества
    // вернуть "Фамилия Имя" без отчества
    final parts =
    full.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList(); // разбиваем по пробелам и убираем пустые
    if (parts.length >= 2) { // если минимум две части
      return '${parts[0]} ${parts[1]}'; // возвращаем первые две
    }
    return full; // иначе исходная строка
  }

  Future<void> _openEdit(BuildContext context) async { // открыть экран редактирования (только для автора)
    // открыть экран редактирования (только для автора)
    final updated = await Navigator.of(context).push<bool>( // открываем экран редактирования
      MaterialPageRoute(
        builder: (_) => EditEventScreen(event: event), // редактор события
      ),
    );
    if (updated == true) {
      // если событие отредактировано — закрываем детали и сигнализируем наверх
      Navigator.of(context).pop(true); // возвращаемся на список с флагом "изменено"
    }
  }

  @override
  Widget build(BuildContext context) { // сборка экрана деталей
    final cover = event.coverUrl; // ссылка обложки
    final authorFull = (event.ownerFullName ?? '').trim(); // ФИО автора

    return Scaffold(
      appBar: AppBar(
        title: Text(event.title), // в заголовке название события
        actions: [
          if (event.iAmOwner)
            IconButton(
              tooltip: 'Редактировать', // подсказка
              icon: const Icon(Icons.edit), // иконка редактирования
              onPressed: () => _openEdit(context), // открыть редактор
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16), // отступы
        children: [
          if (cover != null)
            GestureDetector(
              onTap: () => Navigator.of(context).push( // полноэкранный просмотр обложки
                MaterialPageRoute(
                  builder: (_) => PhotoViewScreen(imageAsset: cover), // просмотр картинки
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16), // скругляем углы
                child: AspectRatio(
                  aspectRatio: 16 / 9, // пропорции 16:9
                  child: Image.network(cover, fit: BoxFit.cover), // загружаем обложку
                ),
              ),
            ),
          const SizedBox(height: 12), // отступ
          Text(
            '${EventTile._fmt(event.startAt)} — ${EventTile._fmt(event.endAt)}', // интервал времени
            style: const TextStyle(fontWeight: FontWeight.bold), // выделяем жирным
          ),
          if ((event.place ?? '').isNotEmpty) ...[ // если указан адрес
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.place, size: 16), // маленькая иконка места
              const SizedBox(width: 4),
              Flexible(child: Text(event.place!)), // текст места
            ]),
          ],
          const SizedBox(height: 12), // отступ
          Text(event.description ?? 'Без описания'), // текст описания или заглушка
          const SizedBox(height: 12),
          Text('Участников: ${event.attendees}'), // число участников
          const SizedBox(height: 12),
          if (authorFull.isNotEmpty)
            Text(
              'Автор: ${_shortName(authorFull)}', // автор события (короткое ФИО)
              style: TextStyle(
                fontStyle: FontStyle.italic, // курсив
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withOpacity(0.8), // приглушенный цвет
              ),
            ),
          if (event.iAmOwner) ...[ // доп. блок только для автора
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _openEdit(context), // открыть редактор
              icon: const Icon(Icons.edit), // иконка
              label: const Text('Редактировать событие'), // текст кнопки
            ),
          ],
        ],
      ),
    );
  }
}

class CreateEventScreen extends StatefulWidget { // экран создания события
  // экран создания события
  const CreateEventScreen({super.key}); // без параметров

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState(); // создаём состояние
}

class _CreateEventScreenState extends State<CreateEventScreen> { // состояние создания события
  final titleCtrl = TextEditingController(); // заголовок
  final descCtrl = TextEditingController(); // описание
  final placeCtrl = TextEditingController(); // место
  final imageCtrl = TextEditingController(); // относительный путь в bucket

  DateTime startAt = DateTime.now().add(const Duration(hours: 2)); // дефолт: через 2 часа
  DateTime endAt = DateTime.now().add(const Duration(hours: 3)); // дефолт: через 3 часа

  bool loading = false; // индикатор
  String? error; // ошибка
  late final EventsRepository repo; // репозиторий

  Uint8List? _pickedBytes; // байты выбранного файла
  String? _pickedName; // имя файла

  @override
  void initState() { // инициализация
    super.initState();
    repo = EventsRepository(supabase); // создаём репозиторий событий
  }

  bool get _pickedIsImage { // выбранный файл — картинка?
    // выбранный файл — картинка?
    final name = (_pickedName ?? '').toLowerCase(); // имя в нижнем регистре
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp'); // набор допустимых расширений
  }

  Future<void> _pickFile() async { // выбрать файл
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false, // только один файл
      type: FileType.any, // любой тип
      withData: kIsWeb, // на web сразу читаем bytes
    );
    if (res == null || res.files.isEmpty) return; // пользователь отменил
    final f = res.files.single; // берём один файл

    Uint8List? bytes = f.bytes; // пробуем взять bytes
    if (bytes == null && f.path != null && !kIsWeb) {
      bytes = await File(f.path!).readAsBytes(); // читаем с диска, если не web
    }
    if (bytes == null) { // если так и не прочитали
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прочитать файл')), // сообщение об ошибке
        );
      }
      return;
    }

    setState(() {
      _pickedBytes = bytes; // сохраняем содержимое
      _pickedName = f.name; // сохраняем имя файла
    });
  }

  Future<void> _uploadPickedFile() async { // загрузить файл в bucket event-images
    // загрузить файл в bucket event-images
    if (_pickedBytes == null) { // если ещё нет выбранного файла
      await _pickFile(); // предлагаем выбрать
      if (_pickedBytes == null) return; // если всё равно нет — выходим
    }
    setState(() {
      loading = true; // включаем индикатор
      error = null; // очищаем ошибку
    });

    try {
      String ext = 'bin'; // расширение по умолчанию
      final name = (_pickedName ?? '').trim(); // имя файла
      final dot = name.lastIndexOf('.'); // индекс точки
      if (dot > 0 && dot < name.length - 1) {
        ext = name.substring(dot + 1).toLowerCase(); // берём расширение
      }
      final uid = supabase.auth.currentUser?.id ?? 'anon'; // uid пользователя или 'anon'
      final objectKey =
          '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext'; // относительный путь
      await supabase.storage
          .from(eventImagesBucketName) // бакет event-images
          .uploadBinary(
        objectKey, // ключ в бакете
        _pickedBytes!, // содержимое
        fileOptions: FileOptions(upsert: true), // перезаписываем при совпадении
      );

      setState(() {
        imageCtrl.text = objectKey; // сохраняем путь в поле
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Картинка загружена'))); // уведомление
    } catch (e) {
      setState(() => error = 'Ошибка загрузки: $e'); // сохраняем текст ошибки
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор
    }
  }

  bool get _datesValid => endAt.isAfter(startAt); // валидация дат (конец позже начала)

  Future<void> _submit() async { // отправка формы
    // отправка формы
    setState(() {
      loading = true; // включаем индикатор
      error = null; // очищаем ошибку
    });
    try {
      if (!_datesValid) { // если даты некорректны
        throw Exception(
            'Дата/время окончания должны быть ПОЗЖЕ даты/времени начала'); // выбрасываем ошибку
      }
      await repo.createEvent( // создаём событие через репозиторий
        title: titleCtrl.text, // название
        description: descCtrl.text, // описание
        place: placeCtrl.text, // место
        imagePath: imageCtrl.text, // относительный путь к картинке
        startAt: startAt, // начало
        endAt: endAt, // конец
      );
      await context.read<MyEventsState>().reloadStats(); // обновляем глобальный счётчик
      if (mounted) Navigator.of(context).pop(true); // закрываем экран с флагом "создано"
    } catch (e) {
      setState(() => error = '$e'); // сохраняем текст ошибки
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор
    }
  }

  Widget _asListPreview() { // мини-превью как карточка в списке
    final fake = EventModel( // создаём "фейковое" событие для предпросмотра
      id: 'preview', // фиктивный id
      title: (titleCtrl.text.isEmpty ? 'Название события' : titleCtrl.text), // заголовок или заглушка
      description: descCtrl.text.isEmpty ? null : descCtrl.text, // описание или null
      place: placeCtrl.text.isEmpty ? null : placeCtrl.text, // место или null
      imagePath: imageCtrl.text.isEmpty ? null : imageCtrl.text, // путь к картинке или null
      startAt: startAt, // текущее значение начала
      endAt: endAt, // текущее значение окончания
      createdBy: null, // автора не указываем
      isSystem: false, // обычное событие
      attendees: 12, // примерное количество участников
      iAmJoined: false, // флаги участия
      iAmOwner: false,
      ownerFullName: null, // автор не отображается
      ownerLogin: null,
    );
    return IgnorePointer(
      ignoring: true, // делаем плитку некликабельной
      child: EventTile(
        e: fake, // используем фейковое событие
        onJoin: () {}, // пустые колбэки
        onLeave: () {},
        onOpen: () {},
      ),
    );
  }

  void _openPickedFull() { // полноэкранное открытие выбранной (ещё не загруженной) картинки
    if (_pickedBytes != null && _pickedIsImage) { // только если есть bytes и это картинка
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewScreen(imageBytes: _pickedBytes), // просмотр картинки из памяти
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold( // сборка экрана создания события
    appBar: AppBar(title: const Text('Новое событие')), // заголовок
    body: ListView(
      padding: const EdgeInsets.all(16), // отступы
      children: [
        TextField(
          controller: titleCtrl, // поле названия
          decoration: const InputDecoration(labelText: 'Название*'), // обязательное
        ),
        const SizedBox(height: 8),
        TextField(
          controller: descCtrl, // поле описания
          decoration: const InputDecoration(labelText: 'Описание'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: placeCtrl, // поле места
          decoration:
          const InputDecoration(labelText: 'Место проведения'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: imageCtrl, // относительный путь к картинке
              readOnly: true, // редактируется только через выбор/загрузку
              decoration: const InputDecoration(
                labelText: 'Картинка (загрузите любой формат)',
                helperText:
                'Файл попадёт в bucket event-images, здесь — относительный путь', // подсказка
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.attach_file), // иконка файла
            label: Text(_pickedName == null
                ? 'Выбрать файл'
                : 'Выбрано: $_pickedName'), // показываем имя выбранного файла
            onPressed: loading ? null : _pickFile, // блокируем при загрузке
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.cloud_upload), // иконка облака
            label: const Text('Загрузить в бакет'), // загрузка файла
            onPressed: loading ? null : _uploadPickedFile, // блокируем при загрузке
          ),
        ]),
        if (_pickedBytes != null) ...[ // если есть выбранный файл
          const SizedBox(height: 12),
          Text(
            'Предпросмотр выбранного файла (до загрузки):',
            style: Theme.of(context).textTheme.bodySmall, // подсказочный стиль
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _openPickedFull, // нажатие — полноэкранный просмотр
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12), // скругление
              child: Container(
                color: Theme.of(context).cardColor, // фон под предпросмотр
                padding: const EdgeInsets.all(8), // внутренний отступ
                child: _pickedIsImage
                    ? Image.memory(
                  _pickedBytes!, // если это картинка — показываем превью
                  height: 160,
                  fit: BoxFit.cover,
                )
                    : Row( // если не картинка — иконка файла + имя
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
        if (imageCtrl.text.trim().isNotEmpty) ...[ // если уже есть загруженная обложка
          const SizedBox(height: 12),
          Text(
            'Загруженная обложка (публичный URL):',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => Navigator.of(context).push( // полноэкранный просмотр загруженной обложки
              MaterialPageRoute(
                builder: (_) => PhotoViewScreen(
                  imageAsset: publicUrl(
                    bucket: eventImagesBucketName, // используем бакет событий
                    objectKey: imageCtrl.text.trim(), // относительный путь
                  ),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  publicUrl(
                    bucket: eventImagesBucketName,
                    objectKey: imageCtrl.text.trim(),
                  ),
                  fit: BoxFit.cover, // заполняем по ширине
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Как это будет выглядеть в списке событий:',
          style: Theme.of(context).textTheme.bodySmall, // подсказка к предпросмотру
        ),
        const SizedBox(height: 8),
        _asListPreview(), // карточка-превью
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text('Начало: ${EventTile._fmt(startAt)}'), // текст с датой/временем начала
          ),
          TextButton(
            onPressed: () async { // выбор даты начала
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: startAt, // текущая дата начала
                firstDate: DateTime(now.year - 1), // год назад
                lastDate: DateTime(now.year + 2), // через 2 года
              );
              if (picked != null) {
                setState(() => startAt = DateTime(picked.year,
                    picked.month, picked.day, startAt.hour, startAt.minute)); // переносим время на новую дату
              }
            },
            child: const Text('Дата'),
          ),
          TextButton(
            onPressed: () async { // выбор времени начала
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(startAt), // текущее время начала
              );
              if (picked != null) {
                setState(() => startAt = DateTime(startAt.year,
                    startAt.month, startAt.day, picked.hour, picked.minute)); // обновляем время
              }
            },
            child: const Text('Время'),
          ),
        ]),
        Row(children: [
          Expanded(
            child: Text('Окончание: ${EventTile._fmt(endAt)}'), // текст с датой/временем окончания
          ),
          TextButton(
            onPressed: () async { // выбор даты окончания
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: endAt, // текущая дата окончания
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 2),
              );
              if (picked != null) {
                setState(() => endAt = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    endAt.hour,
                    endAt.minute)); // переносим время окончания на новую дату
              }
            },
            child: const Text('Дата'),
          ),
          TextButton(
            onPressed: () async { // выбор времени окончания
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(endAt),
              );
              if (picked != null) {
                setState(() => endAt = DateTime(endAt.year, endAt.month,
                    endAt.day, picked.hour, picked.minute)); // обновляем время
              }
            },
            child: const Text('Время'),
          ),
        ]),
        if (!_datesValid) ...[ // если даты некорректны
          const SizedBox(height: 6),
          const Text(
            '⚠️ Дата/время окончания должны быть ПОЗЖЕ даты/времени начала', // подсказка об ошибке
            style: TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 12),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)), // текст ошибки
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: (loading || !_datesValid) ? null : _submit, // отключаем при загрузке или ошибке дат
          child: loading
              ? const CircularProgressIndicator() // индикатор
              : const Text('Создать'), // текст кнопки
        ),
      ],
    ),
  );
}

class EditEventScreen extends StatefulWidget { // экран редактирования события (для автора)
  final EventModel event; // исходное событие
  const EditEventScreen({super.key, required this.event}); // конструктор

  @override
  State<EditEventScreen> createState() => _EditEventScreenState(); // создаём состояние
}

class _EditEventScreenState extends State<EditEventScreen> { // состояние экрана редактирования
  late final TextEditingController titleCtrl; // заголовок
  late final TextEditingController descCtrl; // описание
  late final TextEditingController placeCtrl; // место
  late final TextEditingController imageCtrl; // относительный путь в bucket

  late DateTime startAt; // начало
  late DateTime endAt; // конец

  bool loading = false; // индикатор
  String? error; // ошибка
  late final EventsRepository repo; // репозиторий

  Uint8List? _pickedBytes; // байты выбранного файла
  String? _pickedName; // имя файла

  @override
  void initState() { // инициализация экрана
    super.initState();
    repo = EventsRepository(supabase); // создаём репозиторий
    titleCtrl = TextEditingController(text: widget.event.title); // заполняем поля из события
    descCtrl = TextEditingController(text: widget.event.description ?? '');
    placeCtrl = TextEditingController(text: widget.event.place ?? '');
    imageCtrl = TextEditingController(text: widget.event.imagePath ?? '');
    startAt = widget.event.startAt; // начальное время
    endAt = widget.event.endAt; // конечное время
  }

  bool get _pickedIsImage { // выбранный файл — картинка?
    final name = (_pickedName ?? '').toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp');
  }

  Future<void> _pickFile() async { // выбор файла обложки
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false, // один файл
      type: FileType.any, // любой тип
      withData: kIsWeb, // на web читаем bytes
    );
    if (res == null || res.files.isEmpty) return; // отмена
    final f = res.files.single;

    Uint8List? bytes = f.bytes; // пробуем взять bytes
    if (bytes == null && f.path != null && !kIsWeb) {
      bytes = await File(f.path!).readAsBytes(); // читаем файл
    }
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прочитать файл')), // ошибка чтения
        );
      }
      return;
    }

    setState(() {
      _pickedBytes = bytes; // сохраняем содержимое
      _pickedName = f.name; // сохраняем имя
    });
  }

  Future<void> _uploadPickedFile() async { // загрузка выбранного файла в бакет
    if (_pickedBytes == null) { // если ничего не выбрано
      await _pickFile(); // просим выбрать
      if (_pickedBytes == null) return; // если всё равно нет — выходим
    }
    setState(() {
      loading = true; // включаем индикатор
      error = null; // очищаем ошибку
    });

    try {
      String ext = 'bin'; // расширение по умолчанию
      final name = (_pickedName ?? '').trim();
      final dot = name.lastIndexOf('.');
      if (dot > 0 && dot < name.length - 1) {
        ext = name.substring(dot + 1).toLowerCase(); // разбираем расширение
      }
      final uid = supabase.auth.currentUser?.id ?? 'anon'; // текущий пользователь или 'anon'
      final objectKey =
          '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext'; // относительный путь
      await supabase.storage
          .from(eventImagesBucketName)
          .uploadBinary(
        objectKey, // ключ
        _pickedBytes!, // байты
        fileOptions: FileOptions(upsert: true), // перезаписываем при совпадении
      );

      setState(() {
        imageCtrl.text = objectKey; // записываем путь в поле
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Картинка загружена'))); // уведомление
    } catch (e) {
      setState(() => error = 'Ошибка загрузки: $e'); // текст ошибки
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор
    }
  }

  bool get _datesValid => endAt.isAfter(startAt); // валидация дат

  Future<void> _submit() async { // отправка изменений
    setState(() {
      loading = true; // индикатор
      error = null; // очищаем ошибку
    });
    try {
      if (!_datesValid) { // проверяем даты
        throw Exception(
            'Дата/время окончания должны быть ПОЗЖЕ даты/времени начала'); // выбрасываем исключение
      }
      await repo.updateEvent( // обновляем событие через репозиторий
        id: widget.event.id, // id события
        title: titleCtrl.text, // обновлённый заголовок
        description: descCtrl.text, // описание
        place: placeCtrl.text, // место
        imagePath: imageCtrl.text, // путь к картинке
        startAt: startAt, // начало
        endAt: endAt, // конец
      );
      await context.read<MyEventsState>().reloadStats(); // обновляем глобальные счётчики
      if (mounted) Navigator.of(context).pop(true); // возвращаем флаг "успешно изменено"
    } catch (e) {
      setState(() => error = '$e'); // сохраняем текст ошибки
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор
    }
  }

  void _openPickedFull() { // полноэкранный просмотр выбранного файла
    if (_pickedBytes != null && _pickedIsImage) { // только для картинок
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewScreen(imageBytes: _pickedBytes), // просмотр из памяти
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold( // сборка экрана редактирования
    appBar: AppBar(title: const Text('Редактировать событие')), // заголовок
    body: ListView(
      padding: const EdgeInsets.all(16), // отступы
      children: [
        TextField(
          controller: titleCtrl, // название
          decoration: const InputDecoration(labelText: 'Название*'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: descCtrl, // описание
          decoration: const InputDecoration(labelText: 'Описание'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: placeCtrl, // место
          decoration:
          const InputDecoration(labelText: 'Место проведения'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: imageCtrl, // путь к картинке
              readOnly: true, // руками не редактируем
              decoration: const InputDecoration(
                labelText: 'Картинка (загрузите любой формат)',
                helperText:
                'Файл попадёт в bucket event-images, здесь — относительный путь',
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.attach_file), // иконка файла
            label: Text(_pickedName == null
                ? 'Выбрать файл'
                : 'Выбрано: $_pickedName'), // имя выбранного файла
            onPressed: loading ? null : _pickFile,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Загрузить в бакет'),
            onPressed: loading ? null : _uploadPickedFile, // загрузка файла
          ),
        ]),
        if (_pickedBytes != null) ...[ // предпросмотр выбранного файла
          const SizedBox(height: 12),
          Text(
            'Предпросмотр выбранного файла (до загрузки):',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _openPickedFull, // полноэкранный просмотр
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Theme.of(context).cardColor,
                padding: const EdgeInsets.all(8),
                child: _pickedIsImage
                    ? Image.memory(
                  _pickedBytes!, // показываем картинку
                  height: 160,
                  fit: BoxFit.cover,
                )
                    : Row( // если не картинка — иконка файла
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
        if (imageCtrl.text.trim().isNotEmpty) ...[ // если есть уже установленная обложка
          const SizedBox(height: 12),
          Text(
            'Текущая обложка (публичный URL):',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => Navigator.of(context).push( // полноэкранный просмотр текущей обложки
              MaterialPageRoute(
                builder: (_) => PhotoViewScreen(
                  imageAsset: publicUrl(
                    bucket: eventImagesBucketName,
                    objectKey: imageCtrl.text.trim(),
                  ),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  publicUrl(
                    bucket: eventImagesBucketName,
                    objectKey: imageCtrl.text.trim(),
                  ),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Text('Начало: ${EventTile._fmt(startAt)}'), // начало события
          ),
          TextButton(
            onPressed: () async { // выбор даты начала
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: startAt,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 2),
              );
              if (picked != null) {
                setState(() => startAt = DateTime(picked.year,
                    picked.month, picked.day, startAt.hour, startAt.minute));
              }
            },
            child: const Text('Дата'),
          ),
          TextButton(
            onPressed: () async { // выбор времени начала
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(startAt),
              );
              if (picked != null) {
                setState(() => startAt = DateTime(startAt.year,
                    startAt.month, startAt.day, picked.hour, picked.minute));
              }
            },
            child: const Text('Время'),
          ),
        ]),
        Row(children: [
          Expanded(
            child: Text('Окончание: ${EventTile._fmt(endAt)}'), // окончание события
          ),
          TextButton(
            onPressed: () async { // выбор даты окончания
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: endAt,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 2),
              );
              if (picked != null) {
                setState(() => endAt = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    endAt.hour,
                    endAt.minute));
              }
            },
            child: const Text('Дата'),
          ),
          TextButton(
            onPressed: () async { // выбор времени окончания
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(endAt),
              );
              if (picked != null) {
                setState(() => endAt = DateTime(endAt.year, endAt.month,
                    endAt.day, picked.hour, picked.minute));
              }
            },
            child: const Text('Время'),
          ),
        ]),
        if (!_datesValid) ...[ // если даты некорректны
          const SizedBox(height: 6),
          const Text(
            '⚠️ Дата/время окончания должны быть ПОЗЖЕ даты/времени начала',
            style: TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 12),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)), // текст ошибки
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: (loading || !_datesValid) ? null : _submit, // отключаем при ошибках/загрузке
          child: loading
              ? const CircularProgressIndicator()
              : const Text('Сохранить изменения'), // кнопка сохранения
        ),
      ],
    ),
  );
}
