import 'dart:typed_data'; // для Uint8List
import 'dart:io' show File; // для чтения файла на mobile/desktop

import 'package:flutter/foundation.dart' show kIsWeb; // чтобы различать web и всё остальное
import 'package:flutter/material.dart'; // базовый UI toolkit
import 'package:file_picker/file_picker.dart'; // выбор файлов
import 'package:supabase_flutter/supabase_flutter.dart'; // UserAttributes для обновления профиля

import '../../core/app_services.dart'; // supabase, buckets, publicUrl
import '../../models/user_model.dart'; // UserModel
import '../common/photo_view_screen.dart'; // просмотр фото/аватарок

class UsersScreen extends StatefulWidget { // экран со списком всех пользователей для администратора
  // экран со списком всех пользователей для администратора
  final String currentUserId; // id залогиненного пользователя
  final VoidCallback onToggleTheme; // колбэк переключения темы
  const UsersScreen({ // конструктор экрана пользователей
    super.key, // пробрасываем key
    required this.currentUserId, // обязательный id текущего пользователя
    required this.onToggleTheme, // обязательный колбэк смены темы
  });

  @override
  State<UsersScreen> createState() => _UsersScreenState(); // создаём состояние
}
class _UsersScreenState extends State<UsersScreen> { // состояние списка пользователей
  List<UserModel> users = const []; // список пользователей
  bool loading = false; // флаг индикатора
  String? error; // текст ошибки

  @override
  void initState() { // инициализация состояния
    super.initState(); // вызываем базовый initState
    _loadUsers(); // сразу грузим список
  }

  Future<void> _loadUsers() async { // загрузка списка пользователей
    setState(() {
      loading = true; // включаем индикатор загрузки
      error = null; // очищаем ошибку
    });
    try {
      final rows = await supabase // запрос к таблице users
          .from('users') // таблица users
          .select('id, login, full_name, avatar_url') // выбираем нужные поля
          .order('login'); // сортируем по логину

      users = (rows as List) // приводим к списку
          .map<UserModel>(
            (u) => UserModel( // строим UserModel из записи
          id: u['id'] as String, // id пользователя
          login: (u['login'] ?? '') as String, // логин или пустая строка
          fullName: (u['full_name'] ?? '') as String, // ФИО или пустая строка
          avatarUrl: u['avatar_url'] as String?, // путь к аватару или null
        ),
      )
          .toList(); // превращаем в обычный List<UserModel>
    } catch (e) {
      error = 'Не удалось загрузить пользователей: $e'; // сохраняем текст ошибки
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор, если виджет жив
    }
  }

  ImageProvider _avatarFor(UserModel u) { // аватар для пользователя
    final path = (u.avatarUrl ?? '').trim(); // берём путь и обрезаем пробелы
    if (path.isNotEmpty) { // если путь не пустой
      return NetworkImage( // грузим картинку по сети
        publicUrl(
          bucket: avatarsBucketName, // используем бакет avatars
          objectKey: path, // относительный путь к файлу
        ),
      );
    }
    return const AssetImage('assets/profile0.jpg'); // иначе дефолтная аватарка из assets
  }

  void _openUser(UserModel u) { // редактирование пользователя
    Navigator.of(context).push( // открываем новый экран
      MaterialPageRoute(
        builder: (_) => UserEditScreen( // экран редактирования пользователя
          userId: u.id, // передаём id пользователя, которого редактируем
          isSelf: u.id == widget.currentUserId, // если id совпал с текущим — это "я"
          onToggleTheme: widget.onToggleTheme, // пробрасываем переключатель темы
        ),
      ),
    );
  }

  Future<void> _openCreateUser() async { // открыть экран создания пользователя
    final created = await Navigator.of(context).push<bool>( // ждём результат с экрана
      MaterialPageRoute(
        builder: (_) => CreateUserScreen( // форма создания пользователя
          onToggleTheme: widget.onToggleTheme, // пробрасываем переключатель темы
        ),
      ),
    );
    if (created == true) { // если экран вернул true
      await _loadUsers(); // перегружаем список
    }
  }

