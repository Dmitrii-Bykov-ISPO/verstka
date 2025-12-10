
import 'package:flutter/material.dart'; // базовый UI
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // auth, User, AuthException

import '../../core/app_services.dart'; // глобальный supabase-клиент и конфиг

class AuthService { // сервис авторизации
  static SupabaseClient get _supa => Supabase.instance.client; // короткий доступ к клиенту

  static User? get currentUser => _supa.auth.currentUser; // текущий пользователь (или null)

  static Future<void> signOut() async { // выход из аккаунта
    // выход из аккаунта
    await _supa.auth.signOut(); // очищаем сессию и токены
  }

  // Регистрация (пока заглушка без ключа админа)
  static Future<AuthResponse> signUp({ // регистрация нового пользователя
    required String email, // email для входа
    required String password, // пароль
    required String login, // логин (фамилия+инициалы)
    required String fullName, // ФИО
  }) async {
    return _supa.auth.signUp(
      email: email, // почта
      password: password, // пароль
      data: {
        'login': login, // логин в метаданных
        'full_name': fullName, // ФИО в метаданных
      },
    );
  }

  static Future<_TwoFactorPlan> signInWithPasswordAndPlan2FA({ // вход с паролем + план по 2FA
    required String identifier, // логин ИЛИ email
    required String password, // пароль
  }) async {
    final idNorm = identifier.trim().toLowerCase(); // нормализуем ввод (обрезаем пробелы, приводим к нижнему регистру)

    String? email; // сюда положим email

    if (idNorm.contains('@')) { // если похоже на email
      email = idNorm; // используем как есть
    } else {
      // иначе считаем, что это login
      final row = await _supa
          .from('users') // таблица users
          .select('email') // нужен только email
          .eq('login', idNorm) // ищем профиль по login
          .maybeSingle(); // либо одна строка, либо null
      email = row?['email'] as String?; // берём email из профиля
    }
    if (email == null || email.isEmpty) { // если email не найден
      throw AuthException('Пользователь не найден или не задан email'); // выбрасываем ошибку supabase
    }
    final res = await _supa.auth.signInWithPassword( // пробуем войти по email + пароль
      email: email,
      password: password,
    );
    final user = res.user; // получаем пользователя из ответа
    if (user == null) { // если user == null — вход не удался
      throw AuthException('Не удалось войти');
    }

    // 2) Читаем профиль, чтобы понять режим 2FA
    final profile = await _supa
        .from('users') // таблица users
        .select('two_factor_type, email') // интересуют тип 2FA и email
        .eq('id', user.id) // профиль текущего пользователя
        .maybeSingle(); // одна строка или null
    final mode = (profile?['two_factor_type'] as String?) ?? 'auto'; // auto/email/none
    final profileEmail = (profile?['email'] as String?) ?? email; // email из профиля или auth

    if (mode == 'none') { // режим без 2FA
      // без 2FA — оставляем созданную сессию
      return _TwoFactorPlan.none(user.id); // возвращаем план без 2FA
    }
    // 2FA Email
    if ((mode == 'auto' || mode == 'email') && // если режим auto или email
        profileEmail != null &&
        profileEmail.isNotEmpty) { // и есть валидный email
      await _supa.auth.signOut(); // убираем сессию от signInWithPassword
      await _supa.auth.signInWithOtp(
        // отправляем одноразовый код на email
        email: profileEmail, // адрес, куда отправляем код
        shouldCreateUser: false, // не создаём нового пользователя
      );
      return _TwoFactorPlan.email(user.id, profileEmail); // возвращаем план с 2FA по email
    }
    return _TwoFactorPlan.none(user.id); // план без 2FA
  }

  static Future<void> verifyOtp({ // верификация одноразового кода
    required _TwoFactorPlan plan, // план, полученный на первом шаге
    required String code, // код из письма
  }) async {
    if (plan.kind == _TwoFactorKind.none) { // если 2FA не нужна
      return; // ничего не делаем
    }

    if (plan.kind == _TwoFactorKind.email) { // режим 2FA по email
      // verifyOTP создаст НОВУЮ полноценную сессию, если код верный
      await _supa.auth.verifyOTP(
        token: code.trim(), // введённый код без пробелов
        type: OtpType.email, // подтверждаем по email
        email: plan.target, // адрес, на который слали код
      );
      return; // после успешной проверки сессия уже активна
    }
  }
}

enum _TwoFactorKind { none, email } //  перечисление типов 2FA

class _TwoFactorPlan { // внутренний класс плана 2FA
  final String userId; // uid пользователя (из успешного password-логина)
  final _TwoFactorKind kind; // вид 2FA
  final String? target; // email для кода

  _TwoFactorPlan(this.userId, this.kind, this.target); // базовый конструктор

  factory _TwoFactorPlan.none(String userId) => // статический конструктор для режима без 2FA
  _TwoFactorPlan(userId, _TwoFactorKind.none, null);

  factory _TwoFactorPlan.email(String userId, String email) => // статический конструктор для 2FA по email
  _TwoFactorPlan(userId, _TwoFactorKind.email, email);
}

class LoginScreen extends StatefulWidget { // экран логина
  final ValueChanged<String> onSignedIn; // сообщает uid при успешном логине
  final VoidCallback onToggleTheme; // колбэк переключения темы

