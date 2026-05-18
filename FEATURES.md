# UNIC iOS — Comprehensive Feature & Screen Reference for Android Porting

This document is the single exhaustive reference for every screen and feature in the UNIC iOS app.
It combines business logic, API calls, data rules, visual layout, UI elements, and interactions.
Written in platform-agnostic language for Android developers.

---

## Table of Contents

- [Data Models Reference](#data-models-reference)
- [Shared UI Patterns](#shared-ui-patterns)
- [Domain: Auth](#domain-auth)
  - [Screen: App Lifecycle & Authentication Gate](#screen-app-lifecycle--authentication-gate)
  - [Screen: Login](#screen-login)
  - [Screen: Welcome (Loading Splash)](#screen-welcome-loading-splash)
  - [Screen: Main (Tab Container)](#screen-main-tab-container)
- [Domain: Plans](#domain-plans)
  - [Screen: Plan Progress Banner](#screen-plan-progress-banner)
  - [Screen: Plans List](#screen-plans-list)
  - [Screen: Plan Create / Edit Form](#screen-plan-create--edit-form)
- [Domain: Salons](#domain-salons)
  - [Screen: Salons List](#screen-salons-list)
  - [Screen: Salons Map View](#screen-salons-map-view)
  - [Sheet: Salons Filter Popover](#sheet-salons-filter-popover)
  - [Sheet: Status Info](#sheet-status-info)
  - [Screen: Salon Detail](#screen-salon-detail)
  - [Screen: Salon Full Map](#screen-salon-full-map)
  - [Sheet: Add Status](#sheet-add-status)
  - [Sheet: Status History](#sheet-status-history)
  - [Sheet: Edit Note (within Status History)](#sheet-edit-note-within-status-history)
  - [Screen: Salon Create / Edit Form](#screen-salon-create--edit-form)
  - [Screen: Test Drive List](#screen-test-drive-list)
  - [Screen: Route Planner](#screen-route-planner)
- [Domain: Sales](#domain-sales)
  - [Screen: Sales Dashboard](#screen-sales-dashboard)
  - [Screen: All Top Clients](#screen-all-top-clients)
  - [Screen: All Top Products](#screen-all-top-products)
  - [Screen: Invoice Detail](#screen-invoice-detail)
  - [Sheet: Payment Method Picker](#sheet-payment-method-picker)
  - [Screen: Invoice Create / Edit Form](#screen-invoice-create--edit-form)
  - [Sheet: Client Picker (Firm Picker)](#sheet-client-picker-firm-picker)
  - [Sheet: Create Client](#sheet-create-client)
  - [Sheet: Product Picker](#sheet-product-picker)
  - [Screen: Stock Movement Form](#screen-stock-movement-form)
  - [Screen: Client Detail](#screen-client-detail)
  - [Sheet: Edit Client](#sheet-edit-client)
  - [Screen: Product Detail](#screen-product-detail)
- [Domain: Stock](#domain-stock)
  - [Screen: Stock Tab](#screen-stock-tab)
  - [Sheet: Barcode Scanner](#sheet-barcode-scanner)
  - [Sheet: Stock Checklist](#sheet-stock-checklist)
  - [Screen: PDF Catalog Viewer](#screen-pdf-catalog-viewer)
- [Domain: Promos](#domain-promos)
  - [Screen: Promos Tab](#screen-promos-tab)
  - [Sheet: Promo Detail](#sheet-promo-detail)
  - [Sheet: Promo Create / Edit Form](#sheet-promo-create--edit-form)
- [Domain: Profile](#domain-profile)
  - [Screen: Profile](#screen-profile)
  - [Screen: User Activity](#screen-user-activity)
  - [Screen: Users List](#screen-users-list)

---

# Domain: Auth

---

## Screen: App Lifecycle & Authentication Gate

### Purpose
Manages the top-level lifecycle of the app. Decides which screen to show based on the user's login state and smoothly transitions between unauthenticated, loading, and fully authenticated states.

### Layout
The user sees one of four states, each occupying the full screen:

| State | What the user sees |
|---|---|
| `loading` | Centered spinner — no other content |
| `auth` | Login screen |
| `welcome` | Welcome splash (data preloading) |
| `main` | Four-tab main interface |

### Data displayed
A loading indicator during startup. No data shown to the user at this level.

### User actions
None — the user does not interact with this layer directly.

### Business rules
- On cold launch the app enters a `loading` state while listening for an auth event from Firebase.
- If Firebase reports no session (signed out), the app switches to the Login screen.
- If Firebase reports a valid session, the app switches to the Welcome / Splash screen to preload data.
- If the app is already on the main screen and a token refresh event arrives, only the in-memory user record is updated; navigation is not reset.
- Once the Splash screen finishes preloading, the app transitions to the Main (tab bar) screen.
- Sign-out from anywhere in the app sends the user back to the Login screen.

### API / Data sources
- Firebase Auth — a continuous real-time listener is opened once on app start and is never closed.

### Navigation
- `loading` → Login screen (on no session)
- `loading` → Welcome screen (on valid session)
- Welcome screen → Main screen (after preloading completes)
- Main screen → Login screen (on sign-out)

### Empty / Loading states
The entire screen is the loading state — a centered spinner with no other content.

---

## Screen: Login

### Purpose
Lets the user enter an email address and password and sign in to Firebase.

### Layout
Full-screen centered column with a large bold title, two input fields, an optional error message below the fields, a primary Login button, and a spinner below the button while loading.

### Data displayed
- Large bold title ("Login" or equivalent localized string)
- Email text field (email keyboard, lowercase-only)
- Password field (masked input)
- Error message text in red (visible only when a login error occurred — shown between the fields and button)
- Login button (primary/prominent style)
- Spinner below the button while the login request is in-flight

### User actions
- Type email and password.
- Tap the **Login button** — submits the credentials. On success the auth listener in the App Lifecycle layer picks up the session and navigates forward automatically. On failure, an error message is shown.
- The login button is disabled while a request is in progress (`isLoading` is true).

### Business rules
- The Login button does nothing if either field is empty.
- If the network call fails, the error message from Firebase is displayed and the user can try again.
- The screen itself does not navigate anywhere; all transitions are driven by the auth listener.

### API / Data sources
- Firebase Auth `signInWithEmailAndPassword` — called once per login attempt.

### Navigation
None from this screen. Navigation away is triggered by the auth listener in the App Lifecycle layer.

### Empty / Loading states
- While loading: the button is disabled and a spinner appears below it.
- On error: a red caption text appears between the button and the fields.

---

## Screen: Welcome (Loading Splash)

### Purpose
A brief loading screen shown after login while the app fetches the initial salon data. Ensures a minimum display time of 1 second so the transition does not feel abrupt. Also requests location permission as soon as it appears.

### Layout
Full-screen centered content with a large accent-colored sparkle icon, app name in large bold text, a personalized greeting, and a spinner pinned near the bottom edge of the screen.

### Data displayed
- Large accent-colored sparkle icon
- "UNIC" app name (bold, large)
- Greeting text: "Hello, [FirstName]!" in the user's language
- Spinner at the bottom edge

### User actions
None — the screen advances automatically.

### Business rules
- The screen waits for two conditions before proceeding: (1) the salon data fetch has completed (success or failure), and (2) at least 1 second has elapsed.
- If the salon fetch fails, the app continues with an empty salon list — the user is never blocked.
- Preloaded salons are passed directly into the Main screen, avoiding a second network call.
- The screen requests device location permission on appearance.

### API / Data sources
- Firebase — `fetchAllSalons` — one-shot read of the full salon collection.

### Navigation
Automatically advances to the Main screen when both readiness conditions are met.

### Empty / Loading states
Always shows a loading spinner — the screen itself is the loading state.

---

## Screen: Main (Tab Container)

### Purpose
The root screen of the authenticated experience, providing four tabs that the user can switch between freely. A floating plan progress banner is overlaid on all tabs.

### Layout
Four-tab bottom navigation bar. A floating semi-transparent plan progress banner overlays the top of all tabs (it does not intercept taps or block scrolling).

**Tabs:**

| Position | Label | Icon |
|---|---|---|
| 1 | Salons | Storefront |
| 2 | Promos | Tag |
| 3 | Stock | Shipping box |
| 4 | Profile | Person circle |

### Data displayed
Whichever tab is currently selected. The tab bar shows labels/icons for Salons, Promos, Stock, and Profile.

### User actions
- Tap any tab item to switch to it.
- The floating plan banner is display-only and cannot be tapped.

### Business rules
- The selected tab defaults to Salons on first load.
- Each tab manages its own navigation stack internally.
- A floating Plan Progress Banner is overlaid on this screen (see [Screen: Plan Progress Banner](#screen-plan-progress-banner)).

### API / Data sources
None at this level; each tab loads its own data.

### Navigation
- Salons tab → Salons List
- Promos tab → Promos Tab
- Stock tab → Stock Tab
- Profile tab → Profile Screen

### Empty / Loading states
None at this level.

---

# Domain: Plans

---

## Screen: Plan Progress Banner

### Purpose
A floating overlay shown on top of all Main screen tabs that displays the user's current active plan and their progress toward goals.

### Layout
A narrow, translucent bar overlaid near the top of all four main tabs (below the navigation bar area). It is purely informational and cannot be tapped — it passes through all touch events. Shows compact progress summary (e.g. ring indicators or counts). Disappears entirely when there is no active plan.

### Data displayed
- Plan name / period (start and end dates).
- Progress indicators (e.g. salons visited vs. target, test drives vs. target) — a compact summary.
- Hidden entirely when no active plan exists.

### User actions
None — the banner is display-only.

### Business rules
- The banner fetches the active plan once per session on load. There is no automatic refresh.
- If the fetch fails, the banner stays hidden silently.
- If no active plan is found, the banner is not shown.

### API / Data sources
- Firebase — `fetchActivePlan` — one-shot read.

### Navigation
None.

### Empty / Loading states
Banner is hidden when there is no active plan or when the fetch fails.

---

## Screen: Plans List

### Purpose
Lets managers view all work plans, create new ones, edit existing ones, and delete them.

### Layout
Grouped list with an inline "Plans" title. A plus (+) button in the top-right toolbar appears for users who can manage plans.

### Data displayed
A list of plans sorted newest-first. Each plan row shows:
- Plan period string (bold headline, left)
- Status badge (right): "● Active" (green), "✓ Done" (gray), "◌ Upcoming" (orange)
- Duration in days (e.g. "31 d")
- Target chips: salon icon + "X/day (Y)" showing daily and total salon targets; car icon + "X/day (Y)" showing daily and total test-drive targets
- An Add button in the toolbar (visible to users with `canManagePlans` permission)
- A loading indicator while fetching
- An error banner if the fetch fails

### User actions
- Tap **Add (+)** → opens the Plan Create form.
- **Swipe left on a plan row** (managers/admins only): reveals two buttons:
  - **Delete** (red trash icon) — shows a confirmation dialog, then deletes.
  - **Edit** (orange pencil icon) — opens the Plan Edit form pre-filled with that plan's data.

### Business rules
- Only users with the `canManagePlans` permission see the Add, Edit, and Delete controls.
- When a new plan is created and saved, it is automatically assigned to all users in the system (a batch Firebase write).
- When an existing plan is edited and saved, only that plan document is updated — users are not re-assigned.
- Deletion is optimistic: the plan is removed from the list immediately, then the Firebase delete runs in the background.

### API / Data sources
- Firebase — `fetchAllPlans` — read on load.
- Firebase — `fetchDefaultPlan` — read on load to pre-fill the create form; failures are silently ignored.
- Firebase — `deletePlan(id)` — write on delete confirmation.
- Firebase — `savePlan(plan)` — write inside the Plan Form.
- Firebase — `setPlanForAllUsers(plan)` — batch write after a new plan is saved.

### Navigation
- Tap Add → Plan Create Form (modal sheet)
- Tap edit icon (swipe action) → Plan Edit Form (modal sheet)

### Empty / Loading states
- Loading: full-screen frosted spinner overlay.
- Empty: empty state icon with "No plans" + target icon.
- Error alert if a save or delete fails.
- Confirmation dialog before deleting a plan.

---

## Screen: Plan Create / Edit Form

### Purpose
A form for creating a new work plan or editing an existing one.

### Layout
Full-height modal sheet with a form, titled "Add Plan". Contains a scrollable form with three sections.

**Sections:**
1. **Dates** — Start Date picker (date only) + End Date picker (date only, minimum = start date).
2. **Daily Goals** (section header: "Goal Per Day") — Salons stepper: minus/plus buttons with current value (0–99), label with storefront icon; Test Drives stepper: same layout with car icon.
3. **Period Total Goals** (section header: "Total Goal") — Salons stepper (0–999); Test Drives stepper (0–999).

Close (X) button on the left, checkmark (or spinner) button on the right.

### Data displayed (form fields)
- Start date picker
- End date picker
- Salons per day (numeric stepper, 0–99)
- Total salons target (numeric stepper, 0–999; 0 means no cap)
- Test drives per day (numeric stepper, 0–99)
- Total test drives target (numeric stepper, 0–999; 0 means no cap)

### User actions
- Adjust any field using date pickers and +/- steppers.
- Tap **Checkmark** → validates the form, saves to Firebase, and closes the sheet.
- Tap **Close (X)** → closes the sheet without saving.

### Business rules
- Save is disabled unless the end date is after the start date.
- In create mode, the form is pre-filled with organisation-wide default targets (fetched by the Plans List screen). In edit mode, the form is pre-filled with the plan's existing values.
- When saving, total targets of 0 are stored as "no target" (nil).
- New plans are automatically propagated to all users by the Plans List after the form closes.

### API / Data sources
- Firebase — `savePlan(plan)` — write on save.

### Navigation
None; the sheet closes on save or cancel.

### Empty / Loading states
- Frosted spinner overlay while saving.
- Error alert if saving fails.

---

# Domain: Salons

---

## Screen: Salons List

### Purpose
The primary work screen for sales reps. Shows all salon prospects in the system with rich filtering, sorting, search, and a map view alternative.

### Layout
Large navigation title "Salons" at the top. A search bar below the title (always visible when list mode is active). Scrollable plain list with:
- First row: a "Test Drive" special navigation row (flask icon + count of active test drives)
- All remaining rows: one row per salon

A sticky bottom panel contains:
- A stats row with four colored badges: Total, New, Contacted, Clients
- A horizontally scrollable row of filter chips for salon status

**Toolbar items:**
- Left side: Filter icon (funnel) — opens the Filter Popover; icon becomes filled when any filter is active
- Right side (three buttons): Plus (+) to create a new salon, Route icon (curved path) to open Route Planner (disabled if fewer than 2 salons have coordinates), Map/List toggle icon

### Data displayed
- A scrollable list of salon rows, each showing:
  - Salon name (bold headline)
  - Status badge (colored label: New, Contacted, Demo Scheduled, Test Drive, Ordered, Other)
  - Address (secondary, single line, truncated)
  - Contact icon row: phone (green), Instagram (purple), Facebook (blue), website (orange), language flag emoji
- Stats row at the bottom bar: total salons, new, contacted, clients counts
- Status filter chips (All, New, Contacted, Test Drive, Demo Scheduled, Ordered, Other, "?" info chip)
- Search field above the list

### User actions
- **Search bar** — filters the list in real time by salon name/address.
- **Pull to refresh** — reloads salon data from the server.
- **Tap a salon row** — navigates to Salon Detail.
- **Tap the Test Drive row** — navigates to the Test Drive screen.
- **Status filter chips** (bottom bar, horizontally scrollable): "All" chip clears the filter; one chip per status toggles that status (multiple can be selected); "?" chip opens the Status Info sheet.
- **Filter icon** (funnel, left toolbar) — opens the Filter Popover.
- **Plus (+)** (right toolbar, requires `canEditSalon` permission) — opens the Salon Create form.
- **Route icon** (right toolbar) — opens Route Planner; disabled if fewer than 2 salons have coordinates.
- **Map/List toggle icon** (right toolbar) — switches between list and map view.

### Business rules
- Salons are loaded from Firebase once on first appearance. Navigating back from a detail screen does not trigger a re-fetch.
- The Add button is only available to users with the `canEditSalon` permission.
- Filter chips, search, sort, and map toggle are all applied client-side with no additional API calls.
- Status filter chips apply on top of all other filters. Stats counts (new, contacted, etc.) are computed from the search- and language-filtered list but ignore the status chip, so the numbers reflect the broader set.
- When a salon is saved or deleted in a child screen, the list is updated immediately without a reload.

### API / Data sources
- Firebase — `fetchAllSalons` — called once on first load.
- Firebase — `loadWorksOnTags` — called concurrently with the salons fetch to populate the "Works On" tag options used in forms.

### Navigation
- Tap salon row → Salon Detail
- Tap Test Drive row → Test Drive List
- Tap Add (+) → Salon Create / Edit Form (modal sheet)
- Tap Route icon → Route Planner
- Tap Map/List toggle → Salons Map View
- Filter icon → Filter Popover (inline popover)
- "?" chip → Status Info sheet (modal)

### Empty / Loading states
- While loading: full-height centered spinner with "Loading…" text.
- On error: orange warning icon + error message + "Retry" button.
- Empty list after filter: the list is simply empty (no special placeholder shown).

---

## Screen: Salons Map View

### Purpose
An alternative view of the Salons tab displaying salon locations on an interactive map with status-colored pins.

### Layout
Full-screen native map. The status filter chip bar and a "X salons on map" caption are pinned at the bottom inside a frosted glass panel. Map/List toggle is in the right toolbar.

### Data displayed
- Colored pins for each salon that has GPS coordinates. Pin color matches the salon's status color.
- Cluster bubbles (gray) when pins are close together.
- User's current location dot (blue).
- "X salons on map" caption above the filter chips.

### User actions
- **Tap a pin** — shows a callout bubble with the salon name and two buttons: left (info/detail disclosure) navigates to Salon Detail; right (navigation arrow icon) opens Google Maps or Apple Maps for turn-by-turn directions.
- **Tap a cluster** — zooms in to expand the cluster.
- **Tap the "center on me" button** (top-right, location arrow icon, visible only when location permission is granted) — pans the map to the user's current position.
- **Status filter chips** — same as in list view; filters which pins are shown.
- **"?" chip** — opens the Status Info sheet.
- **Map/List toggle** (toolbar, right side) — switches back to list view.

### Business rules
- Salons without coordinates are not shown on the map.
- No special empty state is shown if all salons lack coordinates — the map simply shows no pins.

### API / Data sources
None beyond what is already loaded by the Salons List.

### Navigation
- Tap pin callout (info button) → Salon Detail
- "?" chip → Status Info sheet

### Empty / Loading states
Salons without coordinates are silently omitted. No empty state is shown if no pins exist.

---

## Sheet: Salons Filter Popover

### Purpose
A compact popover for sorting and filtering the salon list by sort order, date added range, and language.

### Layout
A small popover (approximately 240 pt wide) anchored to the filter (funnel) button. Contains a scrollable vertical list of filter sections.

**Sections:**
1. **Sorting** — radio-style list of sort options: Name, Lead Temperature, Status, Date Added. Below the options, two small Up/Down arrow buttons select ascending or descending order. The active direction button is highlighted.
2. **Date Added** — checkbox-style list of date range options (e.g. This week, This month, etc.). Multiple can be selected.
3. **Language** — checkbox-style list of available languages. Multiple can be selected.
4. **Reset button** (top-right of popover, visible only when any filter is active) — clears all filters.

### Data displayed
- Sort options with current selection and direction.
- Date range chips (available ranges derived from salon data).
- Language chips (populated from languages found in salon data).

### User actions
- Tap a sort option — selects it (radio behavior).
- Tap the Up or Down arrow — sets the sort direction.
- Tap a date range or language — toggles it on/off.
- Tap "Reset" button — clears everything.

### Business rules
- All filtering and sorting is applied client-side with no additional API calls.
- The "Clear Filters" / "Reset" button is only visible when any non-status filter is active.

### API / Data sources
None.

### Navigation
None; the popover closes on tap-outside or after an interaction.

### Empty / Loading states
None.

---

## Sheet: Status Info

### Purpose
An informational sheet explaining each salon pipeline status — what it means and what action is expected next.

### Layout
Full-height modal list with a close button (X) in the top-right toolbar. A plain list of all salon statuses.

### Data displayed
Each row contains:
- Emoji + status full display name (bold)
- Description text (what this status means)
- Next action prompt (in the status's color)

### User actions
- **Close button (X)** — dismisses the sheet.

### Business rules
Static informational content; no API calls.

### API / Data sources
None.

### Navigation
None.

### Empty / Loading states
None.

---

## Screen: Salon Detail

### Purpose
Shows all information about a single salon prospect and provides actions to update its pipeline status, edit its data, or delete it.

### Layout
Scrollable screen with a large title (salon name). Content is organized into vertical sections (not a list). An edit button (pencil icon) appears in the top-right toolbar if the user has edit permission. Sections in order:
1. Quick Actions (horizontal button row)
2. Location (map thumbnail + address + coordinates)
3. Status (current status card)
4. CRM (lead temp, language, works-on tags, enrichment)
5. Notes (free text, if present)
6. Delete button (only for users with delete permission)
7. Admin section (Firestore ID, only for admins)

---

**Quick Actions Section:** Horizontal row of action buttons. Each button shows a colored icon and a label below it. Only buttons for which data exists are shown:
- **Call** (green phone icon) — initiates a phone call. Long-pressing shows a context menu with "Copy number" and "Call" options.
- **Instagram** (purple camera icon) — opens the salon's Instagram URL.
- **Facebook** (blue thumbs-up icon) — opens the salon's Facebook page.
- **Website** (orange globe icon) — opens the salon's website.

**Location Section:** Visible only when the salon has an address or coordinates. Contains:
- **Map thumbnail** (150 pt tall, non-interactive, with a colored status-color pin) — tapping navigates to the Salon Full Map screen; an "expand" icon overlay is shown in the top-right corner.
- **Address row** — address text with a pin icon; tapping copies the address to clipboard; a navigation arrow button (blue, right side) opens Google Maps or Apple Maps for directions.
- **Coordinates row** — latitude/longitude in monospace text with a copy icon; tapping copies the coordinate string.

**Status Section:** Card with:
- "Current status" label on the left; status badge (colored rounded label) on the right.
- Plus button (circle with + icon) next to the status badge — opens the Add Status sheet.
- A hint text below.
- Latest status note (if any), displayed in secondary text.
- "Change History" row at the bottom — tapping opens the Status History sheet.

**CRM Section:** Card with rows:
- Lead temperature: label on left, one of three colored badge options (A/B/C) on right, or "—" if not set.
- Language: label on left, flag emoji on right (Czech, Ukrainian, Russian, English).
- Works On tags (if any): label above, then a wrapped flow of capsule-shaped tags.
- Enrichment status (if set): a blue-tinted badge label.

**Notes Section:** Visible only when the salon has non-empty notes. Shows free text in secondary color inside a rounded gray card.

**Delete Section:** Visible only to users with the delete permission. Full-width red destructive button labeled "Delete Salon" with a trash icon. Shows a spinner while deletion is in progress. Tapping shows a confirmation dialog.

**Admin Section:** Visible only to admins. Displays the internal Firestore document ID in monospace text (selectable for copying).

### Data displayed
- Salon name, city, address.
- Contact links: phone, Instagram, website, Facebook.
- Pipeline status badge.
- Lead temperature badge (A / B / C).
- Languages / "Works On" tags.
- Notes.
- Latest status history entry (status, timestamp, note).
- A "Change History" / "View All History" button.
- Edit and Delete buttons (shown only to users with the relevant permissions).
- Map thumbnail if coordinates are available.
- Coordinates row (latitude/longitude).
- Firestore document ID (admins only).

### User actions
- Tap **phone number / Call button** → opens the phone dialer. Long-press shows "Copy number" and "Call" context menu.
- Tap **Instagram / Facebook / Website button** → opens in browser/app.
- Tap **map thumbnail** → opens Salon Full Map screen.
- Tap **address row** → copies address to clipboard.
- Tap **navigation arrow** next to address → opens Google Maps or Apple Maps for directions.
- Tap **coordinates row** → copies coordinate string to clipboard.
- Tap **Plus button** (on status card) → opens the Add Status sheet.
- Tap **"Change History"** row → opens the Status History sheet.
- Tap **Edit (pencil icon)** in toolbar → opens the Salon Edit form.
- Tap **Delete button** → shows a delete confirmation dialog.
- Confirm delete → salon is deleted from Firebase; the screen closes and the salon is removed from the list.

### Business rules
- On load, the app fetches the latest status history entry from Firebase to show the most current "last contact" row.
- Edit permission is controlled by `canEditSalon`. Delete permission is controlled by `canDeleteSalon`.
- After a successful delete, the parent Salons List is updated automatically.
- After saving an edit, the salon data in the list is updated in place without a full reload.
- The edit form is pre-populated with the current salon data.
- Sections that have no data (no phone, no Instagram, no notes, etc.) are hidden entirely.

### API / Data sources
- Firebase — `fetchLatestStatusEntry(salonId)` — called on load.
- Firebase — `fetchStatusHistory(salonId)` — called when the history sheet is opened or after a note update.
- Firebase — `deleteSalon(salonId)` — called on delete confirmation.
- Firebase — `updateStatusEntryNote` / `deleteStatusHistoryEntry` — called from the history sheet.

### Navigation
- Tap Edit (toolbar) → Salon Edit Form (modal sheet)
- Tap Plus on status → Add Status Sheet (modal)
- Tap "Change History" → Status History Sheet (modal)
- Tap map thumbnail → Salon Full Map (navigation push)
- Delete confirmed → pops back to Salons List

### Empty / Loading states
Sections that have no data are hidden entirely. No explicit loading state for the detail screen itself (data is loaded from the parent and supplemented by the status entry fetch on load).

---

## Screen: Salon Full Map

### Purpose
Full-screen interactive map focused on a single salon's location, with navigation options and call support.

### Layout
Full-screen interactive map with the salon's name as the navigation title. A frosted glass info card is pinned at the bottom.

**Bottom info card (from left to right/top):**
- Salon name (headline)
- Address + copy icon button (copies address to clipboard)
- Status badge (right side)
- Call button (green, only if phone number exists) — long-press shows context menu with phone number, copy, and call options
- "Google Maps" button (opens Google Maps, only if a Google Maps URL exists)

### Data displayed
- Full-screen interactive map with a single colored pin (scissors icon) at the salon's location.
- Bottom info card: salon name, address, status badge, call button, Google Maps button.

### User actions
- Map is fully interactive (pan, zoom, tilt, rotate).
- **Map style menu** (top-right toolbar, map circle icon) — choose Standard, Satellite, or Hybrid.
- **Open in external app button** (top-right toolbar, share/arrow icon) — opens Google Maps.
- **Call button** in bottom card — initiates phone call.
- **Google Maps button** in bottom card — opens Google Maps.
- **Copy icon** next to address — copies address text to clipboard.
- Map controls: user location button, compass, scale, pitch toggle.

### Business rules
- If the salon has no coordinates, the map is not shown. Instead, an empty state message is displayed ("No location data").

### API / Data sources
None — data is passed in from the parent Salon Detail.

### Navigation
None — this is a leaf screen. Back navigation returns to Salon Detail.

### Empty / Loading states
If the salon has no coordinates: empty state message ("No location data").

---

## Sheet: Add Status

### Purpose
Lets a sales rep record a new status update for a salon — marking it as Contacted, Test Drive, Demo Scheduled, etc. — along with an optional note and the user's current GPS location.

### Layout
Modal sheet with a navigation bar. Contains a form with four conditional sections:
1. **Status picker section** — inline list of all statuses, each with a colored dot and name. One status is selected at a time.
2. **Demo Date section** (visible only when "Demo Scheduled" is selected) — date and time picker.
3. **Articles section** (visible only when "Test Drive" is selected) — searchable multi-select tag editor for article/product codes from stock.
4. **Note section** — multi-line optional text field for a comment.

Close (X) button on the left, Checkmark button on the right (disabled while saving).

A frosted overlay with a spinner and "Fetching location…" text appears while the location is being captured on save.

### Data displayed
- Status picker (all pipeline statuses available).
- A date/time picker for the scheduled demo date (shown only when "Demo Scheduled" is selected).
- An article/product picker for test-drive items (shown only when "Test Drive" is selected; items loaded from the FlexiBee stock cache).
- A free-text notes field.
- An error alert if location could not be obtained.

### User actions
- Tap a status to select it.
- (If Demo Scheduled) pick a scheduled demo date/time (must be tomorrow or later).
- (If Test Drive) search and tap to select/deselect one or more product article codes.
- Type a note.
- Tap **Checkmark** → the app fetches the device's GPS location, writes the entry to Firebase, then closes the sheet.
- Tap **Close (X)** → closes the sheet without saving.

### Business rules
- Saving requires a valid GPS location. If location access is denied or unavailable, the app shows an error alert and does not save.
- After saving, the entry is appended to the salon's status history and the salon's pipeline status is updated in place on the detail screen — no additional network call is needed.
- For Test Drive entries, the selected article codes are joined into the note automatically.
- For Demo Scheduled entries, the chosen date is stored alongside the entry.
- Article codes for the picker are read from the local FlexiBee stock cache (no network call).
- The minimum selectable demo date is tomorrow.

### API / Data sources
- Device location API — async fetch on every save attempt.
- Firebase — `addStatusHistoryEntry` — write on save.
- Firebase — `fetchStatusHistory(salonId)` — read immediately after the write to retrieve the server-assigned entry ID.
- FlexiBee local cache — `stockWithPrices()` — synchronous read on load for the article picker.

### Navigation
None; the sheet closes on save or cancel.

### Empty / Loading states
- Frosted overlay + spinner + "Fetching location…" while location is being captured.
- An alert appears if location access is unavailable.

---

## Sheet: Status History

### Purpose
Shows the full chronological log of all status changes recorded for a salon.

### Layout
Full-height modal sheet with an inline title. Shows either a loading spinner, an empty state, or a plain list.

**Each history row shows:**
- Colored dot (status color)
- Status name (bold)
- Date/time (right-aligned, secondary)
- Note text below (if any)

### Data displayed
- A list of entries, each showing: status badge, timestamp, user who recorded it, optional note.
- For admins: swipe actions for editing/deleting each entry.
- A loading indicator while history is being fetched.

### User actions
- Scroll to review all past entries.
- **Swipe left on a row** (admins only): reveals an edit (pencil) button — opens the Edit Note sheet for that entry.
- **Swipe right on a row** (admins only): reveals a red delete button — deletes that history entry.
- Close the sheet by swiping down (no explicit close button needed).

### Business rules
- The history is fetched from Firebase the first time the sheet is opened. Subsequent opens within the same session reuse the cached list.
- Editing and deleting are only available to users with the `isAdmin` permission.
- After editing a note, the full history is re-fetched to ensure consistency.
- After deleting an entry, it is removed from the local list optimistically and then deleted from Firebase in the background.

### API / Data sources
- Firebase — `fetchStatusHistory(salonId)` — read on first open and after note update.
- Firebase — `updateStatusEntryNote` / `deleteStatusHistoryEntry` — writes on admin actions.

### Navigation
- Swipe-left edit action → Edit Note sheet (for editing a specific history entry's note).

### Empty / Loading states
- Loading: full-height centered spinner with "Loading…".
- Empty: icon + "No history" message.

---

## Sheet: Edit Note (within Status History)

### Purpose
Allows admins to edit the note text of a specific status history entry.

### Layout
A partial-height modal (medium detent). Contains a read-only header row (status color dot, status name, date) and an editable multi-line text field for the note. Close (X) button on the left, Checkmark button on the right.

### Data displayed
- Read-only header: status color dot, status name, timestamp.
- Editable multi-line text field for the note.

### User actions
- Edit the note text field.
- Tap **Checkmark** → saves and dismisses.
- Tap **Close (X)** → dismisses without saving.

### Business rules
- Only admins can access this sheet (gated by swipe action visibility in Status History).

### API / Data sources
- Firebase — `updateStatusEntryNote` — write on save (triggered from parent Status History sheet).

### Navigation
None; closes on save or dismiss, returning to Status History.

### Empty / Loading states
None.

---

## Screen: Salon Create / Edit Form

### Purpose
Lets authorised users create a new salon record or edit the basic information of an existing one.

### Layout
Full-height modal sheet with a navigation bar titled "Add Salon" (or "Edit Salon"). Contains a scrollable form.

**Sections:**
1. **Main** — salon name text field (required)
2. **Location** — address text field; footer note explains geocoding behavior
3. **Contacts** — phone number field (phone keyboard), Instagram handle field (with "@" prefix label), website URL field, Facebook URL field
4. **CRM** — language segmented picker (flags: Ukrainian, Russian, Czech, English); lead temperature selector (tap A, B, or C badge; tap again to deselect)
5. **Works On** — multi-select tag editor (loaded from server; searchable)
6. **Notes** — multi-line text field

Close (X) button on the left, Checkmark button on the right (disabled if name is empty or while saving).

### Data displayed (form fields)
- Name (required)
- Address (full address; geocoded automatically on save if changed)
- Phone
- Instagram handle (without `@` or full URL)
- Website URL
- Facebook URL
- Language picker (Ukrainian, Russian, Czech, English — shown as flag segments)
- Lead Temperature picker (A / B / C; can be cleared by tapping again)
- "Works On" tag multi-select (populated from Firebase tags)
- Notes (multi-line)

### User actions
- Fill in / edit any field.
- Tap language flag segment — selects that language.
- Tap A / B / C badge — toggles lead temperature selection.
- Select/deselect "Works On" tags.
- Tap **Checkmark** → saves the salon to Firebase and closes the form.
- Tap **Close (X)** → if any field has been changed, shows a "Discard Changes?" confirmation. If unchanged, closes immediately.
- Confirm discard → closes without saving.
- Swipe down to dismiss is blocked when there are unsaved changes.

### Business rules
- Save is disabled until the Name field contains at least one non-whitespace character.
- When creating, the new salon is added to the list. When editing, the existing entry is updated in place.
- If the address or city changed during an edit, the backend geocodes the new address automatically.
- Swiping down to dismiss is blocked when there are unsaved changes (user must tap Close and confirm).
- The "Works On" tag list is fetched from Firebase once on form open.

### API / Data sources
- Firebase — `loadWorksOnTags` — read on load.
- FirebaseService — `createSalon` — write when creating a new salon.
- FirebaseService — `updateSalonBasicInfo` — write when editing an existing salon (may trigger geocoding).

### Navigation
None; the form closes on save or discard.

### Empty / Loading states
- A centered frosted spinner appears while saving.
- An error alert appears if saving fails.
- "Discard Changes?" confirmation dialog when closing with unsaved changes.

---

## Screen: Test Drive List

### Purpose
Shows a filtered list of salons that are in the "Test Drive" pipeline stage, giving sales reps a focused view of active test drives.

### Layout
Plain list with a large "Test Drive" title. Optionally shows a notifications-disabled warning banner at the top when notifications are not allowed.

**Each row displays:**
- Salon name (bold headline)
- Deadline date with calendar-clock icon (color coded: red if overdue or due today, orange if 1 day away, secondary otherwise)
- Article line (comma-separated product codes from the test-drive note)
- Comment text (optional, second line of note, 1-line truncated)
- City (secondary text)

**Notifications Disabled Banner** (shown when notifications are not allowed):
- Warning triangle icon (orange)
- Title and body explaining notifications are disabled
- "Settings" button — opens device Settings app

### Data displayed
- A list of salon cards in test-drive status with deadline dates, article codes, comments, and city.
- Notification warning banner when notifications are disabled.

### User actions
- **Tap a row** → navigates to the Salon Detail screen for that salon.
- **"Settings" button** in banner → opens OS device settings.

### Business rules
- The salon list is passed in from the parent Salons List; no additional API call is made.
- Deadline coloring: red if overdue or due today, orange if 1 day away, secondary otherwise.

### API / Data sources
None (data comes from the parent Salons List).

### Navigation
- Tap salon row → Salon Detail

### Empty / Loading states
- Loading: spinner centered in the list.
- Empty: empty state view with a flask icon and "No active test drives" text.

---

## Screen: Route Planner

### Purpose
Displays an ordered list of salons to help a sales rep plan and navigate their visiting route for the day, with route optimization and turn-by-turn navigation support.

### Layout
This is a two-phase screen. Phase 1 is salon selection; Phase 2 is the optimized route map.

---

**Phase 1 — Selection:**

The content area shows either a list or a map (togglable via toolbar). A bottom bar is always visible.

**List Mode:** Plain scrollable list of available salons. Each row shows:
- Checkmark circle icon (filled = selected, empty = not selected)
- Salon name
- Address (secondary, 1 line)
- Status badge (right side)

**Map Mode:** Full-screen map with user location shown and salon pins. Each pin is a circle:
- Gray circle with a small status-colored dot = not selected
- Accent-colored circle with a checkmark = selected

**Bottom bar:**
- Selected count text ("X selected")
- "Deselect All" button (only visible when at least one is selected)
- "Build Route" button — disabled until at least 2 salons are selected; triggers route calculation

---

**Phase 2 — Route Map:**

Full-screen interactive map with a frosted glass bottom panel.

**Map content:**
- User location (blue dot)
- Numbered colored pins for each stop (1-based, color = salon status color)
- Blue polyline (driving) or orange polyline (walking) connecting the stops in order

**Bottom panel (from top to bottom):**
1. Transport type picker — segmented control: Driving (car icon) / Walking (person icon)
2. Stats row (3 badges): Distance, Estimated Time, Number of Stops
3. Progress bar (visible while calculating the route)
4. Horizontally scrollable stop chips: each chip shows the stop number, salon name, and an X button to remove the stop
5. "Navigate" button — opens Apple Maps with the full multi-stop route

### Data displayed
- Phase 1: list of salons with selection state; selection count.
- Phase 2: numbered pins on map, route polyline, transport type, stats (distance, time, stops count), stop chips.

### User actions

**Phase 1:**
- **Toolbar left**: map/list toggle.
- **Toolbar right**: close (X) button — dismisses the screen.
- **Tap a row or a map pin** — toggles that salon's selection.
- **"Deselect All"** — clears all selections.
- **"Build Route"** — starts route optimization and moves to Phase 2.

**Phase 2:**
- **Toolbar left**: back arrow — returns to Phase 1.
- **Toolbar right**: close (X) button.
- **Transport type picker** — switches between driving and walking; triggers route recalculation.
- **Remove stop (X on chip)** — removes that stop and recalculates.
- **"Navigate" button** — launches Apple Maps (disabled if fewer than 2 stops).
- Map controls: user location button, compass, scale.

### Business rules
- "Build Route" button is disabled until at least 2 salons are selected.
- Route Planner is only accessible from Salons List when at least 2 salons have map coordinates.
- Removing a stop chip recalculates the route.
- If the route cannot be built, an alert is shown.

### API / Data sources
None (salon data is passed in from the parent Salons List; route is calculated on-device).

### Navigation
None from Phase 2; back in Phase 2 returns to Phase 1; close dismisses the screen.

### Empty / Loading states
- Phase 2: progress bar shown while route is calculating.
- Alert shown if the route cannot be built (e.g. not enough stops with coordinates).

---

# Domain: Sales

---

## Screen: Sales Dashboard

### Purpose
Provides a financial overview of all issued invoices from the FlexiBee accounting system, with both a searchable invoice list and an analytics dashboard showing revenue, top clients, and top products for a selected period.

### Layout
This screen is pushed from the Profile screen and has no traditional navigation title bar. The content uses an internal two sub-tab layout (not the main tab bar):
- **Analytics** tab (bar chart icon)
- **Invoices** tab (document icon)

---

**Analytics Sub-tab — Layout (scrollable vertical content, grouped background):**

Components in order, top to bottom:
1. Sync status row — sync icon + last sync date/time (or spinner if loading)
2. Period picker — segmented control: Month / Year
3. Period navigator — left chevron button — period label — right chevron button (disabled when at the current period)
4. KPI cards (2-column grid, when data is available):
   - Total Revenue (blue banknote icon)
   - Paid Revenue (green checkmark circle icon)
   - Unpaid Revenue (orange clock icon)
   - Overdue Count (red exclamation icon when > 0, gray otherwise)
5. Monthly Revenue Chart — vertical bar chart with month labels on X-axis and revenue on Y-axis
6. Top Clients card:
   - Header: "Top Clients" + "See All" link (if more than 5 exist)
   - Up to 5 rows: rank number, client name, revenue amount, chevron; each row is tappable → Client Detail
7. Top Products card:
   - Header: "Top Products" + "See All" link (if more than 7 exist)
   - Up to 5 rows (starting from rank 3): rank, product name, product code, quantity sold
   - Note text: "Shown from position 3"

---

**Invoices Sub-tab — Layout:**

List with a floating action button (FAB) in the bottom-right corner. A search bar is shown (activates on scroll or tap). Filter chips are pinned in a horizontal scroll row below the sync status.

Components:
1. Sync status row
2. Status filter chips (horizontal scroll): All, Paid, Unpaid, Overdue (colored capsules; tap to toggle; only one active at a time)
3. Invoice list rows

Each invoice row shows:
- Invoice number (bold)
- Payment method icon (right of number, secondary)
- Payment status badge (right side)
- Client name (below number, secondary, 1 line)
- Issue date (left, secondary caption)
- Total amount in CZK (right, bold)
- Disclosure chevron

FAB (floating action button): circular accent-colored button with a pencil/square icon, bottom-right corner. Tapping opens the Create Invoice sheet.

### Data displayed

*Invoice List tab:*
- Searchable, filterable list of all invoices.
- Payment status filter chips.
- Last sync timestamp.
- Pull-to-refresh control.

*Analytics tab:*
- Period selector: Month or Year, with back/forward navigation arrows.
- Period label (e.g. "May 2026" or "2026").
- Total revenue for the period.
- Paid, unpaid, and overdue sub-totals.
- Overdue count.
- Bar chart of monthly revenue within the period.
- Top Clients list (up to 5, ranked by revenue) with "See All" button.
- Top Products list (up to 5 starting at rank 3, ranked by quantity sold) with "See All" button.

### User actions
- Switch between Invoice List and Analytics tabs.
- **Search bar** — filters invoices by invoice number or client name.
- **Status filter chips** — filter by payment status (single selection).
- **Pull to refresh** — forces a full sync from FlexiBee.
- **Period picker** (Analytics) — switch between monthly and yearly view.
- **Left/right chevron buttons** (Analytics) — navigate to previous/next period (right disabled at current period).
- **Tap a client row** (Analytics, Top Clients) — navigates to Client Detail.
- **"See All" on Top Clients** → navigates to All Top Clients screen.
- **"See All" on Top Products** → navigates to All Top Products screen.
- **Tap an invoice row** → opens Invoice Detail.
- **FAB (+ button)** → opens Invoice Create form.

### Business rules
- On first load, data is read from the local FlexiBee cache immediately, then a conditional network sync runs in the background if the cache is stale.
- All filtering, searching, and analytics computations are done client-side; no additional API calls are made for filter changes.
- Forward navigation in the period picker is blocked at the current calendar period.
- After a new invoice is created, a force-sync runs and the app automatically opens the newly created invoice's detail screen.
- Navigation to Invoice Detail, Client Detail, All Top Clients, and All Top Products is handled by the parent Profile screen's navigation stack.

### API / Data sources
- FlexiBee — `loadIfNeeded()` — conditional network sync on first load.
- FlexiBee — `forceSync()` — full refresh on pull-to-refresh or after invoice creation.
- FlexiBee local cache — `invoices()`, `salesMovementItems()`, `stockWithPrices()` — synchronous reads.

### Navigation
- Tap invoice row → Invoice Detail (pushed by parent)
- Tap client name (Analytics) → Client Detail (pushed by parent)
- Tap "See All" Top Clients → All Top Clients (pushed by parent)
- Tap "See All" Top Products → All Top Products (pushed by parent)
- FAB → Invoice Create Form (modal sheet)

### Empty / Loading states
- Analytics: when no data exists for the selected period — "No Data" empty state with a bar chart icon.
- Invoices: when the filtered list is empty — "No Invoices" empty state with a document icon.
- Initial load: full-screen frosted spinner overlay.
- Syncing: spinner in sync status row.

---

## Screen: All Top Clients

### Purpose
A full searchable ranked list of clients by total invoice revenue, expanding the "Top Clients" preview shown on the Sales Dashboard.

### Layout
Plain list with an inline "Top Clients" title and a search bar.

Each row shows:
- Rank number (secondary)
- Client name (up to 2 lines)
- Revenue amount in CZK (bold, right)
- Disclosure chevron

### Data displayed
A list of clients sorted by total revenue (descending), each showing rank, client name, and total revenue.

### User actions
- **Search bar** — filters by client name in real time.
- **Tap a row** → navigates to Client Detail.

### Business rules
- The list is computed from the invoice data already loaded; no additional API call is made.
- Search is client-side only.

### API / Data sources
None (data is passed in from parent).

### Navigation
- Tap client → Client Detail (pushed by parent)

### Empty / Loading states
When filtered list is empty: "No Data" empty state with a persons icon.

---

## Screen: All Top Products

### Purpose
A full searchable ranked list of products by total quantity issued from stock (from warehouse movement records), expanding the "Top Products" preview shown on the Sales Dashboard.

### Layout
Plain list with an inline "Top Products" title and a search bar.

Each row shows:
- Rank number (secondary)
- Product name (up to 2 lines)
- Product code (secondary, small)
- Quantity sold (bold, right)
- Disclosure chevron

### Data displayed
A list of products sorted by total quantity issued (descending), each showing rank, product name, article code, and total quantity.

### User actions
- **Search bar** — filters by product name or article code in real time.
- **Tap a row** → navigates to Product Detail.

### Business rules
- The list is computed from stock movement data already loaded; no additional API call is made.
- Search is client-side only.

### API / Data sources
None (data is passed in from parent).

### Navigation
- Tap product → Product Detail (pushed by parent)

### Empty / Loading states
When filtered list is empty: "No Data" empty state with a shipping box icon.

---

## Screen: Invoice Detail

### Purpose
Shows all details of a single issued invoice, and allows managing its payment status, linking a warehouse stock movement, marking it as accounted, sharing PDFs, and deleting it.

### Layout
Grouped list with an inline title (invoice number). An edit button appears in the top-right toolbar for editable invoices (unpaid only). A bottom toolbar bar contains action buttons.

**Sections in order:**
1. **Timeline** — horizontal step indicator with 4 stages (Created → Accounted → Stock Moved → Paid), each step and connecting line animates from gray to green when completed.
2. **Header** — invoice number + client name (tappable, blue) + total + status + payment method icon.
3. **Dates** — issue date and due date (due date shown in red if overdue).
4. **Notes** — shown only if non-empty.
5. **Line Items** — collapsible disclosure group; header shows "ITEMS" and total amount; when expanded shows product name, product code, quantity, line total, and chevron for navigating to Product Detail.
6. **Stock Movement** — collapsible disclosure group (visible only when movement items exist); header shows "STOCK MOVEMENT" and an "Edit" link button.

**Bottom Toolbar:**
- Left: Trash icon (red) — triggers delete confirmation alert.
- Right: Checkmark seal icon (mark as accounted, only if not yet accounted); Shipping box icon (create stock movement, only if not yet created and not yet paid); Green checkmark circle icon (mark as paid, only if not yet paid); Document icon (share PDF).

### Data displayed
- Invoice number, issue date, due date.
- Client name (tappable → Client Detail).
- Total amount.
- Payment status badge.
- Payment method icon.
- "Accounted" indicator (timeline step).
- Line items list: product name, product code, quantity, line total.
- Linked stock movement (if one exists): movement items.
- Notes / final text.
- Timeline progress (4 steps).

### User actions
- **Edit button (toolbar)** — opens Invoice Form to edit (only available when invoice is not paid).
- **Tap client name** → opens Client Detail.
- **Tap a product** in line items → opens Product Detail.
- **"Edit" link** in stock movement header → opens Stock Movement sheet.
- **Trash icon** — shows a delete confirmation alert.
- Confirm delete → deletes the linked stock movement (if any) then deletes the invoice; the screen closes and the parent list refreshes.
- **Accounting button** (seal icon) — marks the invoice as accounted in FlexiBee.
- **Stock movement button** (shipping box icon, shown when no movement linked yet) → opens the Stock Movement form.
- **Pay button** (green checkmark icon, shown when not yet paid) → opens a Payment Method Picker sheet.
- **PDF/document button** — downloads the invoice PDF from FlexiBee and opens the system share sheet. If payment method is cash and a cash receipt exists, shares both invoice PDF and receipt PDF.
- **Disclosure groups** — tap to expand/collapse.

### Business rules
- On load, three resources are fetched in parallel: invoice line items, linked stock movement, and cash receipt ID.
- Edit is only available when payment status is not "Paid".
- Only unpaid invoices can be edited.
- When paying by cash (hotove), a cash receipt document is automatically created in FlexiBee.
- After a payment status change, the invoice is re-fetched from FlexiBee to display the updated data.
- After marking as accounted, the invoice is re-fetched.
- After an edit is submitted, the invoice is re-fetched and line items are reloaded.
- Deletion is sequential: the stock movement is deleted first, then the invoice. After deletion, the parent navigates back and forces a FlexiBee sync.

### API / Data sources
- FlexiBee — `fetchLineItemsForInvoice(id)` — read on load.
- FlexiBee — `fetchStockMovement(invoiceNumber)` — read on load.
- FlexiBee — `fetchCashReceiptId(invoiceId)` — read on load.
- FlexiBee — `fetchSingleInvoice(id)` — read after edit, status change, or accounting toggle.
- FlexiBee — `updateInvoicePaymentStatus(id, status, method)` — write on status change.
- FlexiBee — `createCashReceipt(invoice)` — write when paying by cash.
- FlexiBee — `markAsAccounted(id)` — write on accounting tap.
- FlexiBee — `deleteStockMovement(invoiceNumber)` + `deleteInvoice(id)` — sequential writes on delete.
- FlexiBee — `fetchPDF(path)` — binary download for PDF sharing.

### Navigation
- Tap client name → Client Detail (pushed by parent)
- Tap product in line items → Product Detail (pushed by parent)
- Edit button → Invoice Edit Form (modal sheet)
- "Edit" link in stock movement → Stock Movement Form (modal sheet)
- Shipping box icon → Stock Movement Form (modal sheet)
- Pay button → Payment Method Picker (partial/bottom sheet)
- Delete confirmed → pops back to previous screen

### Empty / Loading states
- PDF loading: the document icon is replaced by a spinner.
- Line items loading: a spinner row inside the disclosure group.

---

## Sheet: Payment Method Picker

### Purpose
A bottom sheet for selecting the payment method when marking an invoice as paid.

### Layout
Bottom sheet at approximately 35% of screen height.

### Data displayed
- "Payment Method" title.
- One row per payment method (e.g. Cash, Bank Transfer, Card), each with an icon and name.
- The currently selected method has a checkmark on the right.
- Cancel button at the bottom.

### User actions
- **Tap a payment method row** — confirms the payment status change with that method and closes the sheet.
- **Cancel button** — dismisses without action.

### Business rules
- When cash (hotove) is selected, a cash receipt document is automatically created in FlexiBee.

### API / Data sources
- FlexiBee — `updateInvoicePaymentStatus(id, status, method)` — write on selection.
- FlexiBee — `createCashReceipt(invoice)` — write when cash is selected.

### Navigation
None; closes on selection or cancel.

### Empty / Loading states
None.

---

## Screen: Invoice Create / Edit Form

### Purpose
A form for creating a new invoice or editing an existing (unpaid) invoice in FlexiBee.

### Layout
Full-height modal sheet with an inline title ("Create Invoice" or "Edit Invoice"). Contains a scrollable form. Close (X) button on the left, checkmark (or spinner) on the right.

**Sections:**
1. **Client** — a tappable row showing the selected client name, or a placeholder. Tap opens the Client Picker sheet.
2. **Dates** — issue date picker (date only); due date picker (date only).
3. **Items** (section header shows "ITEMS" on the left and grand total on the right when > 0): editable line item rows; swipe left on a row to delete it; **Add Item** menu button (plus icon) with options: "From Stock" (opens Product Picker), "Scan Barcode" (opens camera scanner), "Manual Entry" (adds a free-text item row).
4. **Notes** — multi-line text field (3–6 lines).
5. **Error section** (shown if submission fails): red warning icon + error text.

**Each line item row (stock items):**
- Product name (non-editable label)
- Product code below name (small, secondary)

**Each line item row (free-text "other" items):**
- Editable product name text field

**All items additionally show:**
- Quantity: minus button — editable number field — plus button
- Price: editable price field + "Kč" label
- Line total (right, bold, shown when > 0)

### Data displayed
- Client picker (pre-selected if opened from a client context).
- Issue date and due date pickers.
- Payment method selector.
- Notes field.
- Line items list (product name, quantity, unit price, line total).
- Add line item controls.

### User actions
- **Client row** — opens Client Picker sheet.
- **Date pickers** — select dates.
- **Quantity minus/plus buttons** — decrement/increment quantity.
- **Quantity text field** — directly edit quantity (decimal allowed).
- **Price text field** — directly edit unit price (decimal allowed).
- **Swipe left on item row** — delete that item.
- **Add Item menu** — choose "From Stock", "Scan Barcode", or "Manual Entry".
- **Barcode scanner** — full-screen camera; on scan, looks up product in price list.
- **Checkmark** → creates or updates the invoice in FlexiBee; the parent screens refresh.
- **Close (X)** → closes the form without saving; the parent forces a FlexiBee sync to pick up any partial server-side saves.

### Business rules
- Only unpaid invoices can be edited.
- At least one valid line item is required to submit.
- After successful submission, the parent Sales Dashboard forces a full sync and then opens the new invoice's detail screen.

### API / Data sources
- FlexiBee — invoice create/update API endpoints.

### Navigation
- Client row → Client Picker sheet
- "From Stock" → Product Picker sheet
- "Scan Barcode" → Barcode Scanner (full-screen cover)

### Empty / Loading states
- Items/firms loading: frosted overlay with spinner + "Loading…" or "Searching…" text.
- Barcode not found: alert with error message.

---

## Sheet: Client Picker (Firm Picker)

### Purpose
A searchable list for selecting a client/firm when creating or editing an invoice.

### Layout
Full-height modal sheet with a search bar. Shows a plain list of clients/firms.

**Each row shows:**
- Client name (primary)
- Client code (secondary, small)
- Checkmark (if currently selected)

**Toolbar:**
- Close (X icon) on the left.
- "New Client" (person-plus icon) on the right — opens Create Client sheet (shown for users with create permission).

### Data displayed
List of all clients/firms with name, code, and current selection indicator.

### User actions
- **Search bar** — filters by name or code.
- **Tap a row** — selects that client and closes the picker.
- **Swipe left on a row** (admins only) — delete client (with confirmation); error alert if fails.
- **New Client icon** — opens Create Client sheet.

### Business rules
- Filtering is client-side.
- Only admins can delete clients via swipe.

### API / Data sources
- FlexiBee — firms/address book list (loaded from cache or API).

### Navigation
- New Client icon → Create Client sheet

### Empty / Loading states
Loading (no firms yet): full-size centered spinner.

---

## Sheet: Create Client

### Purpose
Allows creating a new client/firm directly from within the invoice form flow. On success, the newly created client is automatically selected in the invoice form.

### Layout
Full-height modal sheet with a form. Same fields as Edit Client: company name, IČO, DIČ, email, phone.

### Data displayed (form fields)
- Company name (required, with building icon)
- Tax ID / IČO (numeric)
- VAT number / DIČ
- Email
- Phone

### User actions
- Edit any field.
- **Checkmark** → saves to FlexiBee; newly created client is auto-selected in invoice form.
- **Close (X)** → dismisses without saving.

### Business rules
- Submit is disabled when the Name field is empty.

### API / Data sources
- FlexiBee — `createFirm` — write on submit.

### Navigation
None; closes on submit or dismiss.

### Empty / Loading states
Frosted spinner while submitting. Error alert if submission fails.

---

## Sheet: Product Picker

### Purpose
A searchable list for selecting a product from the price list when adding a line item to an invoice.

### Layout
Full-height modal sheet with a search bar and a plain list.

**Each row shows:**
- Product name
- Product code (secondary, small)
- Sell price in CZK (right, bold, secondary) — only shown when > 0

### Data displayed
List of products from the FlexiBee price list with name, code, and sell price.

### User actions
- **Search bar** — filters by name or code.
- **Tap a row** — selects that product, fills it into the line item, and closes the picker.
- **Close (X icon)** — dismisses without selecting.

### Business rules
- Data comes from the local FlexiBee stock/price list cache.

### API / Data sources
- FlexiBee local cache — `stockWithPrices()`.

### Navigation
None; closes on selection or dismiss.

### Empty / Loading states
None specific.

---

## Screen: Stock Movement Form

### Purpose
Creates a warehouse outflow document in FlexiBee linked to a specific invoice, recording which products were physically issued from stock.

### Layout
Full-height modal sheet with a form and an inline title "Stock Movement – [Invoice Number]".

**Content is divided into:**
- **Bundle sections** (one per bundle/set in the invoice line items): each section has a labeled header with an orange box icon and the bundle name; components inside are editable rows.
- **Regular items section** (labeled "Items"): editable rows for standard line items.

**Each movement item row shows:**
- Product name (or placeholder text if empty)
- Product code below (secondary, small)
- A "pick product" button (text-plus icon) on the right — opens the Product Picker sheet
- Quantity field (editable, decimal)

Swipe left on a row — deletes that item.

"Add Item" button at the bottom of each section — adds a blank row and immediately opens the Product Picker.

**Toolbar:**
- Close (X) button on the left — skips/cancels the movement without saving.
- Spinner or Checkmark button on the right — submits; disabled if form is invalid.

**Error section**: shown at the bottom of the form if submission fails.

### Data displayed
- Invoice number and line items pre-filled from the parent invoice.
- Quantity fields per line item (editable).

### User actions
- Adjust quantities.
- Tap "pick product" button on a row → opens Product Picker.
- "Add Item" → adds blank row and opens Product Picker.
- Swipe left on a row → removes that item.
- **Checkmark** → creates the stock movement in FlexiBee.
- **Close (X)** → closes the form without creating a movement.

### Business rules
- The form is pre-filled with the invoice's line items as a starting point.
- After submission, the parent Invoice Detail reloads to display the newly linked movement.

### API / Data sources
- FlexiBee — stock movement create API.

### Navigation
- "Pick product" button → Product Picker sheet

### Empty / Loading states
Frosted spinner while submitting. Error section shown if submission fails.

---

## Screen: Client Detail

### Purpose
Shows a summary of a single client's invoicing history and allows creating new invoices for them or editing their contact details in FlexiBee.

### Layout
Grouped list with an inline title (client name). An edit button (pencil-square icon) appears in the top-right toolbar. A floating circular plus button in the bottom-right creates a new invoice for this client.

**Sections:**

**Header Section (no border/background):**
- Client name (large bold)
- Tax ID (IČO): "IČO: 12345678"
- VAT ID (DIČ): "DIČ: CZ12345678"
- Stats row: invoice count (document icon), first order date (clock-arrow icon), last order date (clock-checkmark icon)

**Stats Section (2-column KPI cards):**
- Total Revenue (blue)
- Paid Revenue (green)
- Unpaid Revenue (orange)
- Overdue amount or "—" (red if > 0, gray otherwise)

**Invoices Section:** section header "Invoices". List of all invoices for this client, each as a standard invoice row (same as in Invoices sub-tab). Sorted descending by date.

### Data displayed
- Client name.
- Tax ID (IČ) and VAT number (DIČ), loaded from FlexiBee address book.
- Summary stats: lifetime revenue, paid revenue, unpaid revenue, overdue revenue, overdue count.
- First and last order dates.
- Invoice count.
- Invoice list sorted newest-first.
- A Create Invoice button (FAB, shown to users with `canEdit` permission).
- An Edit Client button (shown to users with `canEditClient` permission).

### User actions
- **Edit icon (toolbar)** → opens Edit Client sheet.
- **FAB (+ button)** → opens Create Invoice sheet, pre-selecting this client.
- **Tap an invoice row** → navigates to Invoice Detail.
- After dismissing the invoice create form, the invoice list refreshes from cache.

### Business rules
- On load, the app fetches the client's address-book record from FlexiBee to obtain IČ and DIČ.
- All revenue stats are computed from the invoices passed in — no additional API call.
- The invoice list uses cached invoices; after creating an invoice and dismissing the form, the list is refreshed from cache automatically.

### API / Data sources
- FlexiBee — `fetchFirm(clientCode)` — read on load and before opening the edit form.
- FlexiBee local cache — `invoices()` — synchronous read after invoice form dismissal.

### Navigation
- Tap invoice row → Invoice Detail (pushed by parent)
- FAB → Invoice Create Form (modal sheet)
- Edit icon → Client Edit Form (modal sheet)

### Empty / Loading states
Empty invoices section: "No invoices" text in secondary color.

---

## Sheet: Edit Client

### Purpose
Lets authorised users edit a client's name, tax ID, VAT number, email, and phone number in the FlexiBee address book.

### Layout
Full-height modal sheet with a form.

**Sections:**
1. Company name field (with building icon) — required.
2. Tax identifiers: IČO field (numeric), DIČ field.
3. Contact: email field, phone field.

An error message row appears below all sections if submission fails.

### Data displayed (form fields)
- Name (required)
- IČ (tax ID)
- DIČ (VAT number)
- Email
- Phone

### User actions
- Edit any field.
- **Checkmark** → saves to FlexiBee and closes the form; the parent Client Detail updates its local state.
- **Close (X icon)** → dismisses without saving.

### Business rules
- Submit is disabled when the Name field is empty or while submitting (button replaced by spinner).
- The form is pre-filled with data fetched from FlexiBee before the form opens.

### API / Data sources
- FlexiBee — `updateFirm(code, firm)` — write on submit.

### Navigation
None; the form closes on submit or dismiss.

### Empty / Loading states
Spinner replaces the checkmark button while submitting. Error message row shown on failure.

---

## Screen: Product Detail

### Purpose
Shows detailed stock and pricing information for a single product from the FlexiBee price list.

### Layout
Grouped list with an inline title (product code). Two sections.

**Section 1 — Header card:** A rounded card containing product code (bold caption, secondary) and product name (large, semibold). Long-press context menu: "Copy Article", "Copy Name", "Copy Article and Name".

**Section 2 — Details:**
- In-Stock row: label + quantity badge (color-coded red/orange/green)
- Sell Price row: label + price in CZK (only shown if price > 0)
- Purchase Price row: label + price (only shown when details are expanded)
- Toggle button: "Show details" / "Hide details" — reveals or hides the purchase price

### Data displayed
- Product name and article code.
- Product line / brand.
- Current stock quantity.
- Retail sell price (inc. VAT).
- Purchase price (hidden by default; toggle to reveal — visible to admins/managers only).

### User actions
- **Long-press on header card** → context menu to copy article code, product name, or both.
- **"Show details" / "Hide details" toggle button** → reveals or hides the purchase price row.

### Business rules
- All data is loaded from the local FlexiBee cache; no network call is made when opening this screen.
- This screen is reachable from Invoice Detail (tap a line item), Top Products list, and the Stock tab.
- The purchase price toggle is visible but access may be restricted to admins/managers.

### API / Data sources
None (data comes from the local FlexiBee cache).

### Navigation
None — this is a leaf screen.

### Empty / Loading states
None — data is passed directly when navigating here.

---

# Domain: Stock

---

## Screen: Stock Tab

### Purpose
Gives sales reps a live view of all warehouse inventory grouped by product line, with search, sort, barcode scanning, a stock checklist tool, and a PDF catalog viewer.

### Layout
Navigation screen with a large "Stock" title and a search bar. The list has a stats header and then either grouped sections (by product line) or a flat list depending on the sort option.

**Stats header (3 compact cards in a row):**
- SKU count (blue shipping box icon)
- Total units (green number circle icon)
- Low stock count (orange warning triangle; red tint when count > 0)

Below the cards: sync status row (last sync date and time, or spinner).

**List content:**
- When sorted by section: each product line is a collapsible section with a frosted glass capsule header showing "Line Name (count)". Tapping the header collapses/expands it.
- When sorted by name or quantity: a flat list of all items.

**Each stock item row shows:**
- Product code (bold caption, secondary)
- Product name (up to 2 lines)
- Volume/size badge (capsule, if available)
- Quantity badge (right side, color-coded: red = 0, orange = 1–2, green = 3+)
- Sell price (caption below quantity badge)
- Disclosure chevron

**Toolbar items:**
- Left side — sort menu (up-down arrows icon): choose to sort by Section, Name, or Quantity. When "Quantity" is selected, a sub-menu appears for ascending or descending.
- Left side — barcode scanner icon: opens the Barcode Scanner sheet.
- Left side — checklist icon: opens the Stock Checklist sheet.
- Right side — collapse/expand all icon (only when sorted by section): toggles all sections open or closed.
- Right side — catalog icon (book icon): navigates to the Catalog screen.

**Floating scroll-to-top button:** A blue circle with an up arrow appears in the bottom-right corner when the user has scrolled down past the first screen. Tapping scrolls back to the top.

### Data displayed
- Total stock units and a "low stock" count (items with 2 or fewer units).
- A search field.
- Sort controls: by Section/Name or by Quantity (ascending/descending).
- A grouped list of stock items, organised by product line. Each group is collapsible.
- Each item row: product name, article code, quantity, sell price, volume badge.
- Last sync timestamp.
- Collapse All / Expand All controls.

### User actions
- **Search bar** — filters by product name, article code, or product line in real time.
- **Sort menu** — select sort by Section, Name, or Quantity (with direction sub-option).
- **Tap a section header** — collapses or expands that section.
- **Collapse All / Expand All** icon (right toolbar, when sorted by section) — toggles all sections.
- **Pull to refresh** — forces a full sync from FlexiBee.
- **Tap a product row** → opens Product Detail.
- **Barcode scanner icon** → opens Barcode Scanner sheet; on successful scan, opens Product Detail.
- **Checklist icon** → opens Stock Checklist sheet.
- **Catalog icon** → navigates to PDF Catalog Viewer.
- **Scroll-to-top button** — scrolls to top.

### Business rules
- On first load, data is read from the local FlexiBee cache, then a conditional sync runs in the background.
- All filtering, sorting, and grouping are done client-side.
- Barcode scanning looks up the scanned EAN/QR code in Firebase to find the matching FlexiBee article code, then locates the product in the local stock list.
- If a barcode is not found in Firebase or does not match any stock item, no navigation occurs (silent failure; an alert is shown for errors).
- Items with 2 or fewer units are counted as "low stock" but are not filtered out or highlighted specially beyond the count.

### API / Data sources
- FlexiBee — `loadIfNeeded()` — conditional background sync on load.
- FlexiBee — `forceSync()` — full refresh on pull-to-refresh.
- Firebase — `lookupBarcodeArticle(barcode)` — read when a barcode is scanned.

### Navigation
- Tap product row → Product Detail (pushed onto stack)
- Barcode scanner icon → Barcode Scanner sheet (modal); on successful scan, opens Product Detail
- Checklist icon → Stock Checklist sheet (modal)
- Catalog icon → PDF Catalog Viewer (pushed onto stack)

### Empty / Loading states
- Initial load (empty list): full-screen frosted spinner overlay.
- Empty after load: empty state icon with "No stock data" text.
- Error scanning barcode: alert with error message.

---

## Sheet: Barcode Scanner

### Purpose
A full-screen camera view for scanning a product barcode to find and navigate to a stock item.

### Layout
Full-screen camera view. A dismiss button closes the scanner. On successful scan, the app looks up the product and navigates to its Product Detail screen. On error, an alert is shown.

### Data displayed
Camera viewfinder. Feedback on scan result.

### User actions
- **Scan a barcode** — app looks up the product in the stock list and navigates to Product Detail.
- **Dismiss button** — closes the scanner.

### Business rules
- Barcode lookup goes through Firebase (`lookupBarcodeArticle`) to map EAN to FlexiBee article code.
- If not found, an error alert is shown.

### API / Data sources
- Firebase — `lookupBarcodeArticle(barcode)` — read on each barcode scan.

### Navigation
- On successful scan → Product Detail

### Empty / Loading states
Error alert when barcode is not found.

---

## Sheet: Stock Checklist

### Purpose
An ad-hoc stock-count tool. Sales reps can scan barcodes to build a list of products with quantities, then export the result as a JSON payload for import into an external system.

### Layout
Full-height modal sheet with an inline "Barcode" title and a list of scanned items.

**Each row shows:**
- Product name
- Product code (secondary, small)
- Quantity counter (center): minus button (red circle minus) — count — plus button (green circle plus)

**Toolbar:**
- "Close" button (left) — dismisses.
- Barcode scanner icon (right) — opens camera scanner.
- Bottom bar: total quantity count (shown when > 0).

### Data displayed
- A list of scanned items, each showing: product name, article code, and quantity with increment/decrement buttons.
- Total quantity across all items.
- Error alert when a scanned barcode is not recognised.

### User actions
- **Scanner icon** → opens the in-sheet barcode scanner.
- **Scan a barcode** → the app looks up the article in Firebase and adds it to the list (or increments its quantity if already present).
- **Plus (+) on an item** → increments quantity.
- **Minus (-) on an item** → decrements quantity (removes the item when it reaches zero).
- Export/copy the JSON payload.
- **Close** → dismisses the sheet.

### Business rules
- Items start empty; they can only be added by scanning.
- If the same barcode is scanned again, the quantity of the existing entry is incremented instead of creating a duplicate.
- If a barcode is not found in Firebase or does not match any stock item, an error alert is shown.
- The checklist starts with the FlexiBee stock cache warm (loaded in the background on open).
- Export format: JSON array `[{"article": "CODE", "quantity": N}, ...]`.

### API / Data sources
- FlexiBee — `loadIfNeeded()` — ensures the cache is populated on open.
- Firebase — `lookupBarcodeArticle(barcode)` — read on each barcode scan.

### Navigation
None; closing the sheet returns to the Stock tab.

### Empty / Loading states
- Empty: empty state icon + "No items scanned yet".
- Loading/searching: frosted overlay with spinner and "Searching…" text.
- Scan error: alert with error message.

---

## Screen: PDF Catalog Viewer

### Purpose
Displays a bundled product catalog PDF file within the app and lets the user share it.

### Layout
Full-screen PDF viewer with the navigation title and a Share button in the toolbar.

### Data displayed
- The `catalog.pdf` file from the app bundle, rendered as a scrollable PDF document.
- A Share button in the toolbar.

### User actions
- Scroll through the catalog.
- Tap **Share** → opens the system share sheet with the PDF file.

### Business rules
- The PDF is loaded from the app bundle; no network call is made.
- If the PDF file is missing from the bundle, a "Catalog not available" placeholder is shown.

### API / Data sources
None.

### Navigation
None; back navigation returns to the Stock tab.

### Empty / Loading states
If the PDF file is missing: "Catalog not available" placeholder.

---

# Domain: Promos

---

## Screen: Promos Tab

### Purpose
Displays active promotional offers that sales reps can use during salon visits. Admin users can additionally manage (create, edit, enable/disable, delete) promos.

### Layout
Navigation screen with a large "Promos" title. A horizontally scrollable category filter chip bar is pinned at the bottom (inside a frosted glass panel). The main content is a list of promo rows.

**Each promo row shows:**
- Promo title (localized to the selected language, bold headline)
- Category badge (colored capsule, grayed out if disabled)
- Description preview (2 lines, secondary)
- Validity period string (tertiary text, shown only if dates are set)
- Disabled promos are shown at 45% opacity

**Toolbar items:**
- Left side: language picker (dropdown/menu) — English, Ukrainian, Russian; affects which language's content is shown in the list.
- Left side (managers/admins only): visibility toggle icon (eye/eye-slash) — toggles showing disabled promos.
- Right side (managers/admins only): plus (+) button — opens Promo Form to create a new promo.

**Bottom filter chips:** One chip per available category. Tapping toggles that category filter (multiple can be active at once).

### Data displayed
- A list of promo cards, each showing: title, description, category — all rendered in the selected display language.
- Category filter chips (only showing categories that have at least one promo in the current view).
- A language selector (English, Ukrainian, Russian).
- (Admin only) an "Active / Inactive" toggle to switch between viewing enabled and disabled promos.
- (Admin only) Edit / Delete / Enable / Disable controls on each promo card.

### User actions
- **Tap a language button** → switches the display language of all promo titles and descriptions.
- **Visibility toggle** (managers/admins only) — toggles between showing active and inactive/expired promos.
- **Tap a category chip** → filters to only promos in that category; tap again to clear.
- **Pull to refresh** → reloads promos.
- **Tap a row** → opens the Promo Detail sheet.
- **Plus (+)** (managers/admins only) → opens the Promo Create form.
- **Swipe left on a row** (managers/admins only): reveals Delete (red) and Edit (orange pencil) buttons.
- **Swipe right on a row** (managers/admins only): reveals enable/disable toggle button.
  - If currently enabled → immediately deactivates it in Firebase.
  - If currently disabled → opens Promo Detail with the activation date picker pre-opened.

### Business rules
- Non-admin users only see promos that are both enabled and within their active date window.
- Admin users can toggle between showing active promos and inactive/expired promos.
- On load, promos and category strings are fetched from Firebase concurrently.
- Deletion is optimistic: the promo is removed from the list immediately, then the Firebase delete runs in the background.
- When saving a promo from the form, the list is updated in place (new promo inserted at top; edited promo replaced).
- Category filter chips only show categories that are actually present in the current visible subset.

### API / Data sources
- Firebase — `fetchPromos()` and `fetchPromoCategories()` — concurrent reads on load.
- Firebase — `deactivatePromo(id)` — write on disable.
- Firebase — `deletePromo(id)` — write on delete confirmation.

### Navigation
- Tap promo row → Promo Detail sheet (modal)
- Plus (+) → Promo Create Form (modal sheet)
- Swipe left Edit → Promo Edit Form (modal sheet)
- Swipe right toggle on inactive promo → Promo Detail with date picker open (modal sheet)

### Empty / Loading states
If the displayed list is empty (no promos or all filtered out): empty state view with a tag icon and "No promos" message.

---

## Sheet: Promo Detail

### Purpose
Shows the full content of a single promotional offer. For admin users, also provides controls to enable or disable the promo.

### Layout
Full-height modal sheet with navigation bar. Scrollable content.

**Data shown:**
- Category badge (accent-colored capsule)
- "Active" badge (green) if the promo is currently active
- "Disabled" badge (gray) if the promo is disabled
- Description text (localized to the current language)
- **Validity period card** (shown only if dates are set):
  - "From" date on the left, arrow in the center, "Until" date on the right
  - Progress bar (filled proportionally based on elapsed time; accent = active, orange = upcoming, gray = expired)
  - Status text below the bar: "X days left", "Starts in X days", or "Expired"

**Toolbar items:**
- Close (X) button on the left
- (Managers/admins only) Eye/eye-slash button — toggles enabled/disabled; shows spinner while toggling
- (Managers/admins only) Pencil button — opens Promo Form to edit

### Data displayed
- Promo title and description in the currently selected display language.
- Category.
- Validity period (active from / to dates), if set.
- Active / inactive status badge.
- Validity progress bar with time remaining/elapsed text.
- (Admin only) Enable / Disable toggle button.
- (Admin only) Edit button.

### User actions
- **Close button** → dismisses.
- **Eye/eye-slash icon** (managers/admins only) — toggles enabled state; shows spinner while toggling.
  - If currently enabled → deactivates in Firebase immediately.
  - If currently disabled → shows an inline date picker for activation start and end dates.
- **Pencil icon** (managers/admins only) → navigates to the Promo Edit form (the parent replaces the detail sheet with the form without an extra dismissal).
- When date picker shown (activation flow): confirm activation dates → activates the promo in Firebase with the chosen dates.
- When date picker shown: dismiss the picker → returns to the detail view without activating.

### Business rules
- Only admins/managers with `canManagePromos` permission see the Edit and toggle buttons.
- After a successful enable/disable toggle, the updated promo data is reflected in the sheet and propagated back to the parent Promos list.
- The activation date picker defaults to the promo's existing dates if they exist, or today and +30 days.

### API / Data sources
- Firebase — `deactivatePromo(id)` — write on disable.
- Firebase — `activatePromo(id, validFrom, validTo)` — write on activation confirmation.

### Navigation
- Pencil icon causes the parent to swap the sheet destination to the Promo Edit form (not a push).
- Date Picker sheet (medium detent) when activating a promo that needs dates — has Start Date and End Date pickers, close and confirm buttons.

### Empty / Loading states
Spinner shown on eye icon while toggling.

---

## Sheet: Promo Create / Edit Form

### Purpose
Lets admin users create a new promotional offer or edit an existing one, with support for multilingual content (English, Ukrainian, Russian).

### Layout
Full-height modal sheet with a form.

**Sections:**
1. **English** — Title text field + Description multi-line text field
2. **Ukrainian (Українська)** — Title + Description
3. **Russian (Русский)** — Title + Description
4. **Category** — single-select picker (dropdown/wheel) from a list of available categories

Close (X) button on the left, Checkmark button on the right (disabled if no title in any language, or while saving).

### Data displayed (form fields)
- Title — English (required), Ukrainian (optional), Russian (optional)
- Description — English, Ukrainian, Russian (all optional)
- Category picker (single select from a fixed list of categories)

### User actions
- Fill in any title/description fields.
- Select a category.
- Tap **Checkmark** → saves to Firebase and closes the sheet; the parent list is updated.
- Tap **Close (X)** → closes without saving.

### Business rules
- Save requires the English title to contain at least one non-whitespace character.
- Language variants with empty titles are omitted from the saved document.
- When editing, existing values are pre-filled from the promo's current content map.
- New promos do not have a validity window set by default; enabling them happens separately via the toggle in the Promos list or Promo Detail.

### API / Data sources
- Firebase — `savePromo(promo)` — write on save (creates new document or updates existing one).

### Navigation
None; the sheet closes on save or dismiss.

### Empty / Loading states
Frosted spinner overlay while saving. Error alert if saving fails.

---

# Domain: Profile

---

## Screen: Profile

### Purpose
Shows the current user's performance KPIs for their active plan period, their plan history, and provides navigation to activity logs, sales, users, clients, and plan management (each gated by role).

### Layout
Navigation screen with a large "Profile" title. Grouped list with several sections. A logout button (door-with-arrow icon, red tint) is in the top-right toolbar. Pull to refresh reloads plan data.

**Sections in order:**

**User Card Section:** A row showing:
- Circular avatar with the user's initials (colored by role: red = admin, orange = manager, blue = sales)
- Full name (headline)
- Role label (caption, secondary)

**Progress Section** (shown only when the user has an active plan): A card containing:
- Target icon + plan period string (e.g. "1 May – 31 May 2026")
- "Ended" label if the plan is in the past
- "See All" link on the right — navigates to User Activity
- Circular progress rings (76 pt diameter each): Salons ring (blue when active, gray when past) showing achieved/target count; Test Drives ring (green when active, gray when past)
- Below the rings: stat chips for New Clients and Returning Clients (count + label, color-coded)

**Plan History Section** (shown only when history is non-empty): Section header "Plan History". Each row shows:
- Plan period string (bold subheadline)
- Stats row: salons achieved/target (building icon), test drives achieved/target (car icon)

**Navigation Rows Section** (shown only when the user has relevant permissions):
- **Sales** row (chart icon) — navigates to the Sales screen (admin/manager only, requires `canViewSales`)
- **Clients** row (person stack icon) — navigates to the All Top Clients screen (admin/manager only, requires `canViewSales`)
- **Users** row (two-persons icon) — navigates to the Users screen (admin only, requires `canViewUsers`)

### Data displayed
- User name and role badge with colored avatar.
- Active plan summary: period dates, progress rings for salon visits and test drives (computed from activity entries within the plan period), stat chips for new and returning clients.
- Plan history section: a list of completed past plan periods with their result counters.
- Navigation rows (shown based on role): Activity Log (always), Sales, Clients, Users, Plans.
- Logout button.

### User actions
- **Pull to refresh** → reloads plan data.
- **Logout button** (top-right, red door icon) → shows a confirmation dialog.
  - "Log Out" (destructive) / "Cancel" — confirm logout → signs out; app returns to Login screen.
- **"See All" button** (in progress section) → navigates to User Activity.
- **Sales row** → navigates to Sales Dashboard.
- **Clients row** → navigates to All Top Clients screen (pre-aggregated from cached invoices).
- **Users row** → navigates to Users List.

### Business rules
- On load, the app resolves permissions synchronously, then refreshes the current user from Firebase, fetches activity entries (only if an active plan exists), and always fetches plan history.
- KPIs computed locally:
  - **Salons in plan**: entries whose timestamp falls within the active plan period.
  - **Test drives in plan**: entries with `testDrive` status within the plan period.
  - **New clients in plan**: salons contacted for the first time during the plan period (not contacted before the plan started).
  - **Returning clients in plan**: salons that were contacted both before and during the plan period.
- The Clients navigation row reads from the local FlexiBee invoice cache — no network call is made at tap time.
- Navigation rows are hidden if the user lacks the required permission.

### API / Data sources
- Firebase Auth — `refreshCurrentUser` — called on load.
- Firebase — `fetchUserActivity(userId)` — called on load when an active plan exists.
- Firebase — `fetchPlanHistory(userId)` — always called on load.
- FlexiBee local cache — `invoices()` — synchronous read when navigating to Clients.

### Navigation
- "See All" → User Activity screen (pushed)
- Sales row → Sales Dashboard (pushed)
- Clients row → All Top Clients (pushed)
- Users row → Users List (pushed)
- Confirm logout → Login screen

### Empty / Loading states
No special loading state shown on the profile screen itself; data loads in the background.

---

## Screen: User Activity

### Purpose
Shows a filterable timeline of all status-history entries recorded by a specific user, with per-status counts and daily or custom-range grouping.

### Layout
Scrollable screen with the user's full name as the large navigation title. A targets (bullseye) icon button in the top-right toolbar navigates to the Plans screen.

**Date Controls** — a card at the top with:
- Segmented picker: "Day" / "Custom Range"
- When "Day" is selected: single date picker (date only, up to today)
- When "Custom Range" is selected: two date pickers side by side — "From" and "To" (with range constraints)

**Stats Chips** — horizontally scrollable row of chips, one per status that has at least one entry in the selected period. Each chip shows the count (large, status-colored) and the status name below.

**Activity Entries (grouped by day):**
- Day header label: "Today", "Yesterday", or weekday + date (e.g. "Monday, 15 May")
- **Route map** (if 2+ entries have coordinates): a non-interactive 200-pt map showing numbered colored pins connected by a blue polyline, numbered in chronological order.
- Activity entry cards (one per status update):
  - Colored left border (status color)
  - Salon name (bold)
  - Time (right-aligned, tertiary)
  - Status badge (colored capsule)
  - Note text (up to 2 lines, if present)
  - Long-press: context menu with "Delete" option (for admins only)

### Data displayed
- User name and role.
- A date mode toggle: single-day vs. custom date range.
- A date picker (single day selector or start/end date pickers for custom range).
- Per-status count chips for the selected period.
- A chronologically grouped list of entries (salon name, status badge, timestamp, optional note).
- Route maps for days with 2+ geolocated entries.
- A "Go to Plans" link (bullseye toolbar icon).

### User actions
- **Segmented picker** — switch between "Day" and "Custom Range" date modes.
- **Date pickers** — select the date or date range.
- **Bullseye icon (toolbar)** → navigates to Plans List.
- **Long-press on an activity card** (admins only) — shows "Delete" in a context menu; confirmation, then deletes the entry.

### Business rules
- All filtering is done client-side after the full entry list is loaded.
- The default view shows the current day.
- Custom range defaults to the last 7 days.
- Delete permission is controlled by `canDeleteActivity`.
- Entries are sorted newest-first. Grouping by day is computed on the fly.
- "Go to Plans" is a navigation hook handled by the parent screen (Profile or Users).

### API / Data sources
- Firebase — `fetchUserActivity(userId)` — called once on load.
- Firebase — `deleteActivityEntry(entry)` — called on deletion confirmation.

### Navigation
- Bullseye icon → Plans List (navigation handled by parent)

### Empty / Loading states
- Loading: full-screen centered spinner.
- No entries at all: empty state icon + "No activity yet".
- Entries exist but none match the selected period: empty state icon + "No data for this period".

---

## Screen: Users List

### Purpose
Shows a list of app users, allowing managers and admins to view which users exist and navigate to their individual activity logs.

### Layout
Plain list with a "Users" title (pushed from Profile).

**Each row shows:**
- Circular avatar with user initials (colored by role)
- Full name
- Role label (secondary, small)
- Disclosure chevron

### Data displayed
A list of user rows, each showing: colored avatar with initials, name, and role badge.

### User actions
- **Tap a user row** → opens that user's Activity screen.

### Business rules
- Admins see all users in the system.
- Non-admin users see only users that share their own role (e.g. a SALES user only sees other SALES users).
- Filtering is applied client-side after the full list is fetched.

### API / Data sources
- Firebase — `fetchAllUsers()` — read on load.

### Navigation
- Tap user row → User Activity screen (pushed onto stack)

### Empty / Loading states
- Loading: centered spinner.
- Empty: empty state icon + "No users" text.

---

# Data Models Reference

## User Roles

| Role | Value | Description |
|---|---|---|
| Admin | `ADMIN` | Full access to all features and data. Can manage plans, users, promos, delete activity entries. Avatar: red. |
| Manager | `MANAGER` | Can manage plans and promos. Can view sales and users within their scope. Avatar: orange. |
| Sales | `SALES` | Standard sales rep. Can view and contact salons, record status entries. Cannot manage plans or users by default. Avatar: blue. |

## Permissions Reference

| Permission | Who has it |
|---|---|
| `canEditSalon` | Admin, Manager |
| `canDeleteSalon` | Admin |
| `canManagePlans` | Admin, Manager |
| `canManagePromos` | Admin, Manager |
| `canViewSales` | Admin, Manager |
| `canViewUsers` | Admin |
| `canEditClient` | Admin, Manager |
| `canDeleteActivity` | Admin |
| `isAdmin` | Admin |

## Salon Pipeline Statuses

| Status | Description | Color |
|---|---|---|
| `new` | Not yet contacted | Green |
| `contacted` | Initial contact made | Orange |
| `test_drive` | Product test drive in progress | Purple |
| `demo_scheduled` | Demo meeting scheduled | Blue |
| `ordered` | Client placed an order | Mint |
| `other` | Does not fit other categories | Gray |

## Lead Temperature

| Value | Meaning | Color |
|---|---|---|
| `A` | Hottest lead — high priority | Red |
| `B` | Medium priority | Orange |
| `C` | Cold lead | Blue |

## Invoice Payment Statuses

| Status | FlexiBee Code | Color |
|---|---|---|
| Paid | `uhrazeno` | Green |
| Partial | `castecneUhrazeno` | Orange |
| Unpaid | `neuhrazeno` | Orange |
| Overdue | Computed: unpaid and past due date | Red |

## Payment Methods

| Method | FlexiBee Code |
|---|---|
| Bank Transfer | `code:PREVOD` |
| Cash | `code:HOTOVE` |
| Card | `code:KARTA` |

## Backend Systems

| System | Purpose |
|---|---|
| Firebase / Firestore | Salons, users, plans, promos, status history, activity entries, barcode lookup |
| Firebase Auth | Authentication (email/password) |
| FlexiBee | Accounting ERP: invoices, stock, price list, warehouse movements, cash receipts, address book |

---

# Shared UI Patterns

The following UI components are reused throughout the app.

## Status Badge
A small rounded rectangle showing a status name in its color (e.g. "New" in green, "Contacted" in orange, "Demo" in blue, "Test Drive" in purple, "Ordered" in mint, "Other" in gray).

## Lead Temp Badge
A 32×32 rounded square showing "A", "B", or "C" in the corresponding color (A = red, B = orange, C = blue). When selected, the background is filled; when unselected, it is gray. Tapping a selected badge deselects it.

## Sync Status Row
A horizontal row centered in the list with a sync icon and the last sync date + time in secondary caption text. Shows a spinner and "Loading…" text when syncing.

## Stat Badge / Stat Card
Small cards (or badges) showing a numeric value, a label, and an icon. Used in the Salons stats footer and Stock header. Color-coded per metric.

## KPI Card
A fixed-width card with a left-aligned icon, large bold value, and caption label below. Used in Sales Analytics and Client Detail.

## Filter Chip
A pill/capsule-shaped toggle button. When selected: accent-colored background, white text. When deselected: gray background, primary text.

## Action Button
A vertical button with a large icon above and a small label below, with a lightly tinted rounded background. Used in Salon Detail quick actions.

## Error View
Centered error state with an orange warning icon, a message, and a "Retry" button with primary styling.

## Loading Overlay
A frosted semi-transparent full-screen overlay with a centered spinner and optional status text. Used during saves and loads.

## Close Button
A filled "X in a circle" icon (gray) used consistently in all modal toolbars on the left (cancel/dismiss) side.

## Status History Row
A card-style row with a small colored circle on the left, the status name and date on the same line, and an optional note below.

## Invoice Row
Compact list row with invoice number (bold), client name, date, payment method icon, total amount, and a color-coded payment status badge.

## Salon Row
List row with the salon name (bold), status badge, address (secondary, truncated), and a row of contact icons (phone green, Instagram purple, Facebook blue, website orange, language flag emoji).

## Stock Item Row
Row with product code (bold secondary caption), product name, optional volume badge, color-coded quantity badge (red = 0, orange = 1–2, green = 3+), and sell price.

## Circular Progress Ring
A ring graphic (76 pt diameter) showing achieved vs. target count inside the ring, with a label below. Used in Profile progress section.

## Floating Action Button (FAB)
Circular accent-colored button in the bottom-right corner. Used in Invoices list and Client Detail to create new records.

## User Avatar
Circular avatar displaying the user's initials, colored by role (red = admin, orange = manager, blue = sales).

## Color Reference Summary

**Salon Status Colors:**
| Status | Color |
|---|---|
| New | Green |
| Contacted | Orange |
| Demo Scheduled | Blue |
| Test Drive | Purple |
| Ordered | Mint |
| Other | Gray |

**User Role Colors:**
| Role | Color |
|---|---|
| Admin | Red |
| Manager | Orange |
| Sales | Blue |

**Payment Status Colors:**
| Status | Color |
|---|---|
| Paid | Green |
| Unpaid | Orange |
| Overdue | Red |

**Stock Quantity Colors:**
| Quantity | Color |
|---|---|
| 0 | Red |
| 1–2 | Orange |
| 3+ | Green |
