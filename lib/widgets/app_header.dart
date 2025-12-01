import 'package:flutter/material.dart'; // базовые виджеты Flutter
import 'package:ui_example/core/app_services.dart'; // доступ к publicUrl, StringX и имени бакета avatars

enum _HeaderMenuAction { account, profile } // приватное перечисление действий в popup-меню (Личный кабинет / Профиль)

class AppHeader extends StatelessWidget { // виджет шапки приложения (приветствие, аватар, кнопки)
  final String greeting; // текст приветствия
  final String? currentUserLogin; // логин пользователя
  final String? currentUserAvatarUrl; // url или относительный путь аватара
  final VoidCallback onToggleTheme; // колбэк переключения темы
  final VoidCallback onSignOut; // колбэк выхода из аккаунта
  final VoidCallback onOpenAccount; // колбэк открытия "Личного кабинета"
  final VoidCallback onOpenProfile; // колбэк открытия "Профиля" (заглушка)

  const AppHeader({ // конструктор шапки
    super.key, // ключ виджета
    required this.greeting, // обязательное приветствие
    required this.currentUserLogin, // обязательный логин (может быть null по типу)
    required this.currentUserAvatarUrl, // обязательный путь к аватарке (может быть null по типу)
    required this.onToggleTheme, // обязательный колбэк переключения темы
    required this.onSignOut, // обязательный колбэк выхода
    required this.onOpenAccount, // обязательный колбэк "Личный кабинет"
    required this.onOpenProfile, // обязательный колбэк "Профиль"
  });

  ImageProvider _resolveAvatar() { // выбрать источник аватара (сеть или локальный ассет)
    if ((currentUserAvatarUrl?.isHttpUrl ?? false)) { // если в currentUserAvatarUrl лежит абсолютный http/https URL
      return NetworkImage(currentUserAvatarUrl!); // возвращаем сетевое изображение по этому URL
    }
    if (currentUserAvatarUrl != null && currentUserAvatarUrl!.isNotEmpty) { // если задан относительный путь к аватарке
      return NetworkImage( // загружаем аватар из Supabase Storage по публичной ссылке
        publicUrl( // строим публичный URL
          bucket: avatarsBucketName, // бакет avatars
          objectKey: currentUserAvatarUrl!, // относительный путь к файлу в бакете
        ),
      );
    }
    final login = (currentUserLogin ?? '').trim(); // берём логин пользователя и обрезаем пробелы
    return login.isNotEmpty // если логин не пустой
        ? NetworkImage( // пробуем взять аватарку по имени логина <login>.jpg
      publicUrl( // строим публичный URL на основе логина
        bucket: avatarsBucketName, // бакет avatars
        objectKey: '$login.jpg', // имя файла — логин + .jpg
      ),
    )
        : const AssetImage('assets/profile0.jpg'); // если логина нет — используем локальный дефолтный ассет
  }

  @override
  Widget build(BuildContext context) { // построение шапки
    final avatar = _resolveAvatar(); // заранее вычисляем подходящий ImageProvider для аватарки
    return Padding( // добавляем отступы вокруг шапки
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // симметричные отступы по горизонтали и вертикали
      child: Row( // основной контейнер шапки — горизонтальный ряд
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // элементы распихиваем по краям
        children: [
          Expanded( // слева — текст приветствия, занимает доступное место
            child: Text( // сам текст
              greeting, // строка приветствия
              maxLines: 2, // максимум две строки
              overflow: TextOverflow.ellipsis, // если не влезает — обрезаем с троеточием
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), // крупный жирный шрифт
            ),
          ),
          const SizedBox(width: 8), // небольшой отступ между текстом и иконками справа
          Row( // справа — иконки управления
            children: [
              IconButton( // кнопка переключения темы
                tooltip: 'Тема', // подсказка при долгом тапе/ховере
                onPressed: onToggleTheme, // при нажатии вызываем колбэк переключения темы
                icon: const Icon(Icons.brightness_6), // иконка "солнышко/луна"
              ),
              IconButton( // кнопка выхода
                tooltip: 'Выход', // подсказка
                onPressed: onSignOut, // при нажатии вызываем колбэк выхода
                icon: const Icon(Icons.logout), // иконка выхода
              ),
              PopupMenuButton<_HeaderMenuAction>( // выпадающее меню по клику на аватарку
                tooltip: 'Аккаунт', // подсказка
                onSelected: (action) { // обработчик выбранного пункта меню
                  switch (action) { // смотрим, что выбрали
                    case _HeaderMenuAction.account: // если "Личный кабинет"
                      onOpenAccount(); // открываем "Личный кабинет"
                      break; // выходим из switch
                    case _HeaderMenuAction.profile: // если "Профиль"
                      onOpenProfile(); // открываем "Профиль" (пока заглушка)
                      break; // выходим из switch
                  }
                },
                itemBuilder: (ctx) => const [ // строим список пунктов меню
                  PopupMenuItem( // пункт "Личный кабинет"
                    value: _HeaderMenuAction.account, // значение перечисления
                    child: Text('Личный кабинет'), // текст пункта
                  ),
                  PopupMenuItem( // пункт "Профиль"
                    value: _HeaderMenuAction.profile, // значение перечисления
                    child: Text('Профиль'), // текст пункта
                  ),
                ],
                child: CircleAvatar( // виджет, по которому открывается меню — аватарка
                  radius: 28, // размер аватарки
                  backgroundImage: avatar, // картинка для аватара
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
