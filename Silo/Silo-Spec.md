# Silo — Build Specification

> **Tagline:** *Your product stash.*
> A calm, on-device locker for things you want to buy. Share a link from any app, and it lands in Silo. File it into a collection when you feel like it, and tap to jump back to the product page to buy whenever you're ready. No accounts, no servers, no alerts.

**Working name:** `Silo`. The bare word is contested on the App Store, so treat this as the internal/working name and finalize the public **display name** (e.g. "Silo: Your Product Stash") before submission. Nothing in the build depends on the final string — keep the app name in a single constant.

**Audience for this doc:** the engineer (or Claude Code) building the app. It is the source of truth for scope, data model, interactions, and theming. Read it top to bottom before scaffolding.

---

## 1. North Star: Calm

Every decision serves one principle: **calm**. Silo is a quiet place where purchase intent rests until you want it. The absence of features is the feature.

Concretely, calm means:

- **No notifications. No price-drop alerts. No background polling.** Price is something you *discover when you look*, never something that reaches out to you.
- **No accounts, no login, no social, no feed.** Fully on-device.
- **No decision tax at capture.** Saving is instant and silent; filing is optional and later.
- **Restraint in UI.** Paper-and-ink chrome, photography-forward cards, color held in reserve for collections only.

If a proposed feature adds urgency, noise, or obligation, it does not belong in v1. When in doubt, do less.

---

## 2. Goals & Non-Goals

### Goals (v1)
1. Capture a product link from any app/site into Silo in **under one second**, with zero prompts.
2. Turn a raw URL into a clean product card (title, image, price, source) **automatically and silently**.
3. Let the user organize saved items into **color-coded collections** with near-zero friction.
4. Let the user **jump back to the product page to buy** in one tap.
5. Feel calm, private, and entirely on-device.

