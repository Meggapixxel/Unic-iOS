# UNIC iOS

> 🇺🇦 [Українська](#українська) | 🇬🇧 [English](#english)

---

## Українська

CRM + ERP додаток для команди Chariot Studio (Прага). Управління салонами краси, інвойсами FlexiBee та складськими рухами.

### Архітектура

**Патерни**
- **MVVM** — вся бізнес-логіка та стан у ViewModels (`ObservableObject`). Views не мають `@State` для бізнес-даних.
- **AppRouter** — вся навігація через `router.push(AppDestination)`. Ніколи через `navigationDestination(isPresented:)` напряму у View.
- **`@MainActor`** — всі ViewModels та сервіси з UI-станом позначені `@MainActor`.

**Структура**
```
Models/      — Codable моделі (FlexiBeeModels, Salon, AppUser…)
Services/    — Singleton-сервіси (FirebaseService, FlexiBeeService, AuthService)
Navigation/  — AppRouter, AppDestination, AppNavigationStack
Views/       — View + ViewModel пари (View.swift + View+ViewModel.swift)
```

### Сервіси

**AuthService**
Singleton. Авторизація через Firebase Auth. Ролі: `admin`, `manager`, `sales`.

| Права | admin | manager | sales |
|---|---|---|---|
| Перегляд аналітики / інвойсів | ✅ | ✅ | ❌ |
| Створення / редагування інвойсу | ✅ | ✅ | ❌ |
| Видалення інвойсу / клієнта | ✅ | ❌ | ❌ |
| Рух складу | ✅ | ✅ | ❌ |
| Перегляд користувачів | ✅ | ❌ | ❌ |

**FirebaseService**
Firestore. Основні колекції:

| Колекція | Призначення |
|---|---|
| `salons` | CRM-картки салонів |
| `salons/{id}/statusHistory` | Журнал змін статусу |
| `worksOnTags` | Теги "працює з" |
| `users` | Профілі користувачів |
| `barcodes` | Штрихкоди → артикул FlexiBee |
| `config/bundleCodes` | Коди стартових пакетів (виключення зі складу) |

**FlexiBeeService**
HTTP-клієнт до FlexiBee ERP (Basic Auth). Дані не зберігаються в базі — тільки кеш у пам'яті (`stockWithPrices`, `priceList`). Lazy load через `loadIfNeeded()`.

Ключові ендпоінти:
- `faktura-vydana` — інвойси
- `faktura-vydana-polozka` — позиції інвойсу
- `adresar` — контрагенти (клієнти)
- `cenik` — прайс-лист
- `sklad-pohyb` — складські рухи
- `sklad-pohyb-polozka` — позиції складських рухів

> **Важливо:** `zdrojProSkl` вимкнений для Chariot Studio — FlexiBee не списує склад автоматично при продажу. Всі рухи складу створюються через застосунок.

### Модуль інвойсів

**Кешування**
`SalesViewModel` кешує три набори даних у `UserDefaults` з TTL 1 година:
- `sales_cache_invoices`
- `sales_cache_invoice_items`
- `sales_cache_stock_movements`

**Lifecycle нового інвойсу**
```
Форма (sheet) → submit() → API create → fetchData() → recentlyCreatedInvoiceId
  → onDismiss sheet → router.push(.invoiceWithMovement(invoice))
  → InvoiceDetailView(autoShowMovement: true)
  → load() → triggerStockMovement()
```

### Складський рух

**Логіка вибору потоку**

Після завантаження позицій інвойсу або при ручному натисканні кнопки "Складський рух":

```
triggerStockMovement()
├─ є бандли в інвойсі? → openStockMovement()      [ручний — sheet]
└─ немає бандлів?      → autoCreateStockMovement() [автоматично]
```

- **Автоматичний режим:** API-виклик без UI. При помилці — fallback на ручний режим.
- **Ручний режим:** Sheet з pre-filled звичайними позиціями. Компоненти бандлів додаються вручну.

**Критерії eligible позиції**
1. `item.stockCode != nil` — є явне посилання на ceník (не порожній `cenikRef`)
2. `!bundleCodes.contains(item.productCode)` — не є стартовим пакетом

**Стартові пакети (bundle codes)**
Зберігаються у Firestore `config/bundleCodes.codes: [String]`. Завантажуються при старті застосунку. Бандли не мають BOM у FlexiBee — компоненти вносяться вручну.

**API для руху складу**
```json
POST /sklad-pohyb.json
{
  "winstrom": {
    "sklad-pohyb": [{
      "typDokl": "code:STANDARD",
      "popis": "Vydej k 2025-0042",
      "skladovePolozky": [
        { "cenik": "code:CFB/220", "mnozMj": "2" }
      ]
    }]
  }
}
```

> **Виключення:** `typDokl: "code:VYDEJ"` — невалідний. Правильний тип — `code:STANDARD`. Ключ позицій — `skladovePolozky` (не `polozkyPohybu`).

**Блокування оплати**
Кнопка "Оплачено" з'являється тільки після `stockMovementCreated = true`. Стан сесійний.

### Навігація

```swift
enum AppDestination: Hashable {
    case product(FlexiBeeStockWithPrice)
    case invoice(FlexiBeeInvoice)
    case invoiceWithMovement(FlexiBeeInvoice) // detail + auto-показ руху складу
    case allTopProducts
    case allTopClients
}
```

### Локалізація

Три мови: `uk` (основна), `en`, `ru`. Патерн: `String+Localized.swift` — статичні computed properties, ключі snake_case.

### Вимоги

- iOS 18+
- Xcode 16+
- Firebase SDK (FirebaseCore, FirebaseFirestore, FirebaseAuth)
- IdentifiedCollections (swift-identified-collections)

---

## English

CRM + ERP application for the Chariot Studio team (Prague). Manages beauty salons, FlexiBee invoices, and warehouse stock movements.

### Architecture

**Patterns**
- **MVVM** — all business logic and state lives in ViewModels (`ObservableObject`). Views hold no `@State` for business data.
- **AppRouter** — all navigation goes through `router.push(AppDestination)`. Never via `navigationDestination(isPresented:)` directly in a View.
- **`@MainActor`** — all ViewModels and services with UI state are marked `@MainActor`.

**Structure**
```
Models/      — Codable models (FlexiBeeModels, Salon, AppUser…)
Services/    — Singletons (FirebaseService, FlexiBeeService, AuthService)
Navigation/  — AppRouter, AppDestination, AppNavigationStack
Views/       — View + ViewModel pairs (View.swift + View+ViewModel.swift)
```

### Services

**AuthService**
Singleton. Firebase Auth. Roles: `admin`, `manager`, `sales`.

| Permission | admin | manager | sales |
|---|---|---|---|
| View analytics / invoices | ✅ | ✅ | ❌ |
| Create / edit invoice | ✅ | ✅ | ❌ |
| Delete invoice / client | ✅ | ❌ | ❌ |
| Stock movement | ✅ | ✅ | ❌ |
| View users | ✅ | ❌ | ❌ |

**FirebaseService**
Firestore. Key collections:

| Collection | Purpose |
|---|---|
| `salons` | CRM salon records |
| `salons/{id}/statusHistory` | Status change log |
| `worksOnTags` | "Works with" tags |
| `users` | User profiles |
| `barcodes` | Barcode → FlexiBee article lookup |
| `config/bundleCodes` | Starter kit codes (stock movement exclusion list) |

**FlexiBeeService**
HTTP client for FlexiBee ERP (Basic Auth). Data is not persisted to a database — in-memory cache only (`stockWithPrices`, `priceList`). Lazy-loaded via `loadIfNeeded()`.

Key endpoints:
- `faktura-vydana` — invoices
- `faktura-vydana-polozka` — invoice line items
- `adresar` — counterparties (clients)
- `cenik` — price list
- `sklad-pohyb` — stock movements
- `sklad-pohyb-polozka` — stock movement line items

> **Important:** `zdrojProSkl` is disabled for Chariot Studio — FlexiBee does NOT automatically deduct stock on sale. All stock movements must be created via the app.

### Invoice Module

**Caching**
`SalesViewModel` caches three datasets in `UserDefaults` with a 1-hour TTL:
- `sales_cache_invoices`
- `sales_cache_invoice_items`
- `sales_cache_stock_movements`

**New invoice lifecycle**
```
Form (sheet) → submit() → API create → fetchData() → recentlyCreatedInvoiceId
  → onDismiss sheet → router.push(.invoiceWithMovement(invoice))
  → InvoiceDetailView(autoShowMovement: true)
  → load() → triggerStockMovement()
```

### Stock Movement

**Flow decision logic**

Triggered after invoice line items are loaded (when `autoShowMovement = true`) or manually via the "Stock Movement" button:

```
triggerStockMovement()
├─ invoice has bundle items? → openStockMovement()      [manual — sheet]
└─ no bundle items?          → autoCreateStockMovement() [automatic]
```

- **Automatic mode:** Silent API call, no UI shown. Falls back to manual mode on API failure.
- **Manual mode:** Sheet pre-filled with regular stock items only. Bundle components must be added manually.

**Item eligibility for stock movement**
1. `item.stockCode != nil` — has an explicit ceník reference (non-empty `cenikRef`)
2. `!bundleCodes.contains(item.productCode)` — not a starter kit bundle

**Bundle / starter kit codes**
Stored in Firestore at `config/bundleCodes.codes: [String]`. Loaded at app startup. Bundles have no BOM in FlexiBee — their components must be entered manually.

**Stock movement API payload**
```json
POST /sklad-pohyb.json
{
  "winstrom": {
    "sklad-pohyb": [{
      "typDokl": "code:STANDARD",
      "popis": "Vydej k 2025-0042",
      "skladovePolozky": [
        { "cenik": "code:CFB/220", "mnozMj": "2" }
      ]
    }]
  }
}
```

> **Known exceptions:** `typDokl: "code:VYDEJ"` is invalid — FlexiBee rejects it. Use `code:STANDARD`. Line items key is `skladovePolozky`, not `polozkyPohybu`.

**Payment gating**
The "Paid" button only appears after `stockMovementCreated = true`. This flag is session-only (not persisted across app launches).

### Navigation

```swift
enum AppDestination: Hashable {
    case product(FlexiBeeStockWithPrice)
    case invoice(FlexiBeeInvoice)
    case invoiceWithMovement(FlexiBeeInvoice) // opens detail + auto-triggers stock movement
    case allTopProducts
    case allTopClients
}
```

### Localisation

Three languages: `uk` (primary), `en`, `ru`. Pattern: `String+Localized.swift` with static computed properties and parameterised functions. Keys use snake_case.

### Requirements

- iOS 18+
- Xcode 16+
- Firebase SDK (FirebaseCore, FirebaseFirestore, FirebaseAuth)
- IdentifiedCollections (swift-identified-collections)
