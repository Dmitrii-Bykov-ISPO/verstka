import 'package:flutter/material.dart'; // базовые виджеты Flutter

class InfoCard extends StatelessWidget { // простая карточка с иконкой и заголовком
  final IconData icon; // иконка, которая будет отображаться сверху
  final Color iconColor; // цвет иконки
  final String title; // заголовок карточки

  const InfoCard({ // конструктор карточки
    super.key, // ключ виджета
    required this.icon, // обязательная иконка
    required this.iconColor, // обязательный цвет иконки
    required this.title, // обязательный текст заголовка
  });

  @override
  Widget build(BuildContext context) => Container( // основная обёртка карточки
    padding: const EdgeInsets.all(16), // внутренние отступы со всех сторон
    margin: const EdgeInsets.symmetric(horizontal: 8), // внешние отступы по горизонтали
    decoration: BoxDecoration( // оформление контейнера
      color: Theme.of(context).cardColor, // цвет фона берём из текущей темы (цвет карточки)
      borderRadius: BorderRadius.circular(16), // скруглённые углы карточки
    ),
    child: Column( // содержимое карточки вертикально
      crossAxisAlignment: CrossAxisAlignment.start, // прижимаем содержимое к левому краю
      children: [
        Icon(icon, color: iconColor), // рисуем иконку с заданным цветом
        const SizedBox(height: 8), // небольшой вертикальный отступ
        Text( // текст заголовка
          title, // текст берём из поля title
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), // делаем заголовок крупным и жирным
        ),
      ],
    ),
  );
}
