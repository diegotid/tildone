# Tildone macOS 2.0 — App Store metadata draft

Prepared 25 October 2026. English (US), Spanish (Spain), French and Simplified Chinese. These are local drafts; nothing has been uploaded or published.

The four requested fields are in each locale folder as plain UTF-8 text. `name.txt` and `subtitle.txt` are coordinated recommendations included because keyword coverage depends on those fields. `metadata.json` contains all copy; `validation.json` contains field counts. `REVIEW.md` puts every language into one document.

## Positioning

Lead with keeping the next task visible, then continuing on iPhone. Free iCloud sync is prominent. Explain that Pro is optional, purchased once for Mac and iPhone, and has no subscription. Separate free appearance controls from paid text styling, subtasks and Mac workspace controls. Avoid suggesting that reminders include timed alerts or that completed notes are archived: completed checklists fade and are deleted, with an opportunity to cancel.

## Search and conversion choices

Apple identifies name, subtitle, keywords and category relevance among search factors. Promotional text does not affect search ranking. It therefore carries the outcome, free sync and purchase model. The description opens with the outcome, follows with everyday situations, and explains Pro after the free value. Release notes describe the actual 2.0 changes rather than repeating every existing feature.

Keyword choices are relevant search hypotheses, not measured popularity or difficulty scores. They cover desktop notes, floating notes, checklists, offline use and subtasks in locally appropriate language. Shopping-related keywords have been removed in every locale because shopping is a secondary use case without supporting demand or conversion evidence. Do not use competitor names, unauthorized trademarks or unsupported capabilities. No keyword set can guarantee the most impressions or downloads without performance evidence.

The final English recommendation is “Simple To-Do List: Tildone” with “Sticky notes with iCloud sync”. The title puts the category and simplicity first; the subtitle adds the sticky-note distinction and cross-device continuity. The colon is compact and readable, saving one character compared with a spaced em dash. This is an editorial recommendation, not evidence that category-first order or colons improve ranking or conversion. Localized titles use natural category-first wording and retain Tildone; French follows its spacing convention before the colon and Chinese uses the full-width colon. Spanish and French subtitles use compact natural wording for sticky notes and iCloud, with sync terms also covered in keywords. All name/subtitle pairs here are proposed values, not live App Store metadata.

**The keyword files assume the final name/subtitle pairs in this package. Rework keywords if those pairs change.** The English field no longer repeats “notes” or “list”; it adds checklist, subtask, floating-note and offline vocabulary. We avoid “goal”, “project” and an unqualified “private” promise, and do not spend space on “todo” given its potential overlap with “To-Do”. We do not assume how Apple normalizes punctuation, or rely on speculative cross-locale indexing or promised semantic-ranking boosts. Promotional text, descriptions and release notes are unchanged by this title/subtitle revision.

## Limits and validation

Apple's marketing guide specifies 100 characters for keywords, while its App Store Connect reference specifies 100 bytes. These drafts conservatively meet both, including Chinese. Counts exclude the file's final newline and include spaces and punctuation within the copy. All fields use plain text, without HTML. Passing these checks does not claim that an App Store Connect upload was tested.

| Locale | Name / 30 | Subtitle / 30 | Promo / 170 | Description / 4000 | What’s New / 4000 | Keywords chars / UTF-8 bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| en-US | 26 | 29 | 142 | 1554 | 672 | 88 / 88 |
| es-ES | 24 | 26 | 132 | 1902 | 770 | 90 / 91 |
| fr-FR | 25 | 25 | 130 | 1972 | 804 | 89 / 92 |
| zh-Hans | 14 | 14 | 74 | 619 | 294 | 35 / 85 |

## Release use and evidence

This package targets the macOS 2.0 update. Publish the companion/sync claims when both the Mac update and iPhone app are available. The first iPhone 1.0 release has no “What’s New” field; these release notes are for the Mac update. An iPhone description should have its own phone-first ordering.

Product claims were checked against `Shared/Discovery/WhatsNewRelease.swift`, `Shared/ProFeature+Presentation.swift`, `Shared/ProPaywallView.swift`, `Shared/ProEntitlement.swift`, and Mac settings/completion behavior. Appearance customization and minimization existed before 2.0 and are described as benefits, not new features. The copy makes no unverified encryption, tracking or data-collection promises.

After release, review App Store Search impressions, downloads and conversion in App Store Connect, separated by platform and territory where available. Compare equivalent periods and account for the launch, ratings, ads and creative changes. Refine terms based on relevant traffic and downloads rather than impressions alone. These files are a baseline, not a claim of a completed conversion experiment.

## Sources

Current Apple guidance checked on 25 October 2026:

- [App Store search](https://developer.apple.com/app-store/search/)
- [Creating your product page](https://developer.apple.com/app-store/product-page/)
- [Platform version information and field limits](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [Current English public listing](https://apps.apple.com/us/app/tildone-sticky-to-dos/id6473126292?mt=12)
- [Current Spanish public listing](https://apps.apple.com/es/app/tildone-tareas-adhesivas/id6473126292?mt=12)
- [French listing name](https://apps.apple.com/us/app/6473126292?l=fr-FR&platform=mac&see-all=reviews)
