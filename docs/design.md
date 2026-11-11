# Interface design

gymemo follows Apple's system design with Liquid Glass.
The [Figma file](https://www.figma.com/design/Hid7RVq16U5SizfgMTQRZB/) holds the design system and screens, based on Apple's iOS, iPadOS, macOS, and visionOS kits.
The Watch library refused component imports, so the editable Watch studies document standard SwiftUI controls using Apple's guidance.
Each rule names the Apple page that it applies, read on 2026-11-09 or 2026-11-10, or carries the label of a judgment.

## Foundations

The app builds every screen from standard SwiftUI components.
The [adoption guide](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) says that standard components take the Liquid Glass material when the app builds with the current SDK.
The system draws the tab bar, the toolbars, the sheets, the menus, each `alert`, and the bar over the keyboard.
The app adds no glass effect and no background to a bar or a sheet.
The [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) keeps Liquid Glass out of the content layer and asks apps to use the effect sparingly.
The content sits in inset grouped lists and forms on the grouped background.

Every color is a system color, and the one accent is system indigo.
The accent marks the confirming button of a sheet, the selected tab, the rows that act, the charts, and the symbol of a personal record.
The [color guidance](https://developer.apple.com/design/human-interface-guidelines/color) asks apps to use color sparingly and to color the background of a primary action.
It also asks apps to prefer system colors, which adapt to both appearances and to Increase Contrast.
As text, system indigo reaches 5.1:1 on white and 4.8:1 on a dark row.
The ratios apply the contrast formula of the Web Content Accessibility Guidelines to the values in the same page.
No other system color reaches 4.5:1 on white.
On a dark row inside a sheet, indigo reaches 4.0:1 at the default contrast and 6.5:1 with Increase Contrast.
Destructive actions keep their destructive role.
Set deletion shows a red trash symbol beside text in the label color, because red text failed the contrast check on the sheet's gray row.
A problem also shows a red symbol beside text in the label color.
Unselected text takes the label colors through `Color.primary` and `Color.secondary`, and the Verification section gives the reason.
Selected list rows inherit the system's selection foreground, which keeps their text readable over the selection background.

Text uses the system text styles, so each size follows Dynamic Type.
A set row shows monospaced digits.
The app sets no row height, corner radius, or margin of its own.
The [layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout) asks for standard spacing and for shapes that match their containers.
SF Symbols name each action.
A toolbar item shows its symbol and speaks its title, as the [toolbar guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars) asks.

Logging a set plays the success haptic, and a refused tap plays the error haptic.
The [haptics guidance](https://developer.apple.com/design/human-interface-guidelines/playing-haptics) reserves success for a completed task and asks apps to avoid overuse.
The app adds no animation of its own to frequent actions.

## Tabs

The four tabs are Log, History, Analysis, and Settings, with the symbols `dumbbell.fill`, `clock.fill`, `chart.bar.fill`, and `gearshape.fill`.
The [tab bar guidance](https://developer.apple.com/design/human-interface-guidelines/tab-bars) asks for labels of one word, filled symbols, and tabs that stay visible when their content is empty.
The tab bar keeps its full size while the lifter scrolls.
The choice is a judgment: every tab stays one tap away during a workout.
Each tab opens on a large title, and a pushed screen shows an inline title, as the toolbar guidance asks.

## Log

The Log tab shows today's sets with the date as the subtitle.
One toolbar item with the `plus` symbol adds an exercise.
Each exercise is a section with a prominent header.
The section lists the previous session, each logged set, a weight row, a repetitions row, and a row that logs the set.
The fields start from the last set, so one tap logs the same set again.
The [data entry guidance](https://developer.apple.com/design/human-interface-guidelines/entering-data) asks for choices instead of typing and for sensible defaults.
The weight row shows the decimal pad and the repetitions row shows the number pad.
The [text field guidance](https://developer.apple.com/design/human-interface-guidelines/text-fields) asks for the keyboard that fits the content.
Each row can pair its field with a stepper, which the [stepper guidance](https://developer.apple.com/design/human-interface-guidelines/steppers) suggests beside a text field.
The weight steps by 2.5 kg and the repetitions step by one.
The pads have no return key, so a standard toolbar over the keyboard holds one button that puts the keyboard away.
A number field reserves the clear button's target before focus, so focusing never changes the row's height.
The scroll view centers the focused row when focus or the available keyboard space changes, keeping the clear button outside the keyboard toolbar.
An empty weight shows the prompt Bodyweight and logs a bodyweight set.

A set row opens the set editor on a tap.
Its `swipeActions` offer Delete and Edit, and its `contextMenu` offers the same two actions.
The adoption guide asks that the two sets of actions match.
A problem with an input appears in a row under the fields and says how to fix it.
The [writing guidance](https://developer.apple.com/design/human-interface-guidelines/writing) asks for errors next to the field and for a next step on a blank screen.
The row that logs a set always responds, and a tap with a missing value shows the problem.
The data entry guidance prefers a button that waits for required data, and the app departs from it so that the lifter learns what's missing.
A day without sets shows an empty state with one filled button that adds an exercise.
A note section holds the day's note and a row that edits it.

## Sheets

The exercise picker, the set editor, the note editor, the day picker, and the exercise editor are sheets.
Each sheet has a button with the `xmark` symbol at the leading edge and a filled button with the `checkmark` symbol at the trailing edge.
The [sheet guidance](https://developer.apple.com/design/human-interface-guidelines/sheets) puts Cancel at the leading edge and Done at the trailing edge.
The toolbar guidance reserves the prominent style for one key action at the trailing side.
The set editor opens at the medium height with a grabber, as the sheet guidance suggests for an iPhone.
A sheet closes when the lifter drags it down.
A sheet with unsaved changes asks before it closes and offers Discard Changes and Keep Editing.

The exercise picker lists the recent exercises first and then each body part.
Its search field sits at the bottom, where the [search guidance](https://developer.apple.com/design/human-interface-guidelines/search-fields) places it when there is room.
A toolbar item with the `plus` symbol pushes the form for a new exercise inside the same sheet.

## History

The History tab lists the training days under a header for each month, newest first.
A row shows the date, the exercises with the number of sets, and the start of the note.
A toolbar item with the `calendar.badge.plus` symbol opens the day picker, which shows a calendar.
A past day uses the same screen as the Log tab, with a row that says the day isn't today.
An empty history shows an empty state with a button that starts today's log.

## Analysis

The Analysis tab shows the training days of each of the last 12 weeks and one row for each exercise.
A sentence before the bar chart states the two newest values.
An exercise opens its progress: a range control, a line chart, the personal records, and the sets of each day.
The range control is a segmented control with three ranges.
The [segmented control guidance](https://developer.apple.com/design/human-interface-guidelines/segmented-controls) limits a control to about five segments of one kind.
Each chart shows one measure in the accent color and gives each mark a spoken label and value.
The [charting guidance](https://developer.apple.com/design/human-interface-guidelines/charting-data) asks for simple charts, descriptive text, and accessibility labels.
The bars start at zero, and the list under the line chart gives every value as text.

## Settings

The Settings tab links to exercises, export and import, and the local privacy policy, and states where records stay.
On iPhone and iPad, it also explains paired Apple Watch transfer.
On iPhone, iPad, and Vision Pro, a standard `Link` opens the Shortcuts app using Apple's [documented URL scheme](https://support.apple.com/guide/shortcuts/apda283236d7/ios).
The row grows with Dynamic Type.
On the iOS 26 simulator, `ShortcutsLink` and `ShortcutsUIButton` failed the largest-text-size audit, so the app uses the standard text link.
The exercise list groups the exercises by body part and marks a hidden one.
The exercise editor holds the name, the body part in a menu, a switch that shows the exercise in the picker, and a Delete button for an unused exercise.
The export and import screen has one row for each action, with a footer that explains it.
The result of an action appears in a row at the top.
The export document stays alive independently of the presentation binding until completion.
The [export API](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:)) resets that binding before invoking its completion handler.

## Confirmation

Replacing the log with a backup shows an `alert` with Cancel and a destructive Replace.
The [guidance for the `alert`](https://developer.apple.com/design/human-interface-guidelines/alerts) reserves it for uncommon destructive actions that a person can't undo.
Deleting one set shows no `alert`.
The same page asks apps to avoid one for common actions, even destructive ones.
Committed changes register bounded snapshots with the native window's `UndoManager`.
Undo covers deleted records and imported backups.
Incoming Watch changes and edits in another window invalidate snapshots that could overwrite those records.
Deleting an unused exercise asks in a confirmation that opens from the Delete button.
The adoption guide asks for an action sheet that starts at the control behind it.

## Estimated one-repetition load

The estimate is the weight times one plus the repetitions over 30, and a single repetition keeps its weight.
The form follows the Epley equation as [Beia and colleagues](https://doi.org/10.3390/sports12090233) list it, where the printed coefficient of 0.333 contradicts the paper's own results.
The app uses 0.0333, and no source read for the project confirms that value.
The same paper found predictions most accurate from five to eight repetitions and found overestimates.
The screens call the value an estimate and a rough guide for that reason.

## Languages and text size

English, Japanese, Simplified Chinese, and Traditional Chinese come from one String Catalog.
English titles, buttons, and section headers use title-style capitalization, and explanations use sentence style.
The adoption guide asks for title-style section headers.
Dates follow the calendar and order of the device's region, and weights use its decimal separator.
The starter exercises take their names from the device language at the first launch.
No native speaker has reviewed the Chinese text.

Rows hold text that wraps instead of truncating.
At the accessibility text sizes, a set row moves its personal record mark under the set, and a number row stacks its label, its field, and its stepper.
At those sizes the range control becomes a menu, and each chart shows fewer dates under its axis.
The [typography guidance](https://developer.apple.com/design/human-interface-guidelines/typography) asks for layouts that adapt to every text size.
The weight unit moves beside the heading at accessibility sizes, leaving the field enough width for its Bodyweight prompt.
The [text field guidance](https://developer.apple.com/design/human-interface-guidelines/text-fields) places the clear button at the field's trailing edge.
At accessibility sizes, the clear button moves to the trailing edge of the next row so the value and its Bodyweight prompt have the full width.
The adaptation follows the typography guidance to stack inline controls when larger text crowds the field.

## Native destinations

One SwiftUI target serves iPhone, iPad, Mac, and Vision Pro through [native supported destinations](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target).
The main tabs use the [adaptive sidebar style](https://developer.apple.com/documentation/swiftui/sidebaradaptabletabviewstyle).
History and Analysis use `NavigationSplitView` with typed selections, so wider windows show a list beside its detail and compact windows navigate to the detail.
The structure follows Apple's [iPhone Duo guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) to adapt to the available space and preserve state.
Mac uses native menus, window undo, keyboard commands, and sandboxed system file pickers, following [Mac design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).
Vision Pro uses a resizable shared-space window and standard gaze and pinch controls, following [visionOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-visionos).
The app introduces no immersive space, head-anchored content, or spatial motion.

Apple Watch uses a separate native target with an exercise list, a set entry screen, and a delivery list.
Recent exercises lead the bounded catalog from iPhone.
Standard steppers show body-style values, and the Digital Crown scrolls the list.
The primary action supports the [double-tap hand gesture](https://developer.apple.com/documentation/swiftui/handgestureshortcut/primaryaction).
Saving keeps the set locally, gives success feedback, and scrolls to persistent delivery status.
The interface distinguishes pending, committed, and refused records with words and symbols.
The [Watch guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos) calls for short interactions and shallow navigation.
The owner chose paired iPhone storage, so the Watch target requires its companion instead of adopting Apple's recommendation for an independent app.

The app-specific accessibility behavior and verification boundaries are in [Accessibility](accessibility.md).

## Verification

`mise x -- just check` runs the source check for the rules of this page, the package tests, and the build.
The source check refuses a color written in code, a background on a bar or a sheet, a glass effect, and a fixed appearance.
It also refuses a fixed font size, a modifier that cuts text short, and a hierarchical style such as `.secondary`.
A hierarchical style derives from the style around it.
On the iOS 27.0 simulator, `.primary` took the accent inside a button.
With Increase Contrast, `.secondary` stayed at 4.0:1 on a white row, where `Color.secondary` reached 6.0:1.

`mise x -- just ui-test` drives every screen and runs the system's accessibility audit on each one.
The tours cover four languages in the light appearance, the largest text size in English and Japanese, and the dark appearance.
Two more tours run with Increase Contrast, one in each appearance.
`simctl` switches the appearance and Increase Contrast around each pass.

The tours at the default contrast leave the contrast audit out.
The system draws secondary text, section headers, and footers under 4.5:1 by default.
Apple's Settings app got 11 contrast reports on its About screen at the default contrast and none with Increase Contrast.
The [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility) asks an app in that position to reach its contrast ratios with Increase Contrast.
The same page asks for the check in both appearances.
The two tours with Increase Contrast audit the contrast of every element that the audit names.
The set editor's Weight, Reps, kg, and Delete Set labels also have a narrow image check for reports that contradict their rendered primary color.
The check measures the unrounded [contrast ratio defined by the Web Content Accessibility Guidelines](https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio) in the reported label's screenshot bounds and requires at least 4.5:1.
It refuses missing ink, an ambiguous or colored background, and nonopaque pixels.
The image check applies only to the four identified primary labels on the set editor, not to arbitrary text, images, or material backgrounds.
On iOS 26.4, the largest-size audit also reports the fully visible English Bodyweight placeholder as clipped.
The empty-weight scenario measures its rounded-up bounds with the [system body font](https://developer.apple.com/documentation/uikit/uifont/preferredfont(fortextstyle:compatiblewith:)) at that exact accessibility size.
The check accepts that identified placeholder only when its measured width and height fit inside the field.
The scenarios keep screenshots for visual review, and the measurement fixtures reject the narrower field from the original layout.

Each remaining exclusion rests on an observation of 2026-11-09 on the iOS 27.0 simulator.
A contrast report without an element names no view, and neither the test nor Xcode finds one.
Settings gets such reports with Increase Contrast too.
This app got 11 in the light appearance, and the number stayed the same when a trial build exposed every text that the app merges or hides.
The audit reports partial Dynamic Type support for the calendar of the day picker and for some text in system styles.
Settings gets that report for its own title.
Text under the tab bar or the search field fails the contrast audit through the bar's material.
The header of the set editor lies on the sheet's material under the sheet's bar and fails the contrast audit.
A screenshot with Increase Contrast shows 5.5:1 for that header.
The audit of clipped text runs only at the largest text size.
At a smaller size it predicts clipping for headers and footers that the largest size shows whole.
The audit accepts text without an element on four screens, where the system draws a chart axis, a calendar, or the screen under a sheet.

The iOS 26.0 checks remain incomplete while its simulator renders Chinese characters as squares.
`FontTests` checks the system fonts with Core Text before screenshots can count as localization verification.
Passing accessibility labels alone doesn't establish that the corresponding characters render.
On iOS 26.4, the font preflight and the Settings audit at the largest text size pass in all four languages.
No automated check covers Reduce Transparency or Reduce Motion, because `simctl` switches neither.
One look at the Log tab with the simulator's Reduce Transparency preference showed opaque bars and readable content.
