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

### Коли запускається

| Подія | Перевірка Jira (`jira-gate`) | Регресія (`newman`) |
|---|---|---|
| Щопонеділка о 07:00 UTC (`schedule`) | так | лише якщо знайдено тікети |
| Вручну з прапорцем `jira_gate` | так | лише якщо знайдено тікети |
| Вручну без прапорця | ні | завжди |
| push у `main` (змінилися `collections/**` або workflow) | ні | завжди |

Ручний запуск: **Actions → API regression (Newman) → Run workflow** (прапорець *jira_gate* за бажанням) або:

```bash
gh workflow run newman.yml --ref main
gh workflow run newman.yml --ref main -f jira_gate=true
```

### Jobs

1. **`jira-gate`** ([`scripts/jira-gate.sh`](scripts/jira-gate.sh)):
   - спершу перевіряє вхід через `GET /rest/api/3/myself`. Jira відповідає на пошук і анонімно
     (HTTP 200 і 0 тікетів), тому без цієї перевірки неправильний токен виглядав би як «тікетів немає»;
   - потім шукає тікети через `POST /rest/api/3/search/jql` з JQL
     `labels = "api-testing" AND status = "Ready for QA" ORDER BY key`;
   - пише знайдені тікети з посиланнями в summary запуску;
   - **падає з явною помилкою**, якщо немає секретів чи змінної, вхід не справжній або пошук не вдався.
     Мовчки не пропускає.
2. **`newman`** (Node 20, `newman@6`, `newman-reporter-htmlextra`) проганяє колекцію з репортерами
   `cli`, `json` і `htmlextra`. Якщо хоч одна перевірка впала, job завершується з помилкою.
   Звіти вивантажуються як артефакти (зберігаються 14 днів) навіть тоді, коли тести впали:
   - `newman-report` — JSON-звіт;
   - `newman-html-report` — HTML-звіт.
3. **`publish-report`** — тільки на `main` і тільки якщо `newman` справді відпрацював і створив звіт:
   публікує HTML-звіт на GitHub Pages через `actions/deploy-pages`, навіть коли перевірки впали.

**Останній звіт:** https://julykotsur-alt.github.io/draft-api/

### Налаштування

| Назва | Тип | Значення |
|---|---|---|
| `JIRA_BASE_URL` | variable | адреса Jira, наприклад `https://your-site.atlassian.net` |
| `JIRA_EMAIL` | secret | email Atlassian-акаунта, якому належить токен |
| `JIRA_API_TOKEN` | secret | API-токен з https://id.atlassian.com/manage-profile/security/api-tokens |
| `JIRA_JQL` | variable, необов'язкова | інший JQL замість стандартного |

```bash
gh variable set JIRA_BASE_URL --repo julykotsur-alt/draft-api --body "https://your-site.atlassian.net"
gh secret set JIRA_EMAIL --repo julykotsur-alt/draft-api
gh secret set JIRA_API_TOKEN --repo julykotsur-alt/draft-api
```

`gh secret set` без `--body` попросить вставити значення, і воно не потрапить в історію терміналу.

GitHub Pages має бути увімкнено з джерелом **GitHub Actions**
(Settings → Pages → Build and deployment → Source).

> Репозиторій публічний: логи й summary запусків, зокрема ключі та назви тікетів Jira, бачать усі.
> GitHub вимикає `schedule` у публічних репозиторіях, якщо 60 днів не було активності.

## Структура

```
.github/       GitHub Actions workflow
collections/   Postman-колекції
scripts/       допоміжні скрипти CI (Jira gate)
results/       машиночитні результати запусків (JUnit, JSON), не комітяться
reports/       HTML-звіти, не комітяться
```

## Примітки

- Petstore — спільний публічний демо-сервер: його дані можуть змінювати інші користувачі,
  а сам він часом відповідає повільно або з помилками 5xx.
- `DELETE /pet/{petId}` відповідає текстом `Pet deleted`, хоча в заголовку `Content-Type: application/json`,
  тому в тестах ця відповідь перевіряється як текст.
