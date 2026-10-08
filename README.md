# Flashcards

An iPad flashcard app built with SwiftUI, SwiftData and PencilKit (iOS 17+, iPad only).

## Features
- Multiple decks (deck list with create / delete), each up to 12 cards
- Handwritten cards: draw with Apple Pencil, pan/zoom with fingers (Simulator accepts any input)
- Two-sided cards with a 3D Rotate button to edit front and back
- Thumbnails show the front with a small preview of the back
- Long-press a card to edit, move earlier/later, or delete
- Study mode: tap to flip, previous/next, shuffle
- Every stroke autosaves to SwiftData
- Rename decks inline

## Not included
iCloud/CloudKit sync needs a paid developer account and the iCloud capability; add a CloudKit
configuration to the model container once that is set up.