  @override
  Widget build(BuildContext context) { // сборка UI списка пользователей
    final Widget body = loading // выбираем, что показывать
        ? const Center(child: CircularProgressIndicator()) // если идёт загрузка — индикатор
        : (error != null // если есть ошибка
        ? Center(
      child: Text(
        error!, // текст ошибки
        style: const TextStyle(color: Colors.red), // красный цвет
      ),
    )
        : ListView( // если всё ок — список пользователей
      padding: const EdgeInsets.all(16), // отступы вокруг
      children: [
        ...List.generate(users.length, (i) { // генерируем элементы списка по количеству пользователей
          final u = users[i]; // текущий пользователь
          final avatar = _avatarFor(u); // получаем картинку для аватара
          return GestureDetector( // оборачиваем в GestureDetector для обработки onTap
            onTap: () => _openUser(u), // по тапу открываем редактирование
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4), // вертикальный отступ
              padding: const EdgeInsets.symmetric(vertical: 8), // внутренний отступ по вертикали
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20, // размер аватарки
                    backgroundImage: avatar, // картинка аватара
                  ),
                  const SizedBox(width: 12), // отступ между аватаркой и текстом
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, // текст слева
                      children: [
                        Text(
                          u.login, // показываем логин
                          style: const TextStyle(
                            fontWeight: FontWeight.bold, // делаем логин жирным
                          ),
                        ),
                        if (u.fullName.isNotEmpty) // если ФИО не пустое
                          Text(
                            u.fullName, // показываем ФИО
                            style: Theme.of(context).textTheme.bodySmall, // стиль мелкого текста
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right), // стрелочка перехода
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8), // отступ перед "добавить пользователя"
        GestureDetector(
          onTap: _openCreateUser, // открываем форму создания пользователя
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12), // отступы
            child: Row(
              children: const [
                Icon(Icons.add), // иконка плюс
                SizedBox(width: 8), // отступ
                Text('[добавить пользователя]'), // текст-ссылка
              ],
            ),
          ),
        ),
      ],
    ));

    return Scaffold( // каркас экрана
      appBar: AppBar(
        title: const Text('Пользователи'), // заголовок экрана
        actions: [
          IconButton(
            tooltip: 'Тема', // ДОБАВИЛ: переключатель темы в списке пользователей
            icon: const Icon(Icons.brightness_6), // иконка смены темы
            onPressed: widget.onToggleTheme, // вызываем колбэк смены темы
          ),
        ],
      ),
      body: body, // подставляем тело экрана
    );
  }
}

class UserEditScreen extends StatefulWidget { // экран редактирования пользователя / личного кабинета
  final String userId; // id пользователя, которого редактируем
  final bool isSelf; // true — "Личный кабинет", false — админ редактирует другого
  final VoidCallback onToggleTheme; // ДОБАВИЛ: колбэк переключения темы
  const UserEditScreen({ // конструктор экрана редактирования
    super.key, // пробрасываем key
    required this.userId, // обязательный id
    required this.isSelf, // флаг "сам себя" или "кто-то другой"
    required this.onToggleTheme, // обязательный колбэк смены темы
  });

  @override
  State<UserEditScreen> createState() => _UserEditScreenState(); // создаём состояние
}

class _UserEditScreenState extends State<UserEditScreen> { // состояние экрана редактирования пользователя
  final loginCtrl = TextEditingController(); // логин
  final fullNameCtrl = TextEditingController(); // ФИО
  final emailCtrl = TextEditingController(); // email
  final passwordCtrl = TextEditingController(); // новый пароль

  String twoFactorType = 'auto'; // текущий режим 2FA
  String? avatarPath; // относительный путь аватарки в bucket avatars

  Uint8List? _avatarBytes; // байты выбранного файла
  String? _avatarName; // имя файла

  bool loading = true; // индикатор загрузки
  bool saving = false; // индикатор сохранения
  String? error; // ошибка

  static const List<String> _twoFaOptions = ['auto', 'email', 'none']; // варианты 2FA

  @override
  void initState() { // инициализация экрана
    super.initState(); // базовый initState
    _load(); // загружаем данные пользователя
  }

