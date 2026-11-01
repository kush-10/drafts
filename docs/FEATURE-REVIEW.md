# Drafts feature inventory and usability review

## Overall review

**The app has drifted from a quick scratchpad into a scratchpad + organiser + AI configuration panel + testing tool.** Those additions aren’t separated well enough.

The clearest usability regressions are:
- Basic action buttons disappeared from the notepad.
- The window now stays open when switching apps, while “always on top” remains enabled by default.
- Settings became a long page of unrelated controls.
- Simple note search now shares an interface with category commands and AI search.
- Experimental model-testing controls sit alongside everyday features.

Below is an editable inventory. **“Original” means the last committed version before these recent changes**, not necessarily the earliest version of Drafts. Defaults listed aren’t necessarily your saved preferences.

Mark any item **KEEP / REVERT / REMOVE / SIMPLIFY**.

---

## A. Everyday note-taking

| # | Feature now | Original / review |
|---|---|---|
| **1** | Menu-bar app, no Dock icon; optional hidden menu-bar icon. | Original. Keep unless you want a conventional app window. |
| **2** | **⌥Space** opens the notepad; pressing again saves and hides. Global binding is configurable. | Original. Core feature. |
| **3** | Reopening chooses the **most recently edited** active note. | **Changed:** originally chose the newest-created note. |
| **4** | Clicking outside or switching apps **leaves the notepad open**. Hide explicitly using the shortcut, Escape, or Copy & close. | **Changed:** originally saved and hid automatically. A major interaction change. |
| **5** | Autosave shortly after editing; pending changes also save on switching notes, hiding, sleep, and quitting. Save failures keep changes in memory and show an error. | Original safeguards. **Strongly recommend keeping.** |
| **6** | **⌘S** explicitly saves without hiding. | New. Low-complexity addition; autosave still works without it. |
| **7** | **⌘N** creates a blank note or reuses an existing blank. Never overwrites nonblank notes. | Original. Keep. |
| **8** | Bold, italic, underline; no formatting toolbar. | Original. |
| **9** | Bullets; Return continues a list and an empty bullet ends it. | Original. |
| **10** | Explicit paste preserves supported basic formatting and ignores new images. No automatic clipboard capture. | Original. |
| **11** | **⇧⌘C** copies the entire note as plain text, saves, and hides. Normal **⌘C** copies the selection. | Original. |
| **12** | Standard undo/redo, cut/copy/paste, select all, and close commands. | Original. Essential, regardless of what gets removed. |

## B. Window and appearance

| # | Feature now | Original / review |
|---|---|---|
| **13** | “Keep above other windows,” **on by default**. | Original option, but more intrusive when combined with item **4**. |
| **14** | Notepad is manually resizable. Default **760 × 500**, minimum **640 × 380**. Drag unused footer space to move it. | Resizing is new; original used a fixed compact size. |
| **15** | **⌘F** expands to the display’s usable area, then restores the previous frame. Not a separate macOS full-screen Space. | Original. Unconventional shortcut: users normally expect Find. |
| **16** | Remembers size and expanded state for **30 minutes by default**, adjustable in Settings and preserved across restarts. Reopening recentres the window. | **Changed:** originally reopening/New reset to compact. It remembers size, not your exact screen position. |
| **17** | Twenty selectable light/dark themes with previews and theme search. | New. Original had one dark appearance. |
| **18** | Footer shows **word count + categories**. | **Changed:** removed visible **Notes, New, Copy & close, Hide, Expand/Restore** buttons and shortcut hints. **My strongest candidate to reconsider.** |

## C. Finding and browsing notes