### Non-Goals (explicitly out of scope for v1)
- **Price-drop / back-in-stock alerts** — would force a backend and break the calm thesis.
- **Accounts, login, social, sharing lists with others, public profiles.**
- **Android / web / iPad-optimized layouts.** iPhone first. (Build should not actively preclude iPad, but don't design for it.)
- **In-app browser / built-in checkout.** We hand off to the retailer via the canonical URL.
- **Affiliate-link monetization.** Architecturally allowed for later (see §15) but **off and unbuilt** in v1.
- **CloudKit sync.** Designed-for (see §6, §15) but not enabled in v1.
- **Tags.** Collections only. No free-form tagging.

---

## 3. Platform & Stack

- **Language:** Swift 6 (strict concurrency where practical).
- **UI:** SwiftUI.
- **Persistence:** SwiftData (single shared `ModelContainer`).
- **Min deployment target:** iOS 18.0 (locked). Free to use iOS 18 SwiftData/SwiftUI APIs without availability gating.
- **Capture:** Share Extension + App Groups (shared container).
- **Metadata:** `LinkPresentation` (`LPMetadataProvider`) for quick title/icon; `URLSession` + lightweight HTML/JSON-LD parsing for price and canonical image.
- **Background work:** `BackgroundTasks` (`BGProcessingTask`) for deferred enrichment — opportunistic, never for price alerts.
- **Hand-off to buy:** Universal Links via `UIApplication.open(_:)`.
- **Third-party dependencies: zero (locked).** HTML/JSON-LD parsing is done with targeted string scanning + `JSONDecoder` (see §8). No `SwiftSoup` or other parsing library — this is a deliberate decision in service of the privacy-clean, dependency-free posture, not a default to revisit lightly.
- **No analytics, no tracking SDKs, no crash reporters that phone home** without explicit, disclosed opt-in. v1 ships with none.

---

## 4. Architecture Overview

```
┌─────────────────────────────┐        ┌──────────────────────────────┐
│  Share Extension (thin)     │        │  Main App (SwiftUI)          │
│  - receives shared URL      │        │  - Home / Detail / Archive   │
│  - writes minimal Item      │ ─────► │  - Collections + filing      │
│    (state = .caught)        │  App   │  - Enrichment service        │
│  - returns FAST (<1s,       │  Group │  - Opportunistic price check │
│    <120MB)                  │ shared │  - Open & Buy (Universal Link)│
└─────────────────────────────┘ store  └──────────────────────────────┘
                                  │
                       ┌──────────▼───────────┐
                       │  Shared App Group     │
                       │  - SwiftData store    │
                       │  - cached images dir  │
                       └───────────────────────┘
```

**Save fast, decorate later.** The extension does the bare minimum and returns. All heavy work (redirect resolution, HTML fetch, price parse, image download) happens in the main app or a background task. The UI always renders *something* immediately and upgrades silently.

App Group identifier: `group.<reverse-domain>.silo` (single constant; used by both targets for the `ModelContainer` URL and the image cache directory).

---

## 5. Data Model (SwiftData)

Single-home model: **each `Item` belongs to exactly one `Collection`, or none.** `collection == nil` *is* "Unsorted" — Unsorted is a computed view, never a stored row.

```swift
import Foundation
import SwiftData

enum ItemState: String, Codable, CaseIterable {
    case caught     // just shared; URL + maybe cached title/icon
    case enriched   // metadata + price resolved
    case gotIt      // purchased — positive closure (archive)
    case abandoned  // "not anymore" — neutral (archive)
}

@Model
final class Item {
    var id: UUID = UUID()

    // URLs
    var urlString: String = ""            // canonical https URL (stored as String for predicate use)
    var originalURLString: String?        // raw shared URL before redirect resolution

    // Metadata
    var title: String?
    var sourceDomain: String?             // e.g. "myntra.com" — for the card subtitle
    var imageLocalPath: String?           // filename in App Group images dir (not absolute path)
    var faviconLocalPath: String?

    // Price snapshot
    var savedPrice: Decimal?              // price at save time
    var currentPrice: Decimal?            // most recent opportunistic check
    var currencyCode: String?             // ISO 4217, e.g. "INR"
    var priceCheckedAt: Date?

    // User data
    var note: String?
    var savedAt: Date = Date()

    // State (stored as raw string — SwiftData #Predicate can't filter on enums directly)
    var stateRaw: String = ItemState.caught.rawValue

    // Relationship — nil means Unsorted
    var collection: Collection?

    var state: ItemState {
        get { ItemState(rawValue: stateRaw) ?? .caught }
        set { stateRaw = newValue.rawValue }
    }

    var url: URL? { URL(string: urlString) }

    init(urlString: String, originalURLString: String? = nil) {
        self.urlString = urlString
        self.originalURLString = originalURLString
    }
}

@Model
final class Collection {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = ""             // light-mode swatch hex (see §10.4)
    var darkColorHex: String = ""         // dark-mode (lifted) swatch hex (see §10.4)
    var createdAt: Date = Date()

    // Deleting a collection un-files its items back to Unsorted — NEVER deletes them.
    @Relationship(deleteRule: .nullify, inverse: \Item.collection)
    var items: [Item] = []

    init(name: String, colorHex: String, darkColorHex: String) {
        self.name = name
        self.colorHex = colorHex
        self.darkColorHex = darkColorHex
    }
}
```

**Modeling notes (important):**
- All properties have defaults / are optional. This keeps the model **CloudKit-compatible** for a future sync add (CloudKit forbids non-optional, default-less, unique-constrained attributes). Do not add `@Attribute(.unique)`.
- Filter by state in views using `stateRaw`, e.g. active items are `stateRaw == "caught" || stateRaw == "enriched"`.
- `imageLocalPath` stores a **filename**, resolved against the App Group images dir at read time. Never store absolute container paths — they change across launches/devices.

### Predicate examples

```swift
// Active items (not archived) for the "All" lens
let active = #Predicate<Item> { $0.stateRaw == "caught" || $0.stateRaw == "enriched" }

// Unsorted lens
let unsorted = #Predicate<Item> {
    ($0.stateRaw == "caught" || $0.stateRaw == "enriched") && $0.collection == nil
}

// A specific collection lens (capture collectionID, compare via relationship)
// Filter active items, then in-memory filter by collection?.id == selectedID,
// or use a predicate comparing the optional relationship's id.
```

> Note for the builder: SwiftData predicate support for optional to-one relationship comparisons can be finicky. If a relationship predicate misbehaves, fetch active items with a single `@Query` and partition by `collection?.id` in memory — the dataset is personal-scale (hundreds, not millions), so this is fine.

---

## 6. Item Lifecycle

```
   share link
       │
       ▼
   ┌────────┐   enrichment    ┌──────────┐
   │ caught │ ───────────────►│ enriched │
   └────────┘                 └──────────┘
                                   │
                    ┌──────────────┼───────────────┐
                    ▼              ▼                ▼
                ┌────────┐   ┌───────────┐    (stays active,
                │ gotIt  │   │ abandoned │     filed or unsorted)
                │"Got it"│   │"Not anymore"
                └────────┘   └───────────┘
                    │              │
                    └──────┬───────┘
                           ▼
                       Archive view
```

- **caught** → exists the instant the user shares. Card renders immediately (title/favicon if the extension grabbed them, else a shimmer placeholder + the domain).
- **enriched** → main app / background task resolved the canonical URL, pulled price + hero image, cached the image. Card upgrades silently.
- **gotIt** → user bought it. Leaves the active shelf, moves to the **Got it** archive. Positive closure — a little trophy case.
- **abandoned** → user changed their mind ("Not anymore"). Moves to a neutral archive, rarely looked at.
- **Delete** is separate and rare (saved by mistake) — hard removal, with the image file cleaned up.

`gotIt` and `abandoned` both leave the active shelf but mean opposite things; **keep them distinct.** Neither is a delete.

---

## 7. Enrichment & Price Pipeline

### 7.1 Capture (Share Extension — keep it dumb and fast)
1. Receive the shared item (`NSExtensionItem` → `NSItemProvider`, type `public.url` first, fall back to `public.text` / `public.plain-text` and extract the first URL).
2. Create `Item(urlString:..., originalURLString:...)` with `state = .caught` and write to the shared `ModelContainer`.
3. Optionally attempt a **time-boxed** `LPMetadataProvider` fetch (≤ ~1.5s) to grab a title + icon for a nicer immediate card. If it doesn't return in budget, skip — the main app will enrich. **Never block the dismissal on the network.**
4. Show a minimal "Saved to Silo" confirmation and auto-dismiss. **No collection prompt at capture.**

Hard constraint: the extension must stay well under the ~120 MB extension memory ceiling and feel instant.

### 7.2 Enrichment (Main app foreground + `BGProcessingTask`)
For every `.caught` item:
1. **Resolve redirects** — `URLSession` follows `amzn.to`, `dl.flipkart.com`, etc. to the canonical `https://` URL. Store it in `urlString` (keep the raw in `originalURLString`).
2. **Fetch the page** and parse, in priority order:
   - **JSON-LD** — extract `<script type="application/ld+json">` blocks, `JSONDecode`, look for schema.org `Product` / `Offer` → `name`, `image`, `offers.price`, `offers.priceCurrency`, `offers.availability`. This is the most reliable source on serious retailers.
   - **OpenGraph / meta fallback** — `og:title`, `og:image`, `product:price:amount` / `og:price:amount`, `product:price:currency`.
   - **`LPMetadataProvider` fallback** — title + image only, when the above yield nothing.
3. **Cache the hero image** to the App Group images dir; store the filename in `imageLocalPath`.
4. Set `savedPrice` (and `currentPrice`) + `currencyCode`, `sourceDomain`, `title`, `savedAt` already set. Mark `state = .enriched`.

### 7.3 Price re-check — opportunistic only
- Triggered **only** on: opening an item's detail view, and pull-to-refresh on the home shelf.
- Re-runs the parse, updates `currentPrice` + `priceCheckedAt`.
- **Never** scheduled, **never** background, **never** a notification.
- Detail view shows the delta only when the user is already looking: `₹3,200 when you saved → ₹2,800 now`. Struck-through old price, gentle "now". No badges, no red urgency.
- **Manual baseline (FR-13):** if the user manually set the price, that value is the sticky baseline (`savedPrice`) and is never overwritten. Re-checks still fetch and update the live `currentPrice`, so the then→now comparison keeps working against the user's chosen baseline.

### 7.4 Open & Buy
- Open `urlString` (canonical `https`) via `UIApplication.open`. Universal Links route to the installed retailer app on that product, else Safari. No custom-scheme gymnastics in v1.

---

## 8. Parsing Notes (for the builder)
- **Dependency-free parsing (locked):** regex/string-scan for the `ld+json` script blocks and `<meta>` tags, then `JSONDecoder` for the JSON-LD payload — no HTML-parsing library. Product JSON-LD is sometimes an array or graph (`@graph`) — handle both; pick the node whose `@type` is `Product`.
- `offers` may be an object or an array — normalize.
- Prices arrive as strings or numbers, sometimes with currency symbols/commas — sanitize to `Decimal`.
- Many pages need a realistic `User-Agent` and may be JS-rendered; if a page returns no usable price, **degrade gracefully to no price** — that's an acceptable, expected outcome, not an error state.
- App-only deep links with no web equivalent: store as-is, skip enrichment, render a generic card from the domain/scheme. Don't fail.

---

## 9. Screens & Interactions

### 9.1 Home
- **One screen, lateral filtering — no navigation to switch contexts.**
- **Pill lens row** (horizontal scroll), pinned at top:
  - `All` — far left, **default selected**.
  - Named collections — middle, each with its color **dot**.
  - `Unsorted` — pinned right, with a small **count badge** (the calmest possible nudge to tidy).
  - `+` — trailing pill, opens the collection-create sheet.
- Tapping a pill **filters only** (swaps the `@Query` predicate / in-memory partition). Tapping never *moves* anything.
- Below: the items for the selected lens, as **ItemCards** in a **two-column Pinterest-style masonry grid** — staggered columns, variable card heights driven by each product image's natural aspect ratio. This is photography-forward and reads calm despite the density. Implementation: don't use a rigid `LazyVGrid` (its rows align and lose the masonry feel) — distribute items into two `LazyVStack` columns, appending each item to whichever column is currently shorter (or implement a custom masonry via the `Layout` protocol). Generous inter-card spacing and comfortable margins keep it from feeling busy.
- **Toolbar:** a small **archive icon** (opens the Got it / Not anymore archive). Archive is *not* a pill — it's out of the daily flow.
- **Empty states** (calm, inviting, never apologetic):
  - No items at all → "Share a product link to Silo and it'll land here." + a one-line hint on using the share sheet.
  - Empty collection → gentle prompt, not "Nothing here yet."

### 9.2 ItemCard
- Hero image (cached), sized to its **natural aspect ratio** (variable height — this is what gives the masonry grid its staggered Pinterest feel) · title · `sourceDomain` subtitle · price line.
- **Collection accent shown quietly, twice:** a thin **left-edge stripe** (square that corner — no rounded single-sided border) and a small **dot**. An **Unsorted** card has *no* stripe and *no* dot — the absence reads as "not yet filed."
- While `.caught`: shimmer placeholder where the image/price will land.
- **Tap** → ItemDetail.
- **Long-press** → context menu (the single action surface — **no swipe actions**).

### 9.3 Long-press context menu (`.contextMenu`)
Native context menu (card lifts, background blurs — calm by default). Items:
- **Add to collection ›** — submenu listing collections (each with its color dot) + a trailing **"+ New collection"** row that opens the create sheet inline. This submenu *is* the collection manager — there is no separate admin screen.
- **Got it** — sets `state = .gotIt`.
- **Not anymore** — sets `state = .abandoned`.
- **Delete** — hard delete (confirm; clean up cached image).

(Optional, post-v1 flourish: drag a card onto a pill to file it. Not in v1.)

### 9.4 ItemDetail
- Large hero · title · `sourceDomain`.
- **Price then-vs-now line** (only meaningful after a re-check): `₹X when you saved → ₹Y now`.
- Optional **note** field. Saved date.
- Optional **gentle intent-decay prompt** (P1): if `savedAt` is old (e.g. > ~4 months), show a soft, in-context line: "Saved 4 months ago — still want it?" with an easy "Not anymore." Never a notification or badge — it only ever speaks when the user is already here.
- Primary action: **Open & Buy** — the one place the **clay** signature accent appears. Fires the Universal Link.
- Secondary: move to collection / Got it / Not anymore / delete (mirror the context menu).
- **Edit** (FR-13): an edit affordance to manually fix or fill in **title, price + currency, hero image, and source** when enrichment failed, mis-picked, or never ran. Replace the image via `PHPicker` (no permission prompt) or re-fetch from the page; if the page yielded several images, let the user pick among them. Edited title/image/source are sticky (never auto-overwritten); a manual price becomes the saved baseline while re-checks still show a live "now" beside it.
- Pull-to-refresh or on-appear triggers an opportunistic price re-check.

### 9.5 Collection create/edit sheet
- A small sheet: **name TextField** + a row of the **curated color swatches** (tap one — no free color picker). Save.
- Reached from the `+` pill (deliberate) **and** the "+ New collection" row in the long-press submenu (reactive). Same component, two doors.
- Edit (rename / recolor) reachable by long-pressing a collection pill (P1).

### 9.6 Archive
- Behind the toolbar archive icon. Two groups (sections or a segmented control): **Got it** and **Not anymore**.
- From here: restore to active, or delete. Got it is the satisfying trophy case; Not anymore is neutral.

### 9.7 Share Extension UI
- Minimal to none. Ideally a tiny "Saved to Silo" toast, then auto-dismiss. **No collection selection at capture.**

---

## 10. Theming

**Core principle — "color as a whisper":** the app chrome is **paper and ink**. The *only* saturated color on screen comes from collections (a dot + a thin stripe) and the single **clay** accent on the **Open & Buy** button (and the app icon). Everything else recedes so product photography and collection colors read clearly. Never tint whole cards; never use pure black (it reads cold).

Implement as a semantic token layer (a `Theme` / `Color` extension) that resolves per color scheme — do **not** scatter hex literals through views.

### 10.1 Light mode ("paper")
| Token | Hex |
|---|---|
| Canvas / page bg | `#F4EEE4` |
| Card surface | `#FBF7F0` |
| Card border | `#E7DFD2` |
| Pill border | `#E2D9CB` |
| Ink (primary text) | `#2C2823` |
| Secondary text | `#6B6359` |
| Muted text / hints | `#8A8175` |
| Struck (old) price | `#A39A8C` |

### 10.2 Dark mode ("espresso") — warm, never OLED black
| Token | Hex |
|---|---|
| Canvas / page bg | `#1C1916` |
| Card surface | `#262019` |
| Card border | `#342D24` |
| Pill border | `#3A3228` |
| Ink (primary text) | `#EDE6D9` |
| Secondary text | `#7C7468` |
| Muted text | `#6B6357` |

### 10.3 Signature accent (clay) — Open & Buy + app icon ONLY
| | Hex |
|---|---|
| Clay (light) | `#C2663F` |
| Clay (dark) | `#D17A52` |

### 10.4 Collection swatch palette (curated — the ONLY user-pickable colors)
Eight muted, same-family swatches so any combination stays harmonious. In **dark mode**, lift each ~10% in luminance so the dot/stripe stays legible on espresso (sample lifts shown).

| Name | Light hex | Dark (lifted) |
|---|---|---|
| Clay | `#BC6B4A` | `#C97C5A` |
| Amber | `#C49A48` | `#D2A95C` |
| Sage | `#8B9A6B` | `#9CAB7C` |
| Teal | `#5A9488` | `#6FA89B` |
| Dusty blue | `#6F8CA8` | `#82A0BB` |
| Slate | `#7E8693` | `#9098A5` |
| Plum | `#94708E` | `#A8839F` |
| Rose | `#BE8294` | `#CB95A6` |

Store **both** hexes on the collection: `colorHex` (light) and `darkColorHex` (the lifted dark value from the table). Pick by the active color scheme at render. (Decision: store both rather than derive at runtime — explicit, predictable, and lets the palette be hand-tuned per mode.)

### 10.5 Typography
- Native system font for UI (SF Pro). Keep it to **two weights — regular and medium**; avoid heavy bold. Generous line spacing.
- **New York (serif)** for the wordmark and empty-state headlines — a deliberate touch of warmth against the SF body text. (Decision: locked in, not optional.) Everything else (UI, cards, controls) stays SF Pro.
- Respect **Dynamic Type** everywhere.

### 10.6 Component & motion
- Cards: 12–16px corner radius. Pills: full radius. Color stripe: thin left edge, **square** (no rounded single-sided corners).
- Minimal borders (hairline). Generous whitespace. Photography-forward.
- Subtle, calm motion: gentle shimmer on `.caught`, the native context-menu lift. **Respect Reduce Motion** (disable shimmer/large transitions). Light **haptic** on long-press and on Got it.

---

## 11. Functional Requirements

### P0 — must ship
- **FR-1 Capture:** Sharing a `public.url` (or text containing a URL) from any app creates an active item in Silo in < 1s with no prompt.
  - *Given* a product page in Safari/any app, *when* the user shares to Silo, *then* an item appears in Unsorted on next app open, with at least the URL + domain.
- **FR-2 Enrichment:** Items auto-upgrade with title, hero image, source domain, and price when available, without user action.
  - *Then* a `.caught` item becomes `.enriched` with cached image + `savedPrice` when the page exposes JSON-LD/OG price; *and* degrades to no-price gracefully when it doesn't.
- **FR-3 Single-home collections:** User can create a collection (name + swatch) and file an item into exactly one collection via long-press → Add to collection.
- **FR-4 Pill-lens home:** All / collections / Unsorted (+ count) / `+`; tapping filters only.
- **FR-5 Open & Buy:** Tapping the primary action opens the canonical URL (Universal Link → app or Safari).
- **FR-6 Lifecycle:** Got it and Not anymore move items to a distinct archive; Delete removes permanently; deleting a collection nullifies (items return to Unsorted).
- **FR-7 Fully on-device:** No account, no server, no network except fetching the shared product pages for enrichment/price.
- **FR-8 Soft-dedupe:** On capture/enrichment, if the resolved canonical URL already matches an existing **active** item, do not create a second card — surface/refresh the existing one instead. Dedupe keys on the canonical URL (post-redirect-resolution), so it runs during enrichment once the canonical form is known. Archived items (`gotIt`/`abandoned`) do not block a fresh save of the same product.

### P1 — fast follow
- **FR-9** Opportunistic price re-check on detail open + pull-to-refresh, with then-vs-now display.
- **FR-10** Gentle intent-decay prompt in detail for old items.
- **FR-11** Edit collection (rename/recolor) via long-press on a pill.
- **FR-12** Note field on items.
- **FR-13 Manual edit:** the user can manually correct or fill in an item's **title, price + currency, hero image, and source** — the recovery path when enrichment fails, picks the wrong image, or never runs (app-only links). Image replacement via `PHPicker` (no permission prompt) or re-fetch from the page. Manually edited **title, image, and source are sticky** — enrichment never overwrites them (track with a lightweight per-item edited-fields flag/set on `Item`). A manual **price** edit sets the sticky baseline (`savedPrice`); opportunistic re-checks still refresh the live `currentPrice` so the then→now comparison keeps working, but never clobber the manual baseline.

### P2 — future (design-compatible, not built)
- **FR-14** CloudKit sync (models already compatible).
- **FR-15** Drag-card-onto-pill filing.
- **FR-16** Optional, clearly-disclosed affiliate-link rewrite (off by default).

Each P0 ships with acceptance criteria in Given/When/Then form during implementation; the above are the anchors.

---

## 12. Non-Functional Requirements
- **Privacy:** no third-party SDKs, no analytics, no tracking, no data leaves device. App Privacy nutrition label = "Data Not Collected." Network is limited to fetching the user's own shared product pages.
- **Performance:** capture < 1s and < 120MB in the extension; home renders cached content instantly and enriches in the background; image cache bounded (evict orphaned images when items are deleted).
- **Offline:** capture works offline (URL stored; enrichment deferred until connectivity). The app is fully usable for browsing the stash offline.
- **Accessibility:** Dynamic Type, full VoiceOver labels (cards, menu actions, price deltas), Reduce Motion respected, and the muted palette must still pass contrast for text on colored elements — verify accent/swatch text contrast.
- **Resilience:** never crash or block on a failed parse; missing price/image are normal states with clean fallbacks.

---

## 13. Edge Cases
- **Shortened / deep links** (`amzn.to`, `dl.flipkart.com`): resolve to canonical before storing.
- **App-only deep links** with no web equivalent: store as-is, generic card, no enrichment.
- **Non-product URLs** shared: still save; best-effort metadata; no price is fine.
- **Duplicate saves** (same canonical URL): **soft-dedupe is v1 behavior (FR-8)** — on enrichment, once the canonical URL is resolved, if an active item already has it, refresh/surface the existing card rather than creating a second. Archived (`gotIt`/`abandoned`) items don't block re-saving.
- **Paywalled / blocked / JS-only pages:** graceful no-price.
- **Currency & locale:** format using `currencyCode` + user locale; default sensibly when currency is unknown.
- **Image-less products / huge images:** placeholder; downscale on cache.
- **Offline at capture:** store URL; enrich when back online.
- **Collection deleted while filtered to it:** lens falls back to All; items return to Unsorted.
- **Wrong or missing enrichment** (bad image, mis-parsed title/price, app-only links, JS-only pages): the user can manually edit title, price, image, and source in detail (**FR-13**) — the universal recovery path so no item is ever stuck looking broken.

---

## 14. Build Phases (for Claude Code)

Build in vertical slices so there's something runnable early. Each phase = a runnable milestone.

- **Phase 0 — Foundation:** Xcode project, both targets (app + share extension), App Group, shared `ModelContainer`, the `Theme`/color token layer (§10), app-name constant. *Deliverable:* app launches on the paper canvas in light/dark.
- **Phase 1 — Models + Home shell:** `Item`, `Collection`, `ItemState`; Home with the pill-lens row and ItemCard; a debug "add sample item" path. *Deliverable:* cards render and filter by lens.
- **Phase 2 — Capture:** Share Extension writes a `.caught` item to the shared store and dismisses fast. *Deliverable:* sharing a link from Safari shows it in Unsorted.
- **Phase 3 — Enrichment:** redirect resolution, JSON-LD → OG → LP parsing, image caching, `.enriched` transition, `BGProcessingTask`, **soft-dedupe on canonical URL (FR-8)**. *Deliverable:* shared links auto-fill title/image/price and don't double up.
- **Phase 4 — Collections & filing:** create sheet (name + swatch), long-press context menu, Add-to-collection submenu + New collection, color accents on pills/cards, `.nullify` delete behavior. *Deliverable:* full single-home filing.
- **Phase 5 — Detail & Buy:** ItemDetail, then-vs-now price + opportunistic re-check, Open & Buy via Universal Link, **manual edit of title/price/image/source (FR-13)**. *Deliverable:* tap-through to purchase, and any item is fully correctable by hand.
- **Phase 6 — Archive & lifecycle:** Got it / Not anymore archive view, restore, delete + image cleanup, empty states. *Deliverable:* complete lifecycle.
- **Phase 7 — Polish:** light/dark refinement, shimmer, haptics, Dynamic Type/VoiceOver/Reduce Motion, decay prompt (P1). *Deliverable:* ship-ready calm.
- **Later:** CloudKit sync, drag-to-pill, optional affiliate setting.

---

## 15. Resolved Decisions

All prior open questions are settled. None remain blocking — Claude Code can build straight through.

- **Home layout** → two-column Pinterest-style masonry, variable-height cards. (§9.1)
- **HTML parsing** → dependency-free string scanning, no SwiftSoup. (§3, §8)
- **Duplicate handling** → soft-dedupe on canonical URL, v1 behavior, FR-8. (§11, §13, §14 Phase 3)
- **Dark swatch variants** → store both `colorHex` + `darkColorHex` on the collection. (§5, §10.4)
- **Wordmark / empty-state serif** → New York, for warmth. (§10.5)
- **Min iOS** → 18.0. (§3)

---

## 16. Future Considerations (architectural insurance)
- **CloudKit sync:** models are already CK-compatible (optionals, defaults, no unique constraints). Enabling is a `ModelConfiguration(cloudKitDatabase:)` change + entitlement — keep it a clean later toggle.
- **Affiliate rewrite:** the app holds genuine purchase intent, so rewriting saved links with affiliate tags is a non-creepy, ad-free, no-data-sale monetization path. If ever added: opt-in, clearly disclosed, off by default. Not in v1.
- **Drag-to-pill filing**, **soft-dedupe/merge**, **collection cover images** pulled from contained items.

---

### Appendix — One-line summary for a CLAUDE.md pointer
> Silo is a calm, on-device, privacy-first iOS app (SwiftUI + SwiftData + Share Extension over an App Group) that captures shared product links into an instant "Unsorted" shelf, silently enriches them into product cards (JSON-LD/OG price + cached image), lets the user file them into single-home color-coded collections via long-press, and taps back out to the retailer to buy. No accounts, no servers, no alerts. Paper-and-ink theming; color reserved for collections + the clay Open & Buy accent. See `Silo-Spec.md` for the full spec.
