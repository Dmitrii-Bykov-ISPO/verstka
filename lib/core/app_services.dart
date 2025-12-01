import 'package:supabase_flutter/supabase_flutter.dart'; // клиент supabase

// supabase базовая конфигурация и клиент
const String supabaseUrl = // константа с URL проекта supabase
    'https://azccbwduobbulgdgucjj.supabase.co'; // const потому что это неизменяемый адрес проекта supabase, он известен на этапе компиляции
const String supabaseAnonKey = // константа с публичным anon key
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF6Y2Nid2R1b2JidWxnZGd1Y2pqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk4MDUyNzgsImV4cCI6MjA3NTM4MTI3OH0.x9jEzJnHg_fiX0dFXpWD70kKH848QZC4uELlMpL1yos'; // const потому что публичный ключ авторизации "anon" тоже фиксирован и не меняется во время работы приложения

const String postBucketName = // имя бакета в storage supabase для фотографий постов
    'post-images'; // строковое имя бакета для картинок постов
const String avatarsBucketName = // имя бакета для аватаров пользователей
    'avatars'; // строковое имя бакета для аватарок
const String eventImagesBucketName = // имя бакета для картинок событий
    'event-images'; // бакет картинок событий

late final SupabaseClient // объявляем тип глобального клиента supabase
supabase; // late final потому что объект клиента создаём один раз после Supabase.initialize и больше не меняем

extension StringX on String { // расширение для String, добавляем утилиты
  bool get isHttpUrl => // геттер, проверяющий, что строка похожа на http/https url
  startsWith('http://') || // проверяем, начинается ли строка с http://
      startsWith(
          'https://'); // геттер проверяет, начинается ли строка с http/https, то есть является ли она url
}

String cleanStoragePath(String s) => // функция нормализует путь для storage
s.replaceAll(RegExp(r'^/+'), ''); // нормализуем путь, чтобы не было ведущих слэшей

// Публичная ссылка на объект (корень бакета)
String publicUrl({required String bucket, required String objectKey}) => // функция собирает публичный url к объекту в storage supabase
// функция собирает публичный url к объекту в storage supabase
Supabase.instance.client.storage.from(bucket).getPublicUrl( // берём storage-клиент и строим ссылку для указанного бакета
  cleanStoragePath(
      objectKey), // предварительно чистим путь, чтобы избежать двойных слэшей
);

extension LetX<T> on T { // обобщённое расширение, доступно на любом типе T
  R let<R>(R Function(T it) f) => // метод принимает функцию и возвращает её результат
  f(this); // вызывает переданную функцию с текущим значением и возвращает её результат
}
