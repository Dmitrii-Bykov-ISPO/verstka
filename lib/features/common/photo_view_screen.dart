import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart'; // UI
import 'dart:typed_data'; // Uint8List
import '../../core/app_services.dart'; // StringX (isHttpUrl)

class PhotoViewScreen extends StatelessWidget { // экран просмотра изображения
  final String? imageAsset; // путь/ссылка
  final Uint8List? imageBytes; // bytes для предпросмотра

  const PhotoViewScreen({ // конструктор экрана просмотра
    super.key, // пробрасываем key
    this.imageAsset, // опциональный путь/ссылка на картинку
    this.imageBytes, // опциональные байты картинки
  });

  bool get _hasUrl => // геттер, есть ли вообще что показывать
  (imageAsset ?? '').isHttpUrl || // если это http/https ссылка
      (imageAsset != null &&
          imageAsset!
              .isNotEmpty); // есть ли что показывать (URL или локальный asset)

  @override
  Widget build(BuildContext context) { // сборка UI экрана просмотра
    final child = Builder(builder: (_) { // используем Builder, чтобы удобно выбирать контент
      if (imageBytes != null) { // если переданы байты изображения
        return Center( // центрируем
          child: InteractiveViewer( // даём возможность зумить и двигать
            child: Image.memory(
              imageBytes!, // отображаем картинку из памяти
              fit: BoxFit.contain, // вписываем по большей стороне
            ),
          ),
        );
      }
      if (!_hasUrl) { // если ни url, ни asset нет
        return const Center(
          child: Text(
            'Нет изображения', // текст, если ничего не передано
            style: TextStyle(color: Colors.white), // белый текст
          ),
        );
      }
      final isUrl = (imageAsset ?? '').isHttpUrl; // проверяем, это http/https или локальный asset
      return Center( // центрируем
        child: InteractiveViewer( // снова зум/перемещение
          child: isUrl
              ? CachedNetworkImage( // если это инет ссылка - кешированной сетевое изображение
            imageUrl: imageAsset!, //ссылка на картинка
            imageBuilder: (context, imageProvider) => Container( //контейнер с картинкой
              decoration: BoxDecoration(
                image: DecorationImage(
                    image: imageProvider,
                    fit: BoxFit.cover/*,
                  colorFilter:
                  ColorFilter.mode(Colors.red, BlendMode.colorBurn)),*/ //Если хочеца красного
            ),
            ),
            ),
            //placeholder: (context, url) => CircularProgressIndicator(),
            progressIndicatorBuilder: (context, url, downloadProgress) => //для отображения прогресса загрузки
                CircularProgressIndicator(value: downloadProgress.progress),
            errorWidget: (context, url, error) => Icon(Icons.error),
          )
              : Image.asset( // иначе подразумеваем, что это asset
            imageAsset!, // путь к asset
            fit: BoxFit.contain, // вписываем
          ),
        ),
      );
    });

    return Scaffold( // каркас экрана
      backgroundColor: Colors.black, // фон чёрный, как в просмотрщиках
      appBar: AppBar(
        backgroundColor: Colors.black, // чёрная шапка
        elevation: 0, // убираем тень
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white), // кнопка "назад" белая
          onPressed: () => Navigator.of(context).maybePop(), // возвращаемся назад, если можно
          tooltip: 'Назад', // подсказка
        ),
      ),
      body: SafeArea(child: child), // в теле рендерим выбранный контент
    );
  }
}
