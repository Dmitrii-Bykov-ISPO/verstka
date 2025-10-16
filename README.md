# Flutter + Supabase: учебное мини‑приложение ленты

> **Язык проекта:** Dart/Flutter · **Цель:** образовательный пример «ленты постов» с простейшей авторизацией, темизацией и загрузкой данных из Supabase.

---

## ✨ Возможности
- Вход по паре `login/password` через таблицу `users` (**демо‑уровень**, без безопасных токенов)
- Смена темы (Light/Dark) с сохранением в `SharedPreferences`
- Главный экран с приветствием, карточками постов и просмотром фото
- Интеграция со **Supabase**: таблицы `users`, `posts`, `post_images`, `notifications`, `device_tokens` и публичные бакеты `post-images`, `avatars`

> **Важно:** это учебный код. Пароли хранятся в базе **в открытом виде**, а авторизация реализована простейшей проверкой. В production используйте Supabase Auth и храните хэши паролей.

---

## 🧱 Архитектура и ключевые компоненты
- **`ThemeController`** — управление темой, хранение режима в `SharedPreferences`
- **`SimpleAuth`** — *демо‑аутентификация*: хранит текущий `user_id` локально; вход по таблице `users`
- **`PostsRepository`** — пакетные запросы в Supabase: `posts` → `users` → `post_images`; склейка в `PostModel`
- **`publicUrl(...)`** — получение публичных URL из Supabase Storage для бакетов `post-images` и `avatars`
- **UI**: `LoginScreen`, `HomeScreen`, `PostCard`, `AppHeader`, `PhotoViewScreen`

Стартовая точка: `main()` → инициализация Supabase → `runApp(MyApp)`.

---

## 📦 Зависимости
В `pubspec.yaml` должны быть:

```yaml
dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.2.0
  supabase_flutter: ^2.5.0
```

> Версии можно обновить до актуальных. Flutter — любой стабильный канал (3.x+).

---

