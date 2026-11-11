# Accessibility

The owner adopts applicable recommendations in Apple's [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility) as release criteria.
The scope covers recording, editing, navigation, history, analysis, backup files, privacy, and paired Watch records.
The app has no speech, media, camera capture, or authored animation, so captions, audio description, flashing-content controls, and media playback alternatives don't apply.

## Reading and feedback

System text styles follow supported text-size settings.
Rows wrap, number controls stack at accessibility sizes, and chart ranges become a menu when segments can't grow.
System colors and native selection foregrounds adapt to appearance and contrast settings.
Information never depends on color, sound, or haptics alone.
Saving and validation failures remain visible, and important changes post spoken announcements.
No notice disappears on a timer.

The [VoiceOver guidance](https://developer.apple.com/design/human-interface-guidelines/voiceover) governs control labels, grouping, headings, and updates.
Set rows speak their number, load, repetitions, and record status.
Repeated number controls and logging buttons include the exercise name for VoiceOver and Voice Control.
Steppers expose their current value.
Chart marks speak dates and values, and adjacent text supplies summaries and recorded sets.

## Alternative input

Standard buttons, text fields, steppers, pickers, menus, and navigation provide the system's keyboard, switch, Voice Control, and AssistiveTouch behavior where each platform supports them.
Each row action also has a context-menu entry.
Mac supports Command-1 through Command-4, native Undo and Redo, Return to confirm, and Escape to cancel.
Watch logging exposes the primary hand gesture and tap controls, and its lists support the Digital Crown.
Vision Pro uses standard window controls and no custom gestures.

## Guided logging

iOS declares `UISupportsAssistiveAccess` and supplies a native `AssistiveAccess` scene, following Apple's [optimization guide](https://developer.apple.com/documentation/accessibility/optimizing-your-app-for-assistive-access).
The simplified core task chooses an exercise, enters weight, enters repetitions, reviews the set, and confirms storage.
Typed routes carry the selected exercise and validated values between steps.
The saved screen stays visible until the person logs another set or finishes.
The guided flow doesn't expose deletion or backup replacement.
The debug launch flag exercises the guided views without changing the simulator's system mode.

## Verification boundaries

The [verification guide](verification.md) names the maintained commands and what they establish.
Automated audits supplement inspection of screenshots, spoken labels, and native controls.
Simulator runs don't establish actual Assistive Access system presentation, switch scanning, spoken Voice Control recognition, or hardware comfort.
App Store accessibility declarations must reflect completed platform-specific acceptance, following Apple's [accessibility-label guidance](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/).