  Future<void> _load() async { // загрузка данных пользователя из БД
    setState(() {
      loading = true; // включаем индикатор
      error = null; // очищаем ошибку
    });
    try {
      final row = await supabase // запрос к таблице users
          .from('users') // таблица users
          .select('login, full_name, email, avatar_url, two_factor_type') // выбираем нужные поля
          .eq('id', widget.userId) // фильтр по id
          .maybeSingle(); // либо одна строка, либо null

      if (row == null) { // если не нашли пользователя
        throw Exception('Пользователь не найден'); // бросаем исключение
      }

      loginCtrl.text = (row['login'] ?? '') as String; // заполняем контрол логина
      fullNameCtrl.text = (row['full_name'] ?? '') as String; // контрол ФИО
      emailCtrl.text = (row['email'] ?? '') as String; // контрол email
      avatarPath = row['avatar_url'] as String?; // путь к аватарке
      twoFactorType = (row['two_factor_type'] ?? 'auto') as String; // текущий тип 2FA
    } catch (e) {
      error = 'Не удалось загрузить данные: $e'; // сохраняем текст ошибки
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор
    }
  }

  bool get _avatarIsImage { // проверка, что выбранный файл — картинка
    final name = (_avatarName ?? '').toLowerCase(); // имя файла в нижнем регистре
    return name.endsWith('.jpg') || // jpg
        name.endsWith('.jpeg') || // jpeg
        name.endsWith('.png') || // png
        name.endsWith('.gif') || // gif
        name.endsWith('.webp'); // webp
  }

