# IMSTUDY

An iPad flashcard app built with SwiftUI, SwiftData and PencilKit (iOS 17+, iPad only).

## Features
- Multiple decks (deck list with create / delete), with no limit on cards
- Handwritten cards: draw with Apple Pencil, pan/zoom with fingers (Simulator accepts any input)
- Two-sided cards with a 3D Rotate button to edit front and back
- Previous / Next buttons and a single New Card button inside the editor, so you never have to leave it
- Tap anywhere in the empty slot of the deck grid to add a card
- Dark mode (System / Light / Dark) like Notes: dark paper, ink colors invert
- Per-side lined or blank paper, plus any number of typed text boxes on either side: tap a box to edit it, drag the top-left handle to move, bottom-right to scale, top-right to delete; **Add Text** adds another
- Star cards; filter the deck to Starred and study only starred cards
- Streak counter (flame banner on the deck list and in the session summary) and a Stats screen: current/best streak, reviewed today, due now, accuracy, study time, a 7-day chart and a new/learning/reviewing/mastered breakdown
- Photos on cards: Add Photo from your library, then move, scale or delete; draw over them with the Pencil. Finger-tap a photo to select it
- Unused photo files (left by deleted cards, decks or photos) are cleaned up automatically at launch and when the app backgrounds; the Stats screen shows photo storage with a manual Clean Up button
- Recently Deleted: deleted cards and decks are kept for 30 days and can be restored or deleted forever (individually or all at once); expired items are purged at launch. An Undo banner also appears right after deleting a card, deck, text box or photo
- Backup and restore: Back Up All Decks (or Export Deck from a deck's long-press menu) saves a single .imstudy file via the share sheet (AirDrop, Save to Files...); Restore from Backup adds its decks as new decks. Includes ink, text, photos and study progress
- Search (deck list): finds cards by typed text and by handwriting. Handwriting is read on-device with Apple's Vision framework in the background and cached on each card, re-read only when the ink changes
- Duplicate a card, and Move or Copy a card to another deck (long-press a card), each with Undo
- Haptic feedback on buttons, card changes, flips and deletes
- Thumbnails show the front with a small preview of the back
- Long-press a card to edit, move earlier/later, or delete
- Spaced-repetition study (Leitner boxes): flip a card, then mark Know It / Don't Know. Known cards come back after 1, 2, 4, 8 then 16 days; missed cards return a few cards later in the session and stay due. Study Due / All / Starred, with due-new-mastered counts on each deck
- Every stroke autosaves to SwiftData
- Rename decks inline

## Not included
iCloud/CloudKit sync needs a paid developer account and the iCloud capability; add a CloudKit
configuration to the model container once that is set up.
