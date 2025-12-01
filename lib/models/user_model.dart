class UserModel { // простая модель пользователя для удобной передачи данных по приложению
  final String id; // id пользователя в auth/таблице users
  final String login; // логин пользователя (уникальное короткое имя)
  final String fullName; // полное имя пользователя (ФИО)
  final String? avatarUrl; // относительный путь или абсолютный URL аватарки (может быть null)

  const UserModel({ // конструктор модели пользователя
    required this.id, // обязателен id пользователя
    required this.login, // обязателен логин
    required this.fullName, // обязательно ФИО
    this.avatarUrl, // аватарка может отсутствовать
  });
}
