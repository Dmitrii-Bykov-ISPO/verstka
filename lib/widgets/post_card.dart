import 'package:flutter/material.dart'; // базовые виджеты Flutter
import 'package:ui_example/core/app_services.dart'; // расширение StringX (isHttpUrl) и другие сервисы
import 'package:ui_example/features/common/photo_view_screen.dart'; // экран просмотра фото на весь экран

class PostCard extends StatelessWidget { // карточка отдельного поста
  final String profileAsset; // URL или локальный asset — аватар автора поста
  final String name; // ФИО автора
  final String time; // строка "сколько времени назад"
  final String caption; // текст поста
  final List<String> photos; // список путей/URL картинок поста

  const PostCard({ // конструктор карточки поста
    super.key, // ключ виджета
    required this.profileAsset, // обязательный аватар автора
    required this.name, // обязательное имя автора
    required this.time, // обязательная строка времени
    required this.caption, // обязательный текст поста
    required this.photos, // обязательный список картинок (может быть пустым)
  });

  static Widget buildFromData({ // фабричный метод, чтобы собирать PostCard из конкретных данных
    required BuildContext context, // контекст, чтобы совпадала сигнатура с прежним кодом
    required String profileAsset, // аватар автора
    required String name, // имя автора
    required String time, // строка "сколько назад"
    required String caption, // текст поста
    required List<String> photos, // список картинок
  }) => // возвращаем готовый виджет PostCard
  PostCard( // создаём экземпляр PostCard
    profileAsset: profileAsset, // передаём аватар
    name: name, // передаём имя
    time: time, // передаём строку времени
    caption: caption, // передаём текст поста
    photos: photos, // передаём список картинок
  );

  bool _isUrl(String p) => p.isHttpUrl; // проверка, является ли строка http/https URL (через расширение StringX)

  void _openPhoto(BuildContext context, String p) => // открыть фото на новом экране
  Navigator.of(context).push( // навигация на новый экран
    MaterialPageRoute( // материал-маршрут
      builder: (_) => PhotoViewScreen(imageAsset: p), // экран просмотра фото с переданным путём/URL
    ),
  );

  Widget _img(BuildContext context, String p, {BorderRadius? r}) { // вспомогательный виджет одной картинки
    final w = _isUrl(p) // смотрим, URL это или локальный asset
        ? Image.network(p, fit: BoxFit.cover) // если URL — грузим из сети
        : Image.asset(p, fit: BoxFit.cover); // иначе берём локальный asset
    return GestureDetector( // оборачиваем картинку в GestureDetector для обработки тапов
      onTap: () => _openPhoto(context, p), // при нажатии открываем fullscreen просмотр
      child: ClipRRect( // скругляем углы картинки
        borderRadius: r ?? BorderRadius.circular(16), // либо переданный радиус, либо дефолтный 16
        child: w, // сама картинка
      ),
    );
  }

