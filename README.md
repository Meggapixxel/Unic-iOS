# UNIC iOS App

CRM додаток для управління салонами краси в Празі.

## Налаштування

### 1. Додай Firebase SDK через SPM

1. Відкрий проект в Xcode
2. **File → Add Package Dependencies...**
3. Введи URL: `https://github.com/firebase/firebase-ios-sdk`
4. Вибери версію: **Up to Next Major Version** (11.0.0)
5. Додай packages:
   - `FirebaseCore`
   - `FirebaseFirestore`

### 2. Завантаж GoogleService-Info.plist

1. Відкрий [Firebase Console](https://console.firebase.google.com/project/unic-e02f4/settings/general/ios:com.unic.unic-ios)
2. Зареєструй iOS app з Bundle ID: `com.unic.unic-ios`
3. Завантаж `GoogleService-Info.plist`
4. Заміни файл в проекті

### 3. Додай файли до проекту

В Xcode Project Navigator:
1. Правий клік на папці `unic-ios`
2. **Add Files to "unic-ios"...**
3. Вибери папки: `Models`, `Services`, `ViewModels`, `Views`
4. ✅ "Copy items if needed"
5. ✅ "Create groups"

## Структура проекту

```
unic-ios/
├── Models/
│   └── Salon.swift          # Модель даних салону
├── Services/
│   └── FirebaseService.swift # Сервіс для Firestore
├── ViewModels/
│   └── SalonsViewModel.swift # ViewModel для списку
├── Views/
│   ├── SalonListView.swift   # Головний екран
│   └── SalonDetailView.swift # Деталі салону
├── GoogleService-Info.plist  # Firebase config
└── unic_iosApp.swift         # Entry point
```

## Функціонал

- ✅ Список 837 салонів з Firestore
- ✅ Пошук по назві та адресі
- ✅ Фільтрація по статусу (new, contacted, demo, testing, ordered, lost)
- ✅ Детальна картка салону
- ✅ Швидкі дії: зателефонувати, відкрити карту, Instagram, сайт
- ✅ CRM поля: статус, lead temp, нотатки
- ✅ Pull-to-refresh

## Firebase

- **Project:** unic-e02f4
- **Collection:** `salons`
- **Documents:** 837 салонів

## Вимоги

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
