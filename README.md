# API-регресія Swagger Petstore

Автоматична регресійна перевірка публічного API [Swagger Petstore v3](https://petstore3.swagger.io/)
(`https://petstore3.swagger.io/api/v3`, [OpenAPI](https://petstore3.swagger.io/api/v3/openapi.json)).

## Що перевіряється

Колекція [`collections/petstore-collection.json`](collections/petstore-collection.json) (Postman Collection v2.1)
проходить повний життєвий цикл тварини (`Pet`):

| # | Запит | Ендпоінт | Очікуваний статус |
|---|-------|----------|-------------------|
| 1 | Create pet | `POST /pet` | 200 |
| 2 | Get created pet | `GET /pet/{petId}` | 200 |
| 3 | Update pet | `PUT /pet` | 200 |
| 4 | Get updated pet | `GET /pet/{petId}` | 200 |
| 5 | Delete pet | `DELETE /pet/{petId}` | 200 |
| 6 | Verify deletion | `GET /pet/{petId}` | 404 |

Кожен запит перевіряє:

- **статус** — код відповіді з OpenAPI-документації;
- **схему** — відповідь відповідає `components.schemas.Pet` (JSON Schema у змінній колекції `petSchema`);
- **узгодженість даних** — те, що повернув API, збігається з тим, що було надіслано або збережено на попередньому кроці;
- **час відповіді** — менше 5 секунд.

### Тестові дані

- Фіксованих даних немає: pre-request скрипт кроку 1 генерує унікальний `petId`
  (`Date.now() * 1000 + випадкове 0–999`) і випадкові ім'я, категорію, теги та статус.
- Крок 3 змінює всі поля, крім `id`, щоб оновлення було видно.
- Колекція прибирає за собою: крок 5 видаляє тварину, а крок 6, якщо вона все ще існує,
  видаляє її повторно й очищає службові змінні колекції.

### Змінні колекції

| Змінна | Призначення |
|--------|-------------|
| `baseUrl` | Базова адреса API, за замовчуванням `https://petstore3.swagger.io/api/v3` |
| `petSchema` | JSON Schema відповіді `Pet` |
| `petId`, `createdPet`, `updatedPet`, `petDeleted` | Створюються під час запуску й очищаються в кінці |

## Як запустити

### Postman (графічний інтерфейс)

1. **Import** → виберіть `collections/petstore-collection.json`.
2. Відкрийте колекцію → **Run** → **Run Petstore API regression**.

### Newman (командний рядок)

Потрібен [Node.js](https://nodejs.org/) 18 або новіший (на macOS: `brew install node`).

```bash
npm install -g newman newman-reporter-htmlextra
```

Звичайний запуск:

```bash
newman run collections/petstore-collection.json
```

Запуск зі звітами (JUnit XML — у `results/`, HTML — у `reports/`):

```bash
newman run collections/petstore-collection.json \
  --reporters cli,junit,htmlextra \
  --reporter-junit-export results/junit.xml \
  --reporter-htmlextra-export reports/report.html
```

Інший стенд (наприклад, локальний Petstore):

```bash
newman run collections/petstore-collection.json --env-var "baseUrl=http://localhost:8080/api/v3"
```

> Не запускайте з `--bail`: тоді після першої невдалої перевірки newman зупиниться
> і не дійде до кроків видалення.

## CI (GitHub Actions)

Workflow [`.github/workflows/newman.yml`](.github/workflows/newman.yml) — **API regression (Newman)**.

**Коли запускається:**
- push у `main`, якщо змінилися `collections/**` або сам workflow;
- вручну: **Actions → API regression (Newman) → Run workflow**
  або `gh workflow run newman.yml --ref main`.

**Що робить:**
1. Job `newman` (Node 20, `newman@6`, `newman-reporter-htmlextra`) проганяє колекцію
   з репортерами `cli`, `json` і `htmlextra`. Якщо хоч одна перевірка впала, job завершується з помилкою.
2. Звіти вивантажуються як артефакти запуску (зберігаються 14 днів), навіть коли тести впали:
   - `newman-report` — JSON-звіт;
   - `newman-html-report` — HTML-звіт.
3. Тільки на `main`: job `deploy-report` публікує HTML-звіт на GitHub Pages
   через `actions/deploy-pages` — теж навіть тоді, коли перевірки впали.

**Останній звіт:** https://julykotsur-alt.github.io/draft-api/

GitHub Pages у налаштуваннях репозиторію має бути увімкнено з джерелом **GitHub Actions**
(Settings → Pages → Build and deployment → Source).

## Структура

```
.github/       GitHub Actions workflow
collections/   Postman-колекції
results/       машиночитні результати запусків (JUnit, JSON), не комітяться
reports/       HTML-звіти, не комітяться
```

## Примітки

- Petstore — спільний публічний демо-сервер: його дані можуть змінювати інші користувачі,
  а сам він часом відповідає повільно або з помилками 5xx.
- `DELETE /pet/{petId}` відповідає текстом `Pet deleted`, хоча в заголовку `Content-Type: application/json`,
  тому в тестах ця відповідь перевіряється як текст.
