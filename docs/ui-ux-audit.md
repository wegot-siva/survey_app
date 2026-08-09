# UI/UX audit — what shipped, and what was deliberately left

Record of the UI/UX audit and the slices built from it. The "not built"
section matters as much as the rest: everything there was considered and
declined on purpose, so nobody has to re-derive the reasoning or assume it
was missed.

## Shipped

### P0 — cost engineers time on every survey

| # | Problem | Fix |
|---|---------|-----|
| 1 | A failed save on forms with 20–73 required fields showed only a SnackBar; the invalid field was often several screens away | `FormErrorFocus` scrolls to and focuses the first field in error. Required moving the 5 form bodies from `ListView` (lazy — off-screen fields aren't in the tree, so `Scrollable.ensureVisible` can't reach them) to `SingleChildScrollView` + `Column` |
| 2 | The extended FAB covered the last row's overflow menu on 4 list screens | `EdgeInsets.only(bottom: 88)` on each list |
| 3 | Home screen showed raw DB values ("Status: in_progress") while every other screen used `SurveyStatus.label()` | Both call sites now use the label |
| 4 | Every reload blanked the screen to a spinner, losing scroll position, despite reading local SQLite | `_loading` now gates only the *first* load; later reloads keep content and show a 2px `RefreshBar` |
| 8 | Two hardcoded `Colors.green` (~2.8:1 on white) on a UI read outdoors | `AppStatusColors.complete` (`#2E7D32`) |

### P1 — item 7: no load-failure state

All 14 screens with a `_load()` had no `catch`: a thrown read left `_loading`
stuck true — a spinner forever, nothing to read, nothing to tap. Every one
now surfaces the failure.

The rule is deliberately split, because the two cases are not the same:

- **First load fails** → `LoadErrorView` (plain-language message, the raw
  error so the user can quote it, and a Try again button).
- **Refresh fails** → keep whatever is already on screen and report it in a
  SnackBar. Replacing readable content with an error page would throw away
  context the user can still act on — the same reasoning as P0 #4.

### P1 — item 5: font sizes on the type scale

`AppTextStyles` and three ad-hoc `fontSize:` values now resolve from
`Theme.of(context).textTheme`. **See the correction below about why.**

## An audit finding that was wrong

The audit claimed hardcoded `fontSize:` "breaks text scaling", and that
engineers on large system fonts would see clipping as a result. That is true
on the web; it is **not** true in Flutter. `Text` applies
`MediaQuery.textScaler` to whatever size its style carries, so
`TextStyle(fontSize: 20)` scales exactly like a themed style does.

Measured before changing anything: a hardcoded 20px line rendered **29px
tall at 1× and 57px at 2×**.

So the item 5 migration is a **consistency** win — one type scale, honoured
everywhere, responding to theme changes — not an accessibility fix, and it
is not described as one anywhere in the code.

The genuine large-text risk is *layout*: text that grows inside a box that
doesn't. That is independent of where the font size came from, and it is
what `test/text_scaling_test.dart` actually guards, by capturing
`FlutterError.onError` at 2× on the tightest spots (the fixed 96px photo
thumbnail, the error view, and a list row carrying a badge). The harness is
self-verified — it was confirmed to detect a deliberately overflowing
widget, so a green result means something.

## Not built — deliberate

### Item 6: `Semantics` / screen-reader labels
There are zero `Semantics` widgets in the app, and several indicators
(section status, sync state) convey meaning by colour and icon alone. This
is a real gap and correct in principle. **Deferred by an explicit product
call**: no current user on this team relies on a screen reader, and the
remaining time bought more elsewhere. Revisit if that changes — the status
indicators are the place to start.

### `Form` / `GlobalKey` validation migration
The forms validate manually and assign a per-field `errorText`, which
already renders the message next to the offending field. Once scroll-to-error
landed, rewriting them onto `Form`/`FormField` is churn with no user-visible
gain.

### `AppSpacing` token migration
Tokens exist but are used in 1 of 36 screens; everything else hardcodes
`EdgeInsets.all(16)` and friends. Worth doing opportunistically when a file
is open for another reason — not worth a dedicated pass touching 35 files.

### `darkTheme`
The app is light-only (no `darkTheme`, no `themeMode`). Not a problem for
outdoor daylight use, which is the dominant context.
