= Выбор и обоснование сервисов
+ Microsoft Azure PlayFab:
  - Бизнес-смысл: Обеспечить стабильную и масштабируемую отправку
    push-уведомлений игрокам об их ходе (как того требует ТЗ), а
    также для будущего управления таблицами лидеров и аналитикой.
  - Почему он: PlayFab — это специализированный бэкенд для игр, который
    избавляет от необходимости писать сложную систему пушей с нуля и
    поддерживать её под iOS (APNS) и Android (FCM).

+ Google Gemini API:
  - Бизнес-смысл: Реализовать уникальную функцию ИИ-тренера, который дает не
    просто оптимальный ход, а понятные, «человечные» подсказки, помогая
    новичкам обучаться и не бросать игру.
  - Почему он: В отличие от простых алгоритмических советчиков, Gemini может
    генерировать объяснения на естественном языке, что напрямую соответствует
    требованию.

= Изучение документации сервисов
== PlayFab API (Push-уведомления)
- Тип API: REST.
- Необходимые методы:
  - POST /Server/SendPushNotification (PlayFab Server API).
    - Назначение: Команда вашему бэкенду отправить push-уведомление
      конкретному игроку.
    - Входные параметры: Recipient (PlayFab ID игрока), Message (текст
      уведомления), Subject (заголовок).
- Возможные ошибки:
  - AccountBanned (1002), AccountDeleted (1322): Аккаунт игрока заблокирован.
    Уведомления не отправлять.
  - NotAuthorized (1089): Неверный секретный ключ X-SecretKey. Требует
    проверки настроек.
  - APIClientRequestRateLimitExceeded (1199), ServiceUnavailable (1123):
    Превышение лимита запросов или временная проблема на стороне PlayFab.
    Нужно повторить запрос позже (Retry).
- Сертификаты и ключи:
  - X-SecretKey: Главный ключ для аутентификации серверных запросов к
    PlayFab. Выдается в консоли PlayFab Game Manager. Хранить на сервере!
  - APNS Key (.p8): Для отправки пушей на iOS.
  - FCM Server Key: Для отправки пушей на Android.

== Gemini API (ИИ-тренер)
- Тип API: REST (c поддержкой Server-Sent Events для потоковой передачи).
- Необходимые методы:
  - POST
    https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent
    - Назначение: Запрос совета от ИИ на основе текущего состояния игры.
    - Входные параметры: contents (промпт с историей ходов и рукой игрока).
- Возможные ошибки:
  - 400 INVALID_ARGUMENT: Неверный промпт или JSON.
  - 403 PERMISSION_DENIED: Неверный или истекший API Key.
  - 429 RESOURCE_EXHAUSTED: Превышены лимиты запросов (RPM/TPM). Нужно
    использовать fallback-эвристику.
  - 500 INTERNAL, 503 UNAVAILABLE: Временная ошибка на стороне Google. Нужно
    повторить запрос (Retry).
- Сертификаты и ключи:
  - API Key: Самый простой способ. Генерируется в Google AI Studio.
    Передается в заголовке x-goog-api-key.
  - OAuth 2.0: Более безопасный способ с использованием Service Account для
    production-среды.

= Подготовка сервиса к интеграции
== Новые API методы

Необходимо добавить следующие эндпоинты:
#table(
  columns: 3,
  table.header([*Метод*], [*Endpoint*], [*Назначение*]),
  [POST],
  [/users/me/push-token],
  [Сохранить push-токен устройства игрока.],
  [PATCH],
  [/users/me/push-settings],
  [Включить/выключить уведомления],
  [POST],
  [/games/{game_id}/ai-advice],
  [Запросить совет у ИИ-тренера. Возвращает advice_id, suggested_action и
    explanation.],
)

== Дополнения к базе данных (атрибуты таблиц)
Необходимо добавить:

В уже существующую таблицу users:
- playfab_id --- поле для реализации через playfab
- push_token_ios --- поле для сохранения push token-а ios устройства
- push_token_android --- поле для сохранения push token-а Android устройства
- push_enabled --- поле для включения/выключения уведомления

```sql
-- PlayFab
ALTER TABLE users ADD COLUMN playfab_id VARCHAR(255) UNIQUE;
ALTER TABLE users ADD COLUMN push_token_ios VARCHAR(255);
ALTER TABLE users ADD COLUMN push_token_android VARCHAR(255);
ALTER TABLE users ADD COLUMN push_enabled BOOLEAN DEFAULT true;

-- Gemini
ALTER TABLE users ADD COLUMN ai_coach_enabled BOOLEAN DEFAULT true;
ALTER TABLE users ADD COLUMN ai_coach_aggressiveness INTEGER DEFAULT 50;
```

Новая таблица ai_coach_logs:

```sql
CREATE TABLE ai_coach_logs (
    log_id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(user_id),
    game_id UUID REFERENCES games(game_id),
    hand_state JSONB NOT NULL,
    suggested_action JSONB,
    user_followed BOOLEAN,
    created_at TIMESTAMP DEFAULT NOW()
);
```

== Дополнения к UI
#table(
  columns: 2,
  [*Компонент*],
  [*Изменение*],
  [Экран "Найстройки"],
  [Добавить переключатель "Push-уведомления", "Стиль советов ИИ" и "Агрессивность советов".],
  [Экран "Игра"],
  [В блоке "AI-тренер" добавить индикатор "Загрузка совета..." и отображать текст explanation от Gemini.],
  [Экран "Профиль"],
  [Добавить блок "Статистика ИИ-тренера" (процент принятых советов, влияние на винрейт).],
  [Панель модератора],
  [Добавить вкладку "AI Metrics" для просмотра статистики запросов к Gemini, ошибок и стоимости.],
)

= Диаграмма
Суть диаграммы:
- Регистрация: Приложение сохраняет push-токен устройства на бэкенде (в БД).
- Игровой процесс (Push): После хода игрока бэкенд определяет следующего игрока
  и через PlayFab отправляет ему push-уведомление.
- Игровой процесс (AI): Игрок запрашивает совет. Бэкенд отправляет промпт в
  Gemini. При успехе — возвращает совет и сохраняет его в лог. При ошибке 429 —
  использует простую эвристику (fallback).
- Обратная связь: Когда игрок следует совету, бэкенд обновляет user_followed в
  логах для последующего анализа качества ИИ.
#image("Sequence Diagram Light.drawio.svg")
