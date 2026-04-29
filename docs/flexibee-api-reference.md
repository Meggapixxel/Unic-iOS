# FlexiBee REST API — Довідник

## Підключення

```
Base URL:  https://chariot-studio.flexibee.eu/c/chariot_studio_s_r_o_
Auth:      Basic api:<password>
Accept:    application/json
```

Credentials зберігаються у `FlexiBeeService.swift` — НЕ комітити в публічний репозиторій.

## Формат відповіді

Всі відповіді обгорнуті в `winstrom`:

```json
{
  "winstrom": {
    "@version": "1.0",
    "<entity>": [ ... ]
  }
}
```

При помилці:
```json
{
  "winstrom": {
    "success": "false",
    "message": "Опис помилки"
  }
}
```

## Реалізовані ендпоінти

### Склад (`/skladova-karta.json`)

```
GET /skladova-karta.json?fields=cenik,stavMjSPozadavky&limit=300
```

| Поле | Тип | Опис |
|------|-----|------|
| `cenik` | string ref | `code:KOD` — код товару |
| `cenik@showAs` | string | `KOD: Назва товару` — автоматично з reference |
| `stavMjSPozadavky` | string (число) | Кількість на складі (враховуючи резерви) |

> `stavMJ` — тільки в детальному запиті одного запису. У списку завжди `stavMjSPozadavky`.

### Прайс-лист (`/cenik.json`)

```
GET /cenik.json?fields=id,kod,nazev,cenaZaklVcDph,nakupCena&limit=300
```

| Поле | Тип | Опис |
|------|-----|------|
| `id` | string | Внутрішній ID |
| `kod` | string | Унікальний код товару |
| `nazev` | string | Назва |
| `cenaZaklVcDph` | string (число) | Продажна ціна з ПДВ (CZK) |
| `nakupCena` | string (число) | Закупівельна ціна без ПДВ (CZK) |

> Маржа = `(cenaZaklVcDph / 1.21 - nakupCena) / (cenaZaklVcDph / 1.21) * 100`

## Нереалізовані ендпоінти

Документацію по фактурах — див. `flexibee-invoices-integration.md`.

### Видані фактури (`/faktura-vydana.json`)
### Прийняті фактури (`/faktura-prijata.json`)
### Банківські виписки (`/banka.json`)
### Адресар / Компанії (`/adresar.json`)

## Параметри запиту

| Параметр | Приклад | Опис |
|----------|---------|------|
| `fields` | `id,kod,nazev` | Які поля повернути |
| `limit` | `300` | Максимум записів |
| `conditions` | `lastUpdate gt '2026-04-01'` | Фільтр (працює нестабільно в list-mode) |
| `order` | `nazev@A` | Сортування (A = asc, D = desc) |

> Reference-поля (наприклад `firma`, `cenik`) автоматично включають `@ref` і `@showAs` без явного запиту.

## Особливості

- Всі числові значення повертаються як **рядки** (`"50.0"`, `"372.0"`) — потрібен `Double(str) ?? 0`
- Дати у форматі `"2026-04-21"` або `"2026-04-21+02:00"` — безпечно брати `prefix(10)`
- `id` в list-mode для `skladova-karta` завжди `null` — використовувати `UUID()` як Identifiable
- Оновлення запису: `PUT /cenik/<id>.json` — завжди по `id`, не по `kod` (по `kod` створить дублікат)
- Batch PUT: інколи мовчки ігнорує частину записів — надійніше по одному

## Синхронізація

Поточна стратегія: TTL 24 год, зберігається в `UserDefaults` ключ `flexibee_lastSync`.

Майбутня стратегія (delta-sync):
```
GET /cenik.json?conditions=lastUpdate+gt+'<lastSyncDate>'
```
Дозволить завантажувати тільки змінені записи.