## 🛠️ Подготовка Supabase
1. Создайте проект на [app.supabase.com](https://app.supabase.com)  
2. В **Project Settings → API** возьмите `Project URL` и `anon public key`  
3. Создайте таблицы (SQL ниже) и наполните демо‑данными  
4. В **Storage** создайте публичные бакеты:
   - `post-images`
   - `avatars`
5. Загрузите туда изображения (например: `photo1.jpg`, `photo2.jpg`, ... и аватары `<login>.jpg`).

### Рекомендованные SQL‑миграции
> Выполните в **SQL Editor**.

```sql
-- =====================================
--   СОЗДАНИЕ БАЗЫ ДАННЫХ ПРОЕКТА
--   (полностью рабочий тестовый скрипт)
-- =====================================

-- =====================================
-- ТАБЛИЦА users
-- =====================================
create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  login text unique not null,        -- фамилия+инициалы (латиница)
  password text not null,            -- для теста, в проде хеш
  full_name text not null,
  avatar_url text                    -- ссылка на фото (Supabase Storage)
);

create index if not exists idx_users_login on public.users(login);

-- =====================================
-- ТАБЛИЦА posts
-- =====================================
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  text text not null
);

create index if not exists idx_posts_user_id on public.posts(user_id);
create index if not exists idx_posts_created_at on public.posts(created_at desc);

-- =====================================
-- ТАБЛИЦА post_images (фотографии постов)
-- =====================================
create table if not exists public.post_images (
  id bigserial primary key,
  post_id uuid not null references public.posts(id) on delete cascade,
  storage_path text not null,  -- путь в бакете post-images/<user_id>/<post_id>/<file>.jpg
  sort_order int not null default 0
);

create index if not exists idx_post_images_post_id on public.post_images(post_id);
create index if not exists idx_post_images_sort on public.post_images(post_id, sort_order);


-- =====================================
-- ТЕСТОВЫЕ ДАННЫЕ (логин/пароль = фамилия+инициалы)
-- =====================================
insert into public.users (login, password, full_name, avatar_url) values
('abakumovaea','abakumovaea','Абакумова Евгения Александровна', null),
('bikinakv','bikinakv','Бикина Кира Владимировна', null),
('bykovda','bykovda','Быков Дмитрий Альбертович', null),
('veshikovaaa','veshikovaaa','Вешикова Анастасия Алексеевна', null),
('glushkovadn','glushковадн','Глушкова Дарья Николаевна', null),
('grekovaai','grekovaai','Грекова Ангелина Игоревна', null),
('ishbulatovrr','ishbulatovrr','Ишбулатов Реналь Русланович', null),
('kazenoved','kazenoved','Казенов Эдуард Дмитриевич', null),
('melniksr','melniksr','Мельник Сергий Романович', null)
on conflict do nothing;

insert into public.posts (user_id, text, created_at)
select id, 'Красота то какая! Ляпота!🌅 - © Казенов Эдуард', now() - interval '2 hour'
from public.users where full_name = 'Казенов Эдуард Дмитриевич';

insert into public.posts (user_id, text, created_at)
select id, 'Поход в лес! 🌳🏔️🌲', now()
from public.users where full_name = 'Мельник Сергий Романович';

-- и т.д. по аналогии
```

### Storage: политики
Для бакетов `post-images` и `avatars` включите **Public** или создайте правило чтения для `anon`. Приложение использует публичные ссылки `getPublicUrl`.

> **Путь `storage_path`:** в вашей схеме допустимы как полные пути `post-images/<user>/<post>/<file>.jpg`, так и просто имена файлов `photo1.jpg`. Репозиторий обрабатывает оба варианта.

---

## 🔑 Конфигурация ключей
В коде используются константы:
```dart
const String supabaseUrl = 'https://...supabase.co';
const String supabaseAnonKey = 'eyJ...';
```

> `anon key` — публичный ключ для клиентских приложений, его можно коммитить. Секретные ключи (service_role) **никогда** не встраивайте в клиент.

---

## 🚀 Локальный запуск
```bash
flutter pub get
flutter run
```

---

## 🧪 Демо‑данные
Заполните `users` и `posts` вручную или SQL‑вставками. Пример:

```sql
insert into public.users (login, password, full_name, avatar_url)
values
  ('ivanovaa', '1234', 'Иванова А.А.', null),
  ('petroviv', '1234', 'Петров И.В.', 'petroviv.jpg');

insert into public.posts (user_id, text)
select id, 'Мой отдых 🌊🌊🌊' from public.users where login='ivanovaa';
```
---

## 🧭 Навигация по коду (основные сущности)
- `main()` — инициализация Supabase и запуск приложения
- `ThemeController` — загрузка/сохранение режима темы
- `SimpleAuth` — хранение текущего `user_id` в `SharedPreferences`; вход по таблице `users`
- `PostsRepository.loadPosts()` — выборки `posts`/`users`/`post_images` и сборка `PostModel`
- `publicUrl(...)` / `isHttpUrl` — утилиты для генерации ссылок
- UI‑виджеты: `LoginScreen`, `HomeScreen`, `AppHeader`, `InfoCard`, `PostCard`, `PhotoViewScreen`

---

## ⚠️ Безопасность и оговорки
- Пароли в таблице `users` **в открытом виде** — только для демонстрации. В продакшене:
  - храните **хэши** (bcrypt/argon2)
  - используйте **Supabase Auth** (email/password, OAuth)
  - включайте строгие RLS‑политики (разграничение доступа по пользователю)
- Публичные бакеты удобны для учебных целей, но проверяйте риски утечки данных.

---

## 🔮 Дорожная карта (идеи улучшений)
- Уведомления через FireBase
- Перейти на **Supabase Auth** + защищённые сессии
- Хранить пароли как хэши; добавить регистрацию/сброс
- Кэширование/пагинация постов; лайки/комментарии
- Загрузка изображений из приложения в Storage

---

## 📝 Лицензия
Добавить при необходимости (НЕ ЗНАЮ КАКАЯ НАДО)

---

## 🐞 Траблшутинг
- **Пустой экран на старте**: дождитесь загрузки темы (`_themeReady`), проверьте `supabaseUrl/anonKey`
- **Нет постов/фото**: проверьте данные таблиц и публичность бакетов; заполните демо‑данные
- **Аватар не отображается**: если в `avatar_url` абсолютная ссылка — она используется как есть; иначе ищется в бакете `avatars` файл `<login>.jpg`

---

## 📷 Скриншоты (Добавлю потом)

