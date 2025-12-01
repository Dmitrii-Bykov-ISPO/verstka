import 'package:flutter/material.dart'; // базовый Flutter UI toolkit
import 'package:provider/provider.dart'; // provider для глобального состояния (события)
import 'package:shared_preferences/shared_preferences.dart'; // локальное хранилище для темы
import 'package:supabase_flutter/supabase_flutter.dart'; // инициализация supabase и auth

import 'core/app_services.dart'; // supabase-конфиг, buckets, глобальный supabase-клиент
import 'features/auth/auth.dart'; // AuthService + LoginScreen
import 'features/home/home_screen.dart'; // главный экран после входа
import 'features/events/events_data.dart'; // EventsRepository + MyEventsState
import 'features/common/photo_view_screen.dart'; // экран просмотра фото

// контроллер темы, наследуемся от ChangeNotifier, чтобы уведомлять ui о смене темы
class ThemeController extends ChangeNotifier { // класс, который хранит и переключает тему приложения
  ThemeMode _mode = ThemeMode.system; // приватное поле текущего режима темы, по умолчанию берем системный

  ThemeMode get mode => _mode; // публичный геттер, чтобы только читать текущее значение темы снаружи

  Future<void> load() async { // метод загружает сохранённый режим темы из локального хранилища
    // метод загружает сохранённый режим темы из локального хранилища
    final prefs = await SharedPreferences.getInstance(); // получаем экземпляр shared preferences
    final v = prefs.getString('theme_mode'); // читаем строку по ключу theme_mode
    _mode = v == 'light' // выбираем режим по сохранённой строке
        ? ThemeMode.light // если записано light — включаем светлую тему
        : v == 'dark' // иначе если dark — тёмную
        ? ThemeMode.dark // соответствующее значение
        : ThemeMode.system; // иначе оставляем системную по умолчанию
    notifyListeners(); // уведомляем слушателей (виджеты), что состояние изменилось
  }

  Future<void> toggle() async { // метод переключает светлая/тёмная тема и сохраняет выбор
    // метод переключает светлая/тёмная тема и сохраняет выбор
    _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light; // если было light — делаем dark и наоборот
    notifyListeners(); // уведомляем ui, чтобы он перерисовался с новой темой
    final prefs = await SharedPreferences.getInstance(); // берём доступ к локальному хранилищу
    await prefs.setString('theme_mode', _mode == ThemeMode.light ? 'light' : 'dark'); // сохраняем выбранный режим строкой, чтобы восстановить при следующем запуске
  }
}

Future<void> main() async {
  // точка входа приложения
  WidgetsFlutterBinding.ensureInitialized(); // инициализируем Flutter до асинхронщины

  await Supabase.initialize( // инициализируем Supabase SDK
    // инициализируем Supabase SDK
    url: supabaseUrl, // адрес проекта
    anonKey: supabaseAnonKey, // публичный anon key
  );
  supabase = Supabase.instance.client; // сохраняем клиент в глобальную переменную

  final current = supabase.auth.currentUser; // читаем текущего пользователя из локальной сессии (если есть)
  runApp(MyApp(initialUserId: current?.id)); // если уже залогинен — сразу в Home, иначе Login
}

class MyApp extends StatefulWidget {
  // корневой виджет c состоянием
  final ThemeController? themeController; // опциональный внешний контроллер темы
  final String? initialUserId; // uid, если пользователь уже залогинен
  const MyApp({super.key, this.themeController, this.initialUserId}); // конструктор, принимает key и стартовый uid/контроллер темы

  @override
  State<MyApp> createState() => _MyAppState(); // создаём состояние для MyApp
}

class _MyAppState extends State<MyApp> { // состояние корневого виджета приложения
  late final ThemeController _theme; // контроллер темы
  late final MyEventsState _eventsState; // глобальное состояние событий (provider)
  String? _userId; // текущий uid пользователя (auth.users.id)
  bool _themeReady = false; // флаг готовности темы

  @override
  void initState() {
    super.initState(); // базовая инициализация
    _theme = widget.themeController ?? ThemeController(); // берём переданный контроллер или создаём свой
    _eventsState = MyEventsState(EventsRepository(supabase)); // создаём глобальное состояние событий
    _userId = widget.initialUserId; // если при старте уже есть пользователь — запоминаем
    _initTheme(); // запускаем загрузку сохранённой темы
  }

  Future<void> _initTheme() async {
    // приватный метод загрузки темы и счётчиков
    await _theme.load(); // читаем режим из SharedPreferences
    await _eventsState.reloadStats(); // сразу пробуем обновить счётчики событий (если уже есть сессия)
    if (!mounted) return; // если виджет уже уничтожен — выходим
    setState(() => _themeReady = true); // отмечаем, что тема готова
  }

  @override
  Widget build(BuildContext context) {
    // метод сборки дерева виджетов для приложения
    if (!_themeReady) {
      // пока тема не загрузилась
      return MaterialApp(
        // рисуем пустое светлое приложение-заглушку
        debugShowCheckedModeBanner: false, // убираем плашку DEBUG
        home: Container(color: Colors.white), // белый экран-заглушка
      );
    }

    return AnimatedBuilder(
      // AnimatedBuilder слушает изменения темы
      animation: _theme, // указываем, за кем следить (ThemeController)
      builder: (_, __) => ChangeNotifierProvider<MyEventsState>.value(
        // провайдер глобального состояния событий
        value: _eventsState, // используем уже созданный инстанс
        child: MaterialApp(
          debugShowCheckedModeBanner: false, // убираем плашку DEBUG
          themeMode: _theme.mode, // текущий режим темы
          theme: ThemeData(
            // светлая тема
            brightness: Brightness.light, // светлый режим
            scaffoldBackgroundColor: const Color(0xFFF5EEDC), // цвет фона экранов
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), // цветовая схема из базового цвета
            snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating), // всплывающие snackbar в светлой теме
          ),
          darkTheme: ThemeData(
            // тёмная тема
            brightness: Brightness.dark, // тёмный режим
            colorScheme: ColorScheme.fromSeed( // создаем цветовую схему для тёмной темы
              seedColor: Colors.teal, // базовый цвет тот же
              brightness: Brightness.dark, // схема под тёмный фон
            ),
            snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating), // snackbar в тёмной теме
          ),
          home: _userId == null // выбираем стартовый экран по наличию авторизованного пользователя
              ? LoginScreen(
            // если пользователь не залогинен — экран входа
            onSignedIn: (uid) async {
              // при успешном входе
              setState(() => _userId = uid); // сохраняем uid
              await _eventsState.reloadStats(); // сразу обновляем счётчики событий
            },
            onToggleTheme: _theme.toggle, // передаём колбэк переключения темы на экран логина
          )
              : HomeScreen(
            // иначе показываем главный экран
            currentUserId: _userId!, // передаём uid
            onSignOut: () async {
              // обработчик выхода
              await AuthService.signOut(); // выходим из supabase.auth
              await _eventsState.reloadStats(); // сбрасываем/обновляем счётчики (будет 0)
              if (mounted) { // проверяем, что виджет ещё актуален
                setState(() => _userId = null); // возвращаемся на экран входа
              }
            },
            onToggleTheme: _theme.toggle, // передаём колбэк переключения темы на главный экран
          ),
          routes: {
            '/photo': (_) => const PhotoViewScreen(), // маршрут просмотра фото
          },
        ),
      ),
    );
  }
}