| # | Feature now | Original / review |
|---|---|---|
| **19** | **⌘K and ⌘L** open the same search popup. **⌥⇧K** opens it globally. Existing query is preserved while switching these shortcuts. | Original had **⌘L** for a simple in-window note list; no separate global search shortcut. |
| **20** | Ordinary text search matches all search words, ignoring case/accents. Results are ordered by **last edit**. | Matching is original; ordering changed from creation time. |
| **21** | `/Category` filters notes; names with spaces work without quotes. Multiple filters require all selected categories. | New. Powerful, but requires remembering syntax. |
| **22** | Typing `/` offers category and `/lookup` suggestions; Tab/Return completes them. | New. Suggestions temporarily replace the note-results area. |
| **23** | `/lookup description` runs local semantic search. Can be combined with categories; returns ranked notes, not an AI-written answer. | New. Requires an explicit Return to run, then another to open a result. |
| **24** | Arrow keys select results; Return opens; Escape dismisses search before hiding the note. Semantic search has loading/cancel/error states. | Basic navigation is original; AI states are new. |
| **25** | Separate **Full List Editor**, global **⌥⇧L**. Fixed **1000 × 640** window; text search, sortable title/created/edited columns, All/Trash views. | Original. Another way to browse alongside the popup. |
| **26** | Select a table row to edit below it; double-click/open to use the notepad. Table includes manual category assignment. Reopening resets table filters/selection. | Editing is original; category controls are new. |
| **27** | Move notes to Trash, restore, or permanently delete with confirmation. | Original. Keep safety confirmation. |

## D. Categories and automatic organisation

| # | Feature now | Original / review |
|---|---|---|
| **28** | Create, rename, describe, and delete custom categories in Settings. Deleting a category doesn’t delete notes. | New. |
| **29** | Notes support multiple categories or **Uncategorised**. Categories appear in the footer and search results. | New. “Uncategorised” is permanently visible even if you don’t use organisation. |
| **30** | Click the category menu to assign/remove categories manually. Manual inclusions/exclusions override automatic results; “Use automatic assignments” resets overrides. | New. Safe behaviour, but the distinction isn’t particularly obvious. |
| **31** | Automatic classification after successful content saves, with a further one-second debounce. **Enabled by default**, but requires categories to do useful work. | Entirely new versus original. In the intermediate implementation it ran on hiding/switching; now it runs on saves. |
| **32** | Manual category corrections are saved as examples for future classification. Automatic predictions aren’t treated as human labels. | New. **Learning from corrections is not exposed as a separate opt-in setting.** |
| **33** | Three selectable organisers: bundled embeddings, Apple’s on-device model, or local Ollama. Default is bundled embeddings. | New. Backend selection adds substantial conceptual overhead. |
| **34** | Bundles a roughly **639 MB embedding model** plus inference worker. Starts on demand, uses Metal on Apple Silicon, and stops after inactivity. Semantic search still uses it even when Apple/Ollama is selected for classification. | New. Original had no model/runtime dependency. Potential resource cost—not a measured explanation for all sluggishness. |
| **35** | Settings exposes model availability, organisation status/counts, errors, **Organise existing notes, Pause, Retry unfinished/failed, Rebuild index**. | New. Too much operational machinery for the main settings page. |

## E. Experimental benchmark

**All of this is new. It can be removed from the everyday app without removing basic note-taking.**

| # | Feature now | Review |
|---|---|---|
| **36** | Dedicated benchmark window with Dataset / Label notes / Results tabs. Select read-only source notes; generate fictional notes locally through Apple/Ollama; review/edit dummy text. | This is a testing workflow, not a normal scratchpad feature. |
| **37** | Keyboard labeller: **1–4** categories, **M** multiple, **0** Uncategorised, **S** skip, **←** undo. Labels persist and reopening resumes unfinished work. | Useful for the experiment. Reviewing old/skipped notes is less convenient than it should be. |
| **38** | Compare original embedding baseline, improved embeddings, Apple, and Ollama. Related variations stay in the same reference/validation/test split; scores wait for your labels. | Sound separation, but a lot of complexity for a one-off decision. |
| **39** | Accuracy/F1/category metrics, errors, latency, model provenance, saved reports, and mistake inspection. | Dense results screen. No simple summary-first view. |
| **40** | Separate buttons to adopt a backend or import reference examples into real-note organisation. Doesn’t automatically adopt a winner. | Safe intent, but the two actions and their combined effect need clearer explanation and confirmation. |

## F. Storage, privacy, and distribution

| # | Feature now | Original / review |
|---|---|---|
| **41** | Local note JSON files preserve rich text/legacy content. “Show files” opens storage. No sync or accounts; unreadable files aren’t overwritten. New category/example/cache/benchmark files live separately under `.drafts/`. | Core storage is original; extra metadata stores are new. Not independently encrypted. |
| **42** | **Keep everything** by default. Optional automatic **permanent deletion**, including Trash, after a configurable number of minutes/hours/days since last edit. Protects the actively edited note. | Already in the baseline. **Still worth reviewing:** permanent expiry is risky for a scratchpad with valuable notes. |
| **43** | Bundled and Apple inference stay on-device. Optional Ollama uses localhost only; no automatic server startup, model downloads, or silent fallback. | Original had no runtime networking or AI. Current safeguards should stay if Ollama stays. |
| **44** | Locally rebuilt app in `dist/Drafts.app`; separate installed copies may exist. No automatic updater. Benchmark also has command-line launch/preparation options. | Local builds existed before, but distinguishing the experimental build from an installed older copy is now more important. |

