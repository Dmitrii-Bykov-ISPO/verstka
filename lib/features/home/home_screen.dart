import 'package:flutter/material.dart'; // UI
import 'package:provider/provider.dart'; // Consumer / context.read для MyEventsState
import '../../core/app_services.dart'; // глобальный supabase и buckets
import '../../models/user_model.dart'; // UserModel
import '../posts/posts_repository.dart'; // PostModel + PostsRepository
import '../events/events_data.dart'; // MyEventsState
import '../events/events_screens.dart'; // EventsScreen
import '../users/users_screens.dart'; // UsersScreen + UserEditScreen
import '../../widgets/app_header.dart'; // AppHeader
import '../../widgets/info_card.dart'; // InfoCard
import '../../widgets/post_card.dart'; // PostCard

class HomeScreen extends StatefulWidget { // главный экран после входа, со стейтом
  final String currentUserId; // id текущего пользователя
  final VoidCallback onSignOut; // колбэк выхода
  final VoidCallback onToggleTheme; // колбэк переключения темы (передаём в шапку и дочерние экраны)
  const HomeScreen({ // конструктор главного экрана
    super.key, // пробрасываем key в базовый класс
    required this.currentUserId, // обязательный параметр с id пользователя
    required this.onSignOut, // обязательный колбэк выхода
    required this.onToggleTheme, // обязательный колбэк переключения темы
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState(); // создаём состояние для этого экрана
}

class _HomeScreenState extends State<HomeScreen> { // приватное состояние главного экрана
  late final PostsRepository repo; // репозиторий постов
  List<PostModel> posts = const []; // список постов
  bool loading = true; // флаг индикатора загрузки
  UserModel? me; // данные текущего пользователя
  bool isAdmin = false; // флаг администратора

  @override
  void initState() { // метод инициализации состояния
    // инициализация состояния
    super.initState(); // вызываем базовый initState
    repo = PostsRepository(supabase); // создаём репозиторий постов с глобальным supabase
    WidgetsBinding.instance.addPostFrameCallback((_) { // планируем колбэк после построения первого кадра
      if (mounted) { // проверяем, что виджет ещё в дереве
        context.read<MyEventsState>().reloadStats(); // перезагружаем статистику событий из provider
      }
    });
    _loadAll(); // загружаем данные пользователя и постов
  }

  Future<void> _loadAll() async { // приватный метод загрузки пользователя и постов
    setState(() => loading = true); // включаем индикатор загрузки
    try {
      final u = await supabase // делаем запрос к таблице users
          .from('users') // таблица users
          .select('id, login, full_name, avatar_url') // выбираем нужные поля
          .eq('id', widget.currentUserId) // фильтруем по id текущего пользователя
          .single(); // один пользователь
      me = UserModel( // создаём модель пользователя
        id: u['id'] as String, // приводим id к String
        login: (u['login'] ?? '') as String, // логин или пустая строка
        fullName: (u['full_name'] ?? '') as String, // ФИО или пустая строка
        avatarUrl: u['avatar_url'] as String?, // относительный путь к аватарке или null
      );
      final loginLower = (me?.login ?? '').toLowerCase(); // логин в нижнем регистре
      isAdmin = loginLower == 'bykovda'; // админ — bykovda
      posts = await repo.loadPosts(); // загружаем посты из репозитория
    } finally {
      if (mounted) setState(() => loading = false); // выключаем индикатор, если экран ещё в дереве
    }
  }

  String _timeAgo(DateTime dt) { // вспомогательная функция для отображения времени "n минут назад"
    // "n минут/часов/дней назад"
    final d = DateTime.now().difference(dt); // разница между сейчас и переданной датой
    return d.inMinutes < 60 // если прошло меньше часа
        ? '${d.inMinutes} минут назад' // показываем в минутах
        : d.inHours < 24 // иначе если прошло меньше суток
        ? '${d.inHours} часов назад' // показываем в часах
        : '${d.inDays} дн. назад'; // иначе показываем дни
  }

  String _greeting(UserModel? u) { // приветствие по времени суток и имени
    final name = (u?.fullName ?? '').trim(); // имя пользователя без пробелов по краям
    final h = DateTime.now().hour; // текущий час
    final g = (h >= 4 && h < 12) // выбираем текст приветствия по часу
        ? 'Доброе утро' // 4-11
        : (h < 17) // до 17
        ? 'Добрый день' // дневное время
        : (h < 22) // до 22
        ? 'Добрый вечер' // вечер
        : 'Доброй ночи'; // поздняя ночь
    return name.isEmpty ? 'Здравствуйте!' : '$g, $name!'; // если имени нет — просто "Здравствуйте!", иначе с именем
  }

  void _goHome(BuildContext context) => // навигация на корневой маршрут
  Navigator.of(context).popUntil((route) => route.isFirst); // назад до корня

  void _stub(BuildContext ctx, String msg) => // простая заглушка для будущих экранов
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg))); // показываем snackbar с текстом

  void _openEvents() { // открыть экран событий
    Navigator.of(context).push( // пушим новый маршрут
      MaterialPageRoute( // стандартный material-route
        builder: (_) => EventsScreen( // создаём экран событий
          onToggleTheme: widget.onToggleTheme, // пробрасываем переключение темы в "События"
        ),
      ),
    );
  }

  void _openSelfAccount() { // открыть "Личный кабинет"
    Navigator.of(context).push( // открываем экран редактирования
      MaterialPageRoute(
        builder: (_) => UserEditScreen( // используем экран редактирования пользователя
          userId: widget.currentUserId, // редактируем себя
          isSelf: true, // режим "личный кабинет"
          onToggleTheme: widget.onToggleTheme, // пробрасываем переключение темы в личный кабинет
        ),
      ),
    );
  }

  void _openProfileStub() { // заглушка "Профиль"
    ScaffoldMessenger.of(context).showSnackBar( // показываем snackbar
      const SnackBar(content: Text('Моя страница (заглушка)')), // текст заглушки
    );
  }

  void _openUsersScreen() { // открыть экран пользователей (только для админа)
    if (!isAdmin) { // если я не админ
      _stub(context, 'Экран пользователей доступен только администратору'); // показываем предупреждение
      return; // выходим из метода
    }
    Navigator.of(context).push( // если админ — открываем экран
      MaterialPageRoute(
        builder: (_) => UsersScreen( // экран списка пользователей
          currentUserId: widget.currentUserId, // id текущего пользователя
          onToggleTheme: widget.onToggleTheme, // пробрасываем переключение темы в список пользователей
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) { // метод сборки UI
    final list = loading // выбираем, что показывать: индикатор или список
        ? const Center(child: CircularProgressIndicator()) // если грузим — круговой индикатор
        : ListView( // иначе список
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // отступы списка
      children: [
        Row( // первая строка с карточками
          children: [
            const Expanded( // первая карточка "новости"
              child: InfoCard(
                icon: Icons.notifications, // иконка уведомлений
                iconColor: Colors.yellow, // цвет иконки
                title: '10 новостей', // заголовок карты (пока захардкожено)
              ),
            ),
            Consumer<MyEventsState>( // Consumer следит за MyEventsState
              builder: (ctx, eventsState, _) { // билдер получает текущее состояние событий
                final myEventsCount = eventsState.stats.total; // количество будущих событий
                final hasTodayEvent = eventsState.stats.hasToday; // флаг "есть сегодня"
                final loadingStats = eventsState.loading; // грузим ли статистику

                final title = loadingStats // вычисляем текст заголовка
                    ? 'Загрузка...' // если ещё грузим
                    : '$myEventsCount событ${myEventsCount == 1 ? "ие" : (myEventsCount >= 2 && myEventsCount <= 4 ? "ия" : "ий")}'; // склонение слова "событие"

                return Expanded( // вторая карточка со счётчиком событий
                  child: Stack( // Stack чтобы положить поверх красную точку и кликабельный слой
                    children: [
                      InfoCard( // сама карточка
                        icon: Icons.event, // иконка календаря
                        iconColor:
                        myEventsCount > 0 ? Colors.green : Colors.grey, // цвет иконки в зависимости от количества
                        title: title, // текст заголовка
                      ),
                      if (hasTodayEvent) // если есть событие сегодня
                        Positioned(
                          right: 12, // отступ справа
                          top: 8, // отступ сверху
                          child: Container(
                            width: 10, // ширина индикатора
                            height: 10, // высота индикатора
                            decoration: const BoxDecoration(
                              color: Colors.red, // красная точка
                              shape: BoxShape.circle, // круглая форма
                            ),
                          ),
                        ),
                      Positioned.fill( // делаем всю карточку нажимаемой
                        child: Material(
                          color: Colors.transparent, // прозрачный фон, чтобы не перекрывать стиль
                          child: InkWell(onTap: _openEvents), // по тапу открываем экран событий
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16), // отступ между карточкой и постами
        ...posts.expand((p) sync* { // разворачиваем посты в список виджетов
          yield PostCard.buildFromData( // строим карточку поста
            context: context, // контекст
            profileAsset: p.authorAvatarUrl ??
                'assets/profile0.jpg', // если нет url аватара — локальный ассет
            name: p.authorName, // имя автора
            time: _timeAgo(p.createdAt), // "сколько назад"
            caption: p.text, // текст поста
            photos: p.imageUrls, // список фото
          );
          yield const SizedBox(height: 16); // отступ между постами
        }),
        if (isAdmin) ...[ // если пользователь админ — показываем кнопку "Пользователи"
          const SizedBox(height: 16), // отступ перед кнопкой
          ElevatedButton.icon(
            onPressed: _openUsersScreen, // при нажатии открываем список пользователей
            icon: const Icon(Icons.people), // иконка людей
            label: const Text('Пользователи'), // текст кнопки
          ),
        ],
        const SizedBox(height: 80), // нижний отступ, чтобы не упиралось в нижний бар
      ],
    );

    return Scaffold( // основной каркас экрана
      body: SafeArea( // учитываем вырезы/статусбар
        child: Column( // вертикальная раскладка
          children: [
            AppHeader( // шапка приложения
              greeting: _greeting(me), // приветствие с именем
              currentUserLogin: me?.login, // логин пользователя
              currentUserAvatarUrl: me?.avatarUrl, // аватарка пользователя (relative path)
              onToggleTheme: widget.onToggleTheme, // даём шапке колбэк переключения темы
              onSignOut: widget.onSignOut, // колбэк выхода
              onOpenAccount: _openSelfAccount, // открыть личный кабинет
              onOpenProfile: _openProfileStub, // заглушка профиля
            ),
            const SizedBox(height: 12), // отступ между шапкой и контентом
            Expanded(child: list), // разворачиваем список на всё оставшееся место
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar( // нижняя панель навигации
        shape: const CircularNotchedRectangle(), // форма с вырезом под FAB (если будет)
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0), // горизонтальные отступы
          child:
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ // строка с иконками навигации
            Row( // группа иконок слева
              children: [
                IconButton(
                    icon: const Icon(Icons.home), // иконка домика
                    onPressed: () => _goHome(context)), // домой (на корневой маршрут)
                IconButton(
                    icon: const Icon(Icons.search), // иконка поиска
                    onPressed: () => _stub(context, 'Поиск (заглушка)')), // поиск (пока заглушка)
                IconButton(
                    icon: const Icon(Icons.person), // иконка профиля
                    onPressed: () => _stub(context, 'Профиль (заглушка)')), // профиль (пока заглушка)
                IconButton(icon: const Icon(Icons.event), onPressed: _openEvents), // иконка событий, открывает экран событий
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
