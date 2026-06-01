# 🌾 FarmApp

A comprehensive **offline-first** farm management application built with Flutter. Track your crops from planting to harvest, manage expenses, record sales income, and keep your finances organized — all with or without an internet connection.

---

## ✨ Features

### 🌱 Crop Management
- Track crops through their full lifecycle: **Planning → Planted → Growing → Harvested → Sold / Consumed**
- Record planting and harvest dates
- Log sale amounts and estimated consumption values
- View detailed crop information with expense breakdowns

### 💰 Finance & Expense Tracking
- **Crop-specific expenses** — Track costs tied to individual crops (seeds, fertilizer, labor, etc.)
- **Common expenses** — Record farm-wide expenses not linked to a specific crop (equipment, utilities, etc.)
- **Income tracking** — Log crop sales with quantity, unit, and amount
- **Profit calculation** — See income vs. expenses at a glance

### 📊 Dashboard
- At-a-glance overview of total crops, active (growing) crops, and total expenses
- Quick action shortcuts for adding crops, recording expenses, and viewing finances
- Personalized greeting with user information

### 🔐 Offline-First Authentication
- **Registration** requires internet (creates accounts on both Firebase Auth and local Hive storage)
- **Login** works fully offline using locally stored, hashed credentials
- Passwords are salted and hashed with **SHA-256** before local storage
- Session persistence across app restarts

### ☁️ Cloud Sync (Optional)
- **Bidirectional sync** between local Hive storage and Cloud Firestore
- Toggle sync on/off from Settings — your data stays local if you prefer
- **Last-write-wins** conflict resolution based on `updatedAt` timestamps
- Sync status tracking per record (`pending`, `synced`, `modified`, `deleted`)
- Manual "Sync Now" with detailed push/pull/conflict reporting
- Automatic initial pull when logging in on a new device

### 🔒 Security
- All local data encrypted with **AES-256** via Hive encrypted boxes
- Encryption key stored securely in the platform keychain (`flutter_secure_storage`)
- Firestore security rules enforce per-user data isolation with field-level validation
- Account deletion permanently removes data from both local storage and Firebase

---

## 🏗️ Architecture

### Offline-First Design

```
┌──────────────────────────────────┐
│           Flutter UI             │
│  (Providers / State Management)  │
├──────────────────────────────────┤
│         Service Layer            │
│  AuthService · CropService ·     │
│  FinanceService · SyncService    │
├──────────────┬───────────────────┤
│  Hive (Local)│  Firestore (Cloud)│
│  ● Encrypted │  ● Per-user data  │
│  ● Primary   │  ● Optional sync  │
│    source    │    destination    │
└──────────────┴───────────────────┘
```

All CRUD operations read/write to **Hive first**. Cloud Firestore is only used when sync is enabled and the device is online.

### Project Structure

```
lib/
├── main.dart                      # App entry point, provider setup
├── firebase_options.dart          # Firebase configuration
│
├── core/
│   ├── services/
│   │   ├── hive_service.dart      # Encrypted Hive box management
│   │   └── sync_service.dart      # Bidirectional Hive ↔ Firestore sync
│   ├── theme/
│   │   ├── app_colors.dart        # Color palette & gradients
│   │   └── app_theme.dart         # Material theme configuration
│   └── widgets/
│       ├── custom_button.dart     # Reusable styled button
│       ├── custom_text_field.dart # Reusable styled text field
│       ├── loading_overlay.dart   # Full-screen loading indicator
│       └── main_navigation.dart   # Bottom navigation shell
│
├── features/
│   ├── auth/
│   │   ├── providers/             # AuthProvider (ChangeNotifier)
│   │   ├── screens/               # LoginScreen, RegisterScreen
│   │   └── services/              # AuthService (offline-first auth)
│   ├── crops/
│   │   ├── providers/             # CropProvider
│   │   ├── screens/               # AddCropScreen, CropDetailScreen
│   │   └── services/              # CropService
│   ├── finance/
│   │   ├── providers/             # FinanceProvider
│   │   ├── screens/               # FinanceScreen, AddExpenseScreen, ExpenseListScreen
│   │   └── services/              # FinanceService
│   ├── home/
│   │   ├── providers/             # DashboardProvider
│   │   └── screens/               # HomeScreen (dashboard)
│   └── settings/
│       ├── providers/             # SettingsProvider
│       ├── screens/               # SettingsScreen
│       └── services/              # SettingsService
│
├── models/
│   ├── crop_model.dart            # Crop entity with lifecycle statuses
│   ├── expense_model.dart         # Expense entity (crop-specific & common)
│   ├── sale_model.dart            # Sale entity with quantity & unit
│   └── user_model.dart            # LocalUser entity
│
└── routes/
    └── app_routes.dart            # Named route constants
```

### State Management

The app uses **Provider** (`ChangeNotifierProvider`) for reactive state management:

| Provider | Responsibility |
|---|---|
| `AuthProvider` | Login, registration, session management |
| `CropProvider` | CRUD operations for crops |
| `FinanceProvider` | Expenses, sales, and financial summaries |
| `DashboardProvider` | Aggregated dashboard statistics |
| `SettingsProvider` | Sync toggle, sync execution, app preferences |

---

## 🛠️ Tech Stack

| Category | Technology |
|---|---|
| Framework | Flutter (Dart SDK ^3.11.4) |
| State Management | Provider |
| Local Database | Hive (AES-256 encrypted) |
| Cloud Backend | Firebase (Auth + Cloud Firestore) |
| Secure Storage | flutter_secure_storage |
| Connectivity | connectivity_plus |
| Cryptography | crypto (SHA-256) |
| Unique IDs | uuid (v4) |
| Date Formatting | intl |
| Typography | Google Fonts |

---

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** ≥ 3.11.4
- **Dart SDK** ≥ 3.11.4
- **Firebase project** configured (Android/Web)
- Android Studio / VS Code with Flutter extension

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-username/farm_app.git
   cd farm_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**

   This project uses Firebase for authentication and optional cloud sync. You need to set up your own Firebase project:

   ```bash
   # Install FlutterFire CLI if you haven't
   dart pub global activate flutterfire_cli

   # Configure Firebase for your project
   flutterfire configure
   ```

   This will generate the `firebase_options.dart` file with your project's configuration.

4. **Deploy Firestore rules** (if using cloud sync)
   ```bash
   firebase deploy --only firestore:rules,firestore:indexes
   ```

5. **Run the app**
   ```bash
   flutter run
   ```

### Firebase Emulator (Optional)

For local development without a live Firebase project:

```bash
firebase emulators:start
```

The emulator configuration is already set up in `firebase.json`:
- **Auth emulator**: port `9099`
- **Firestore emulator**: port `8080`
- **Emulator UI**: enabled

---

## 📱 Supported Platforms

| Platform | Status |
|---|---|
| Android | ✅ Primary |
| Web | ✅ Supported |
| iOS | 🔧 Configured |
| Windows | 🔧 Configured |
| macOS | 🔧 Configured |
| Linux | 🔧 Configured |

---

## 🗄️ Data Model

### Firestore Structure

```
users/{userId}/
├── crops/{cropId}
│   └── expenses/{expenseId}
├── common_expenses/{expenseId}
└── sales/{saleId}
```

### Sync Status Lifecycle

```
[Created locally] → pending → [Pushed to cloud] → synced
                                                      ↓
                                              [Edited locally] → modified → [Re-pushed] → synced
                                                      ↓
                                            [Deleted locally] → deleted → [Deleted from cloud] → removed
```