---

## What I think needs fixing or clearing up

These are **review findings and recommendations**, not claims that I’ve measured every performance problem.

### F1. Restore access to basic actions

Removing the footer buttons made the app visually quieter but **harder to operate without memorised shortcuts**. I would restore a small set—probably **Notes, New, Copy & close**—before adding anything else.

### F2. Decide whether this is a temporary popup or a persistent window

Currently it mixes both:
- Nonactivating floating-panel behaviour.
- Always-on-top default.
- No auto-hide.
- Remembered expanded size.

That combination can feel like a window that won’t get out of the way. Pick one primary behaviour rather than adding more rules.

### F3. Separate normal settings from advanced controls

The fixed-size settings window now contains shortcuts, window behaviour, twenty themes, models, job statuses, category editing, and storage controls in one long scroll.

**Recommendation:** short General settings; separate Appearance and optional Advanced/AI sections.

### F4. Keep ordinary search ordinary

Plain search, category completion, and semantic search currently compete for the same popup and Return key.

**Recommendation:** text search first; categories and “search by meaning” should be optional, clearly labelled additions—not required command syntax.

### F5. Remove the benchmark from the everyday interface

The experiment doesn’t need permanent prominence in both menus and Settings.

**Recommendation:** separate developer tool or hidden experimental entry. Keep its data unless you explicitly request deletion.

### F6. Add a genuine “no AI” mode—or remove AI

Disabling automatic organisation currently **does not disable semantic search or remove the bundled model**. Choosing Apple for classification also doesn’t make the app Apple-only.

That needs to be explicit. A lightweight build without the bundled model is a separate decision.

### F7. Make learned examples manageable

Manual corrections are retained, but there is no straightforward screen to inspect/delete individual learned examples or clearly turn that learning off.

**Recommendation:** explicit consent/control if learning remains.

### F8. Make background-job behaviour less confusing

“Pause,” disabling automatic organisation, cancelled jobs, and “Retry unfinished” are different mechanisms. Interrupted jobs can remain pending until retried.

**Recommendation:** one understandable enable/disable control, simple status, and one retry action only when necessary.

### F9. Make search ordering consistent

The popup uses last-edited order; the full-list table initially uses creation order. Reopening follows last edit, while selecting a note alone doesn’t make it the next reopened note.

These rules are defensible individually, but collectively surprising.

### F10. Fix benchmark rough edges if it survives

- Saved labels survive restart, but the actual undo history doesn’t.
- Previous datasets are retained without a proper dataset browser.
- Repeated comparisons accumulate report cards.
- Adoption lacks a clear success summary.
- Backend adoption and example import are separate, so adopting a result doesn’t necessarily reproduce its benchmark setup.
- Latency measurements may use warm caches; they aren’t a controlled cold-start comparison.

### F11. Clarify shortcuts and duplicate names

`⌘K` and `⌘L` do the same thing but still appear under different search names in parts of the menus. `⌘F` means Expand rather than Find. `⌘S` exists but isn’t listed in the main settings shortcut summary.

### F12. Measure responsiveness before blaming a specific component

The model adds real disk/memory/compute cost, but I haven’t profiled your reported clunkiness. We should distinguish:
- Slow opening/focus.
- Typing lag.
- Slow search.
- Window behaviour getting in the way.
- Too many steps and controls.

**Passing tests did not establish that the app remained pleasant to use.**

---

## My recommended direction

**Return the everyday app to:** quick open → write → find another note → copy/hide.

Keep storage safety and editing reliability. Restore discoverable basic controls. Move AI, category-learning machinery, and benchmarking out of the main experience unless you specifically want them.

You can record decisions like this:

> **Revert:** 4, 16, 18<br>
> **Remove:** 32–40<br>
> **Keep:** 3, 14, 17<br>
> **Simplify:** 19–24<br>
> **Fix:** F3, F9, F11

**No app behaviour was changed during this review.**