  Future<void> _pickAvatar() async { // выбрать файл для аватарки
    final res = await FilePicker.platform.pickFiles( // открываем диалог выбора файла
      allowMultiple: false, // только один файл
      type: FileType.image, // тип файлa — картинка
      withData: kIsWeb, // на web сразу читаем bytes
    );
    if (res == null || res.files.isEmpty) return; // если пользователь отменил — выходим
    final f = res.files.single; // берём один выбранный файл

    Uint8List? bytes = f.bytes; // пробуем взять bytes из результата
    if (bytes == null && f.path != null && !kIsWeb) { // если bytes нет и мы не web
      bytes = await File(f.path!).readAsBytes(); // читаем файл с диска
    }
    if (bytes == null) { // если так и не получили данные
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прочитать файл аватарки')), // показываем ошибку
        );
      }
      return; // выходим
    }
    setState(() {
      _avatarBytes = bytes; // сохраняем байты картинки
      _avatarName = f.name; // сохраняем имя файла
    });
  }

  Future<void> _uploadAvatar() async { // загрузка аватара в avatars
    if (_avatarBytes == null) { // если ещё не выбрали файл
      await _pickAvatar(); // открываем выбор
      if (_avatarBytes == null) return; // если всё равно нет — выходим
    }
    setState(() {
      saving = true; // включаем индикатор сохранения
      error = null; // очищаем ошибку
    });
    try {
      String ext = 'jpg'; // расширение по умолчанию
      final name = (_avatarName ?? '').trim(); // имя файла без пробелов
      final dot = name.lastIndexOf('.'); // ищем точку
      if (dot > 0 && dot < name.length - 1) { // если точка есть и не в конце
        ext = name.substring(dot + 1).toLowerCase(); // берём расширение
      }
      final objectKey =
          '${widget.userId}/${DateTime.now().millisecondsSinceEpoch}.$ext'; // путь в бакете: userId/timestamp.ext
      await supabase.storage // обращаемся к storage
          .from(avatarsBucketName) // бакет avatars
          .uploadBinary(objectKey, _avatarBytes!, // загружаем байты
          fileOptions: FileOptions(upsert: true)); // ДОБАВИЛ: без const, чтобы не было ошибки const-выражения

      setState(() {
        avatarPath = objectKey; // сохраняем относительный путь в поле
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Аватарка загружена'))); // уведомляем об успехе
      }
    } catch (e) {
      setState(() => error = 'Ошибка загрузки аватарки: $e'); // сохраняем ошибку
    } finally {
      if (mounted) setState(() => saving = false); // выключаем индикатор сохранения
    }
  }

  void _openAvatarFull() { // открыть аватарку на полный экран
    if (_avatarBytes != null && _avatarIsImage) { // если есть локальные байты и это картинка
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewScreen(imageBytes: _avatarBytes), // показываем картинку из памяти
        ),
      );
    } else if (avatarPath != null && avatarPath!.isNotEmpty) { // если есть путь в бакете
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewScreen( // открываем просмотрщик
            imageAsset: publicUrl(
              bucket: avatarsBucketName, // бакет avatars
              objectKey: avatarPath!, // относительный путь файла
            ),
          ),
        ),
      );
    }
  }

  Future<void> _save() async { // сохранить изменения
    setState(() {
      saving = true; // включаем индикатор
      error = null; // очищаем ошибку
    });
    try {
      await supabase.from('users').update({ // обновляем запись в таблице users
        'login': loginCtrl.text.trim(), // логин
        'full_name': fullNameCtrl.text.trim(), // ФИО
        'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(), // email или null
        'avatar_url': (avatarPath ?? '').trim().isNotEmpty ? avatarPath : null, // относительный путь к аватарке или null
        'two_factor_type': twoFactorType, // выбранный тип 2FA
      }).eq('id', widget.userId); // по id пользователя

      if (widget.isSelf) { // если редактируем сами себя
        final attrs = UserAttributes( // создаём объект с изменяемыми полями учётки
          email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(), // новый email или null
          password:
          passwordCtrl.text.isNotEmpty ? passwordCtrl.text : null, // новый пароль или null
        );
        if (attrs.email != null || attrs.password != null) { // если есть что менять
          await supabase.auth.updateUser(attrs); // обновляем auth-профиль
        }
      }
      if (mounted) Navigator.of(context).pop(true); // закрываем экран и возвращаем true
    } catch (e) {
      setState(() => error = 'Не удалось сохранить: $e'); // сохраняем ошибку
    } finally {
      if (mounted) setState(() => saving = false); // выключаем индикатор
    }
  }

  @override
  Widget build(BuildContext context) { // сборка UI редактора пользователя
    final title =
    widget.isSelf ? 'Личный кабинет' : 'Редактирование пользователя'; // заголовок в зависимости от режима
    if (loading) { // если ещё грузим
      return Scaffold(
        appBar: AppBar(
          title: Text(title), // заголовок
          actions: [
            IconButton(
              tooltip: 'Тема', // ДОБАВИЛ: переключатель темы в Личном кабинете/редакторе пользователя
              icon: const Icon(Icons.brightness_6), // иконка темы
              onPressed: widget.onToggleTheme, // вызываем колбэк темы
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()), // индикатор загрузки
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title), // заголовок
        actions: [
          IconButton(
            tooltip: 'Тема', // ДОБАВИЛ: переключатель темы в Личном кабинете/редакторе пользователя
            icon: const Icon(Icons.brightness_6), // иконка темы
            onPressed: widget.onToggleTheme, // вызываем колбэк темы
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16), // отступы
        children: [
          TextField(
            controller: loginCtrl, // контрол логина
            decoration: const InputDecoration(labelText: 'Логин'), // подпись
          ),
          const SizedBox(height: 8), // отступ
          TextField(
            controller: fullNameCtrl, // контрол ФИО
            decoration: const InputDecoration(labelText: 'ФИО'), // подпись
          ),
          const SizedBox(height: 8), // отступ
          TextField(
            controller: emailCtrl, // контрол email
            decoration: const InputDecoration(labelText: 'Email'), // подпись
          ),
          const SizedBox(height: 12), // отступ
          DropdownButtonFormField<String>( // селект выбора метода 2FA
            value: _twoFaOptions.contains(twoFactorType)
                ? twoFactorType // если текущее значение в списке — берём его
                : 'auto', // иначе auto по умолчанию
            items: _twoFaOptions
                .map(
                  (v) => DropdownMenuItem( // элемент выпадающего списка
                value: v, // значение
                child: Text(
                  v == 'auto'
                      ? 'auto (по умолчанию)' // подпись для auto
                      : v == 'email'
                      ? 'email (код по почте)' // подпись для email
                      : 'none (без 2FA)', // подпись для none
                ),
              ),
            )
                .toList(), // превращаем в список
            onChanged: (v) {
              if (v == null) return; // если null — игнорируем
              setState(() => twoFactorType = v); // сохраняем новый тип 2FA
            },
            decoration: const InputDecoration(
              labelText: 'Метод 2FA', // подпись поля
            ),
          ),
          const SizedBox(height: 12), // отступ
          Row(
            children: [
              Expanded(
                child: TextField(
                  readOnly: true, // поле только для чтения
                  controller: TextEditingController(text: avatarPath ?? ''), // показываем текущий путь к аватарке
                  decoration: const InputDecoration(
                    labelText: 'Путь к аватарке (relative в avatars)', // подпись поля
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8), // отступ
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: saving ? null : _pickAvatar, // если идёт сохранение — блокируем, иначе выбираем файл
                icon: const Icon(Icons.image), // иконка выбора изображения
                label:
                Text(_avatarName == null ? 'Выбрать аватар' : _avatarName!), // текст кнопки: либо "выбрать", либо имя файла
              ),
              const SizedBox(width: 8), // отступ
              ElevatedButton.icon(
                onPressed: saving ? null : _uploadAvatar, // кнопка загрузки аватарки
                icon: const Icon(Icons.cloud_upload), // иконка облака
                label: const Text('Загрузить в avatars'), // текст кнопки
              ),
            ],
          ),
          const SizedBox(height: 8), // отступ
          if (_avatarBytes != null ||
              (avatarPath != null && avatarPath!.isNotEmpty)) ...[ // если есть аватар для предпросмотра
            Text(
              'Предпросмотр аватарки:', // заголовок предпросмотра
              style: Theme.of(context).textTheme.bodySmall, // стиль мелкого текста
            ),
            const SizedBox(height: 6), // отступ
            GestureDetector(
              onTap: _openAvatarFull, // по тапу открываем на полный экран
              child: Builder(
                builder: (context) {
                  ImageProvider? img; // сюда положим источник картинки
                  if (_avatarBytes != null && _avatarIsImage) { // если есть bytes
                    img = MemoryImage(_avatarBytes!); // создаём MemoryImage
                  } else if (avatarPath != null &&
                      avatarPath!.isNotEmpty) { // иначе пробуем url
                    img = NetworkImage(
                      publicUrl(
                        bucket: avatarsBucketName, // бакет avatars
                        objectKey: avatarPath!, // путь к файлу
                      ),
                    );
                  }
                  return CircleAvatar(
                    radius: 40, // размер кружка
                    backgroundColor: Theme.of(context).cardColor, // фон кружка
                    backgroundImage: img, // сама картинка
                    child: img == null
                        ? const Icon(Icons.person, size: 40) // иконка, если картинки нет
                        : null,
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12), // отступ
          if (widget.isSelf) ...[ // доп. поля только для личного кабинета
            TextField(
              controller: passwordCtrl, // контрол для нового пароля
              obscureText: true, // скрываем ввод
              decoration: const InputDecoration(
                labelText: 'Новый пароль (опционально)', // подпись
                helperText: 'Если оставить пустым — пароль не изменится', // подсказка
              ),
            ),
            const SizedBox(height: 12), // отступ
          ],
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)), // показываем текст ошибки
          const SizedBox(height: 8), // отступ
          ElevatedButton(
            onPressed: saving ? null : _save, // кнопка "Сохранить"
            child: saving
                ? const CircularProgressIndicator() // если идёт сохранение — индикатор
                : const Text('Сохранить'), // иначе текст
          ),
        ],
      ),
    );
  }
}
class CreateUserScreen extends StatefulWidget { // экран создания пользователя
  final VoidCallback onToggleTheme; // ДОБАВИЛ: колбэк переключения темы
  const CreateUserScreen({super.key, required this.onToggleTheme}); // конструктор принимает колбэк темы
  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState(); // создаём состояние
}
class _CreateUserScreenState extends State<CreateUserScreen> { // состояние экрана создания пользователя
  final loginCtrl = TextEditingController(); // логин
  final fullNameCtrl = TextEditingController(); // ФИО
  final emailCtrl = TextEditingController(); // email
  final passwordCtrl =
  TextEditingController(); // пароль (пока не используется на бэке)
  String twoFactorType = 'auto'; // метод 2FA по умолчанию
  Uint8List? _avatarBytes; // байты выбранного аватара
  String? _avatarName; // имя файла аватара
  String? avatarPath; // относительный путь в avatars
  bool saving = false; // флаг сохранения
  String? error; // текст ошибки

  bool get _avatarIsImage { // проверка, что выбранный файл — картинка
    final name = (_avatarName ?? '').toLowerCase(); // имя файла в нижнем регистре
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp'); // набор допустимых расширений
  }
  Future<void> _pickAvatar() async { // выбор файла аватарки
    final res = await FilePicker.platform.pickFiles( // диалог выбора файла
      allowMultiple: false, // только один файл
      type: FileType.image, // только изображения
      withData: kIsWeb, // на web сразу берём bytes
    );
    if (res == null || res.files.isEmpty) return; // если отменили выбор — выходим
    final f = res.files.single; // берём один файл
    Uint8List? bytes = f.bytes; // пробуем взять bytes из результата
    if (bytes == null && f.path != null && !kIsWeb) { // если не web и нет bytes
      bytes = await File(f.path!).readAsBytes(); // читаем файл с диска
    }
    if (bytes == null) { // если bytes так и нет
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прочитать файл')), // показываем ошибку
        );
      }
      return; // выходим
    }
    setState(() {
      _avatarBytes = bytes; // сохраняем байты аватарки
      _avatarName = f.name; // сохраняем имя файла
    });
  }
  Future<void> _uploadAvatar() async { // загрузка аватара в бакет
    if (_avatarBytes == null) { // если ещё нет байтов
      await _pickAvatar(); // просим выбрать файл
      if (_avatarBytes == null) return; // если не выбрали — выходим
    }
    setState(() {
      saving = true; // включаем индикатор сохранения
      error = null; // очищаем ошибку
    });
    try {
      String ext = 'jpg'; // расширение по умолчанию
      final name = (_avatarName ?? '').trim(); // имя файла
      final dot = name.lastIndexOf('.'); // индекс точки
      if (dot > 0 && dot < name.length - 1) { // если точка не в начале/конце
        ext = name.substring(dot + 1).toLowerCase(); // берём расширение
      }
      final objectKey =
          'new-users/${DateTime.now().millisecondsSinceEpoch}.$ext'; // путь в бакете для новых пользователей
      await supabase.storage // обращаемся к storage
          .from(avatarsBucketName) // бакет avatars
          .uploadBinary(objectKey, _avatarBytes!, // загружаем bytes
          fileOptions: FileOptions(upsert: true)); // ДОБАВИЛ: без const

      setState(() {
        avatarPath = objectKey; // сохраняем относительный путь
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Аватарка загружена'))); // уведомляем об успехе
      }
    } catch (e) {
      setState(() => error = 'Ошибка загрузки аватарки: $e'); // сохраняем текст ошибки
    } finally {
      if (mounted) setState(() => saving = false); // выключаем индикатор
    }
  }

  void _openAvatarFull() { // открыть аватар на полный экран
    if (_avatarBytes != null && _avatarIsImage) { // если есть локальные байты
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewScreen(imageBytes: _avatarBytes), // показываем bytes
        ),
      );
    } else if (avatarPath != null && avatarPath!.isNotEmpty) { // иначе, если есть путь
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewScreen(
            imageAsset: publicUrl(
              bucket: avatarsBucketName, // бакет avatars
              objectKey: avatarPath!, // путь к файлу
            ),
          ),
        ),
      );
    }
  }

  Future<void> _save() async { // сохранить пользователя (пока как заглушка)
    setState(() {
      saving = true; // включаем индикатор
      error = null; // очищаем ошибку
    });
    try {
      // Сейчас это только UI-форма. Реального создания auth-пользователя тут нет.
      // TODO: сделать вызов backend/RPC для реального создания.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Создание пользователя пока не реализовано (нужен backend/RPC).'), // текст-заглушка
        ));
        Navigator.of(context).pop(false); // закрываем экран и возвращаем false
      }
    } catch (e) {
      setState(() => error = 'Ошибка: $e'); // сохраняем текст ошибки
    } finally {
      if (mounted) setState(() => saving = false); // выключаем индикатор
    }
  }

  @override
  Widget build(BuildContext context) { // сборка UI экрана создания пользователя
    return Scaffold(
      appBar: AppBar(
        title: const Text('Создание пользователя'), // заголовок экрана
        actions: [
          IconButton(
            tooltip: 'Тема', // ДОБАВИЛ: переключатель темы на форме создания пользователя
            icon: const Icon(Icons.brightness_6), // иконка темы
            onPressed: widget.onToggleTheme, // вызываем колбэк смены темы
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16), // отступы
        children: [
          TextField(
            controller: loginCtrl, // контрол логина
            decoration: const InputDecoration(labelText: 'Логин'), // подпись
          ),
          const SizedBox(height: 8), // отступ
          TextField(
            controller: fullNameCtrl, // контрол ФИО
            decoration: const InputDecoration(labelText: 'ФИО'), // подпись
          ),
          const SizedBox(height: 8), // отступ
          TextField(
            controller: emailCtrl, // контрол email
            decoration: const InputDecoration(labelText: 'Email'), // подпись
          ),
          const SizedBox(height: 8), // отступ
          TextField(
            controller: passwordCtrl, // контрол пароля
            obscureText: true, // скрываем ввод
            decoration: const InputDecoration(
              labelText: 'Пароль', // подпись
              helperText:
              'Пока только поле формы — сохранение пароля на бэке не реализовано', // подсказка
            ),
          ),
          const SizedBox(height: 12), // отступ
          DropdownButtonFormField<String>( // выбор метода 2FA
            value: twoFactorType, // текущее значение
            items: const [
              DropdownMenuItem(
                  value: 'auto', child: Text('auto (по умолчанию)')), // пункт auto

              DropdownMenuItem(
                  value: 'email', child: Text('email (код по почте)')), // пункт email
              DropdownMenuItem(
                  value: 'none', child: Text('none (без 2FA)')), // пункт none
            ],
            onChanged: (v) {
              if (v == null) return; // защищаемся от null
              setState(() => twoFactorType = v); // обновляем выбранный тип 2FA
            },
            decoration: const InputDecoration(labelText: 'Метод 2FA'), // подпись поля
          ),
          const SizedBox(height: 12), // отступ
          Row(
            children: [
              Expanded(
                child: TextField(
                  readOnly: true, // только просмотр
                  controller: TextEditingController(text: avatarPath ?? ''), // путь к аватарке
                  decoration: const InputDecoration(
                    labelText: 'Путь аватарки (avatars)', // подпись
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8), // отступ
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: saving ? null : _pickAvatar, // если сохраняем — блокируем, иначе выбираем файл
                icon: const Icon(Icons.image), // иконка картинки
                label:
                Text(_avatarName == null ? 'Выбрать аватар' : _avatarName!), // текст кнопки
              ),
              const SizedBox(width: 8), // отступ
              ElevatedButton.icon(
                onPressed: saving ? null : _uploadAvatar, // загрузка файла в бакет
                icon: const Icon(Icons.cloud_upload), // иконка облака
                label: const Text('Загрузить аватар'), // текст
              ),
            ],
          ),
          const SizedBox(height: 8), // отступ
          if (_avatarBytes != null ||
              (avatarPath != null && avatarPath!.isNotEmpty)) ...[ // если есть что показать
            Text(
              'Предпросмотр аватарки:', // заголовок
              style: Theme.of(context).textTheme.bodySmall, // стиль текста
            ),
            const SizedBox(height: 6), // отступ
            GestureDetector(
              onTap: _openAvatarFull, // при нажатии открываем на весь экран
              child: Builder(
                builder: (context) {
                  ImageProvider? img; // источник картинки
                  if (_avatarBytes != null && _avatarIsImage) { // если есть bytes
                    img = MemoryImage(_avatarBytes!); // MemoryImage
                  } else if (avatarPath != null &&
                      avatarPath!.isNotEmpty) { // если есть путь
                    img = NetworkImage(
                      publicUrl(
                        bucket: avatarsBucketName, // бакет avatars
                        objectKey: avatarPath!, // путь к файлу
                      ),
                    );
                  }
                  return CircleAvatar(
                    radius: 40, // размер
                    backgroundColor: Theme.of(context).cardColor, // цвет фона
                    backgroundImage: img, // картинка
                    child: img == null
                        ? const Icon(Icons.person, size: 40) // иконка, если аватара нет
                        : null,
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12), // отступ
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)), // показываем ошибку
          const SizedBox(height: 8), // отступ
          ElevatedButton(
            onPressed: saving ? null : _save, // кнопка "Сохранить"
            child: saving
                ? const CircularProgressIndicator() // индикатор при сохранении
                : const Text('Сохранить (UI-заглушка)'), // текст, пока это заглушка
          ),
        ],
      ),
    );
  }
}