  const LoginScreen({
    super.key, // пробрасываем key
    required this.onSignedIn, // колбэк при входе
    required this.onToggleTheme, // обязательный параметр
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState(); // создаём состояние
}

class _LoginScreenState extends State<LoginScreen> { // состояние экрана логина
  final loginCtrl = TextEditingController(); // логин или email
  final passCtrl = TextEditingController(); // пароль
  final otpCtrl = TextEditingController(); // код 2FA

  bool loading = false; // идёт ли запрос
  String? error; // текст ошибки
  _TwoFactorPlan? _plan; // текущий план 2FA (null до начала логина)

  bool get _waitingOtp => // признак, что ждём ввод кода
  _plan != null && _plan!.kind != _TwoFactorKind.none; // ждём ли код

  void _reset2FA() { // сброс ожидания кода и плана
    // сброс ожидания кода
    setState(() {
      _plan = null; // план очищаем
      otpCtrl.clear(); // поле кода чистим
      error = null; // ошибки убираем
    });
  }

  Future<void> _startLogin() async { // шаг 1: логин+пароль
    // шаг 1: логин+пароль
    _reset2FA(); // сбрасываем старый план
    setState(() {
      loading = true; // включаем индикатор
      error = null; // очищаем ошибку
    });
    try {
      final plan = await AuthService.signInWithPasswordAndPlan2FA( // вызываем сервис авторизации
        identifier: loginCtrl.text, // логин или email
        password: passCtrl.text, // пароль
      );
      if (plan.kind == _TwoFactorKind.none) { // если 2FA не требуется
        // если 2FA не требуется
        widget.onSignedIn(plan.userId); // сразу пускаем в приложение
      } else {
        // иначе ждём код с почты
        // иначе ждём код с почты
        setState(() {
          _plan = plan; // сохраняем план
        });
      }
    } on AuthException catch (e) { // ошибки авторизации из supabase
      // ошибки авторизации
      setState(() => error = e.message); // сообщение от сервера
    } catch (e) {
      // другие ошибки
      setState(() => error = 'Ошибка входа: $e'); // общий текст ошибки
    } finally {
      if (mounted) {
        setState(() => loading = false); // выключаем индикатор
      }
    }
  }

  Future<void> _confirmOtp() async { // шаг 2: подтверждение кода
    // шаг 2: подтверждение кода
    final plan = _plan; // локальная ссылка
    if (plan == null || plan.kind == _TwoFactorKind.none) { // если плана нет или 2FA не требуется
      return; // ничего не делаем
    }
    setState(() {
      loading = true; // индикатор
      error = null; // убираем ошибку
    });
    try {
      await AuthService.verifyOtp( // отправляем код на проверку
        plan: plan, // план 2FA
        code: otpCtrl.text, // введённый код
      );
      widget.onSignedIn(plan.userId); // пускаем пользователя после успешной проверки кода
    } on AuthException catch (e) { // неверный/просроченный код
      // неверный/просроченный код
      setState(() => error = 'Неверный код: ${e.message}'); // показываем сообщение
    } catch (e) {
      // другие ошибки
      setState(() => error = 'Ошибка подтверждения кода: $e'); // общий текст ошибки
    } finally {
      if (mounted) {
        setState(() => loading = false); // выключаем индикатор
      }
    }
  }

  @override
  Widget build(BuildContext context) { // сборка экрана логина
    final waitingOtp = _waitingOtp; // локальная копия флага ожидания кода

    return Shimmer(
      duration: Duration(seconds: 10), //Default value
      color: Colors.white, //Default value
      colorOpacity: 0, //Default value
      enabled: true, //Default value
      direction: ShimmerDirection.fromLTRB(),  //Default Value
      child:
     Scaffold(
      appBar: AppBar(
        // AppBar, чтобы повесить переключатель темы
        title: const Text('Вход'), // заголовок экрана
        actions: [
          IconButton(
            tooltip: 'Тема', // подсказка
            icon: const Icon(Icons.brightness_6), // иконка переключения темы
            onPressed: widget.onToggleTheme, // вызов колбэка переключения темы
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420), // ограничиваем ширину (удобно для web/desktop)
          child: Padding(
            padding: const EdgeInsets.all(24), // отступы вокруг формы
            child: Column(
              mainAxisSize: MainAxisSize.min, // сжимаем по высоте под содержимое
              children: [
                const Text(
                  'Вход', // заголовок формы
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: loginCtrl, // логин или email
                  enabled: !waitingOtp && !loading, // при ожидании кода блокируем изменение
                  decoration: const InputDecoration(
                    labelText: 'Логин или Email', // подпись поля
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl, // пароль
                  enabled: !waitingOtp && !loading, // тоже блокируем при 2FA
                  obscureText: true, // скрытый ввод
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                  ),
                ),
                const SizedBox(height: 16),
                if (waitingOtp) ...[ // блок ввода кода 2FA
                  TextField(
                    controller: otpCtrl, // поле кода
                    enabled: !loading, // можно вводить, пока не отправляем
                    decoration: const InputDecoration(
                      labelText: 'Код из письма',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Мы отправили код на вашу почту. Введите его, чтобы завершить вход.', // пояснение пользователю
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                ],
                if (error != null) // если есть ошибка
                  Text(
                    error!, // текст ошибки
                    style: const TextStyle(color: Colors.red),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, // кнопки по краям
                  children: [
                    ElevatedButton(
                      onPressed: loading || waitingOtp ? null : _startLogin, // стартуем логин, если не ждём код и не грузимся
                      child: loading && !waitingOtp
                          ? const CircularProgressIndicator() // индикатор при первом шаге
                          : const Text('Войти'), // текст кнопки
                    ),
                    if (waitingOtp) ...[ // дополнительные кнопки при ожидании кода
                      ElevatedButton(
                        onPressed: loading ? null : _confirmOtp, // подтверждаем код
                        child: loading
                            ? const CircularProgressIndicator()
                            : const Text('Подтвердить'),
                      ),
                      TextButton(
                        onPressed: loading ? null : _reset2FA, // сброс процесса 2FA
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
    )

    );
  }
}
