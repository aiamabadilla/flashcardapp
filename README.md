# Flashcards

An iPad flashcard app built with SwiftUI, SwiftData and PencilKit (iOS 17+, iPad only).

## Features
- Multiple decks (deck list with create / delete), with no limit on cards
- Handwritten cards: draw with Apple Pencil, pan/zoom with fingers (Simulator accepts any input)
- Two-sided cards with a 3D Rotate button to edit front and back
- Previous / Next buttons and a single New Card button inside the editor, so you never have to leave it
- Tap anywhere in the empty slot of the deck grid to add a card
- Dark mode (System / Light / Dark) like Notes: dark paper, ink colors invert
- Per-side lined or blank paper, and typed text on either side
- Star cards; filter the deck to Starred and study only starred cards
- Haptic feedback on buttons, card changes, flips and deletes
- Thumbnails show the front with a small preview of the back
- Long-press a card to edit, move earlier/later, or delete
- Study mode: tap to flip, previous/next, shuffle
- Every stroke autosaves to SwiftData
- Rename decks inline

## Not included
iCloud/CloudKit sync needs a paid developer account and the iCloud capability; add a CloudKit
configuration to the model container once that is set up.