  Widget _photos(BuildContext context) { // раскладка фото внутри карточки
    const double gap = 8.0; // расстояние между картинками
    if (photos.isEmpty) return const SizedBox.shrink(); // если фото нет — возвращаем пустой виджет
    if (photos.length == 1) { // если только одна картинка
      return SizedBox( // обёртка с фиксированной высотой
        height: 500, // фиксированная высота, как в исходном коде
        width: double.infinity, // по ширине занимает всё доступное
        child: _img(context, photos[0]), // показываем одну картинку
      );
    }
    if (photos.length == 2) { // если две картинки
      return SizedBox( // обёртка с фиксированной высотой
        height: 500, // общая высота блока
        child: Row( // размещаем две картинки в ряд
          children: [
            Expanded(child: _img(context, photos[0])), // первая картинка слева
            const SizedBox(width: gap), // промежуток между ними
            Expanded(child: _img(context, photos[1])), // вторая картинка справа
          ],
        ),
      );
    }
    if (photos.length == 3) { // если три картинки
      return SizedBox( // обёртка с фиксированной высотой
        height: 500, // высота блока
        child: Row( // основная раскладка — две колонки
          children: [
            Expanded(child: _img(context, photos[0])), // слева одна большая картинка
            const SizedBox(width: gap), // отступ между колонками
            Expanded( // справа две картинки друг над другом
              child: Column( // вертикальная колонка
                children: [
                  Expanded(child: _img(context, photos[1])), // верхняя картинка
                  const SizedBox(height: gap), // отступ между картинками
                  Expanded(child: _img(context, photos[2])), // нижняя картинка
                ],
              ),
            ),
          ],
        ),
      );
    }
    return GridView.builder( // для 4 и более картинок используем GridView
      physics: const NeverScrollableScrollPhysics(), // отключаем прокрутку у грида (прокручивается весь список постов)
      shrinkWrap: true, // разрешаем гриду занимать только нужную высоту
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount( // параметры сетки
        crossAxisCount: 4, // 4 колонки
        crossAxisSpacing: gap, // горизонтальные отступы между ячейками
        mainAxisSpacing: gap, // вертикальные отступы между ячейками
        childAspectRatio: 1, // квадратные ячейки (ширина = высота)
      ),
      itemCount: photos.length, // количество элементов = количество картинок
      itemBuilder: (context, i) => // билдер для каждой ячейки
      _img(context, photos[i], r: BorderRadius.circular(10)), // картинка с чуть меньшим скруглением
    );
  }

  @override
  Widget build(BuildContext context) { // построение карточки поста
    final ImageProvider avatar = _isUrl(profileAsset) // определяем источник аватарки
        ? NetworkImage(profileAsset) // если profileAsset — URL, берём сетевое изображение
        : AssetImage(profileAsset) as ImageProvider; // иначе считаем, что это локальный asset
    return Container( // корневой контейнер карточки поста
      padding: const EdgeInsets.all(16), // внутренние отступы
      decoration: BoxDecoration( // оформление карточки
        color: Theme.of(context).cardColor, // фон берём из темы (цвет карточки)
        borderRadius: BorderRadius.circular(16), // скруглённые углы
      ),
      child: Column( // раскладываем содержимое вертикально
        crossAxisAlignment: CrossAxisAlignment.start, // выравнивание по левому краю
        children: [
          Row( // верхняя часть карточки: аватар, имя, время, меню
            children: [
              CircleAvatar(radius: 24, backgroundImage: avatar), // аватар автора поста
              const SizedBox(width: 10), // отступ между аватаром и текстом
              Column( // колонка с именем и временем
                crossAxisAlignment: CrossAxisAlignment.start, // выравнивание текста по левому краю
                children: [
                  Text( // имя автора
                    name, // строка с именем
                    style: const TextStyle(fontWeight: FontWeight.bold), // делаем имя жирным
                  ),
                  Text( // строка с временем
                    time, // текст "сколько назад"
                    style: TextStyle( // стиль текста
                      color: Theme.of(context) // берём цвет текста из темы
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withOpacity(0.6), // делаем его чуть прозрачнее
                    ),
                  ),
                ],
              ),
              const Spacer(), // заполнитель, чтобы иконка меню уехала вправо
              const Icon(Icons.more_vert), // иконка "ещё" (меню, пока без обработчика)
            ],
          ),
          const SizedBox(height: 12), // вертикальный отступ между шапкой и текстом поста
          Text( // сам текст поста
            caption, // содержимое поста
            style: const TextStyle(fontSize: 16), // обычный читаемый размер шрифта
          ),
          const SizedBox(height: 12), // отступ перед блоком картинок
          _photos(context), // блок с картинками (в зависимости от количества)
          const SizedBox(height: 12), // отступ перед иконками действий
          Row( // ряд с иконками действий
            mainAxisAlignment: MainAxisAlignment.spaceAround, // равномерно распределяем по ширине
            children: const [
              Icon(Icons.favorite_border), // иконка "лайк" (пока без логики)
              Icon(Icons.chat_bubble_outline), // иконка "комментарий" (пока заглушка)
              Icon(Icons.share), // иконка "поделиться" (пока заглушка)
            ],
          ),
        ],
      ),
    );
  }
}
