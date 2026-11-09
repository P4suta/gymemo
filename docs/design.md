# Interface design

gymemo has four tabs, named Log, History, Analysis, and Settings.
Each rule names the Apple page that it applies, read on 2026-11-09, or carries the label of a judgment.

## Structure

The four tabs carry one-word labels and icons, and an empty tab stays visible with guidance inside it.
The [tab bar guidance](https://developer.apple.com/design/human-interface-guidelines/tab-bars) asks for labels, for single words where possible, and for tabs that stay visible when their content is unavailable.

The Log tab offers choices before typing.
The lifter picks an exercise from a list, and the weight and repetitions start from the previous set.
The [data entry guidance](https://developer.apple.com/design/human-interface-guidelines/entering-data) asks for choices instead of text entry and for reasonable default values.
The weight field shows the decimal pad and the repetitions field shows the number pad, and each field has a visible label.
A field that holds text ends with a button that clears it.
The [text field guidance](https://developer.apple.com/design/human-interface-guidelines/text-fields) asks for the keyboard type that fits the content and for a clear button at the trailing end.

The History tab shows the 20 newest days and adds older days on request.
Its rows and the rows of the other lists draw at once instead of on demand, so each row keeps its size at every text size.

A problem with an input appears beside the fields and says how to fix it.
The [writing guidance](https://developer.apple.com/design/human-interface-guidelines/writing) asks for errors next to the field, for verbs on buttons, and for a next step on a blank screen.
Buttons always respond, because a button that ignores taps would draw a faded state that the visual rules exclude.

## Confirmation

Replacing the log with a backup shows an `alert`, and its cancel button reads Cancel in each language.
The [guidance for the `alert`](https://developer.apple.com/design/human-interface-guidelines/alerts) reserves it for uncommon destructive actions that a person can't undo, and asks for a button titled Cancel.
Deleting one set shows no `alert`.
The same page asks apps to avoid one for common, undoable actions.
A deleted set has no undo, so the choice is a judgment: the lifter can log the same set again with one button.
Deleting an unused exercise asks through an action sheet, which the same page prefers for choices that follow an intentional action.

## Visual rules

The screens draw with two colors: the surface and the ink.
The two colors are white and black in the light appearance and black and white in the dark one.
The app follows the system appearance and offers no setting of its own, as the [Dark Mode guidance](https://developer.apple.com/design/human-interface-guidelines/dark-mode) asks.
The app's own drawing excludes gray steps, opacity, gradients, shadows, and translucent surfaces.
Size, weight, spacing, solid rules, and solid frames carry the hierarchy.
A selected option shows a filled mark or a filled button, and a personal record shows a framed label.
The system draws the tab bar, the navigation bar, the keyboard, the file pickers, the date picker, and each `alert`, and the app leaves each of them unchanged.
The content of a screen ends at a rule over the tab bar, and the navigation bar has a solid surface.
No text shows through a translucent bar as a result.

Each control has an icon and a visible label.
Controls are at least 44 points tall, and text uses the system text styles so that Dynamic Type applies.
Rows that hold two or more values stack them at the accessibility text sizes.
The [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility) gives the 44-point control size, asks for text that enlarges, and asks apps to convey information with more than color.

## Charts

Each chart shows one measure, has a sentence that states its main value, and gives each mark a spoken label and value.
The [charting guidance](https://developer.apple.com/design/human-interface-guidelines/charting-data) asks for simple charts, descriptive text, and accessibility labels.
The weekly chart draws one bar for each of the last 12 weeks, and the progress chart draws one line with a point for each day.
Both use the ink alone, without grid lines, and a list under the progress chart gives every value as text.
The charts take no selection or hover, because the list already gives the detail.
A color palette check has nothing to examine, because the charts hold one series in one color.

## Estimated one-repetition load

The estimate is the weight times one plus the repetitions over 30, and a single repetition keeps its weight.
The form follows the Epley equation as [Beia and colleagues](https://doi.org/10.3390/sports12090233) list it, where the printed coefficient of 0.333 contradicts the paper's own results.
The app uses 0.0333, and no source read for the project confirms that value.
The same paper found predictions most accurate from five to eight repetitions and found overestimates.
The screens call the value an estimate and a rough guide for that reason.

## Languages

English, Japanese, Simplified Chinese, and Traditional Chinese come from one String Catalog.
Dates follow the calendar and order of the device's region, and weights use its decimal separator.
English counts take the singular and the plural form.
The starter exercises take their names from the device language at the first launch.
No native speaker has reviewed the Chinese text.

## Verification

`mise x -- just check` runs the source checks for colors, literals, and the other rules, with a planted violation for each.
`mise x -- just ui-test` runs the scenarios and the accessibility audit of each screen.
The audit runs in the light appearance, the dark appearance, the largest text size, and each language.
The audit leaves out three kinds of findings that the app can't change.
The first is the day numbers and the header of the system's date picker, which keep one size.
The second is the axis labels of the charts, whose values each mark repeats as its spoken label.
The third is a contrast finding on text that an edge of its scroll view cuts through, which fails at any colors.
`mise x -- just screenshots` exports the screenshots that the tests kept.
