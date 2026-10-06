#if DEBUG
// design-lint: allow-file spacing-literal,radius-literal,opacity-literal,frame-literal gallery-sample — sample content, not chrome
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Wave 3: inputs and forms.
extension ComponentGalleryView {
    var wave3Section: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Inputs · Forms", subtitle: "Wave-3 selection, input, and form controls")

            wave3SelectionRow
            wave3ChoiceRow
            wave3NumericRow
            wave3TextRow
            wave3RestyledRow
            wave3FormRowSample
        }
    }

    private var wave3SampleItems: [String] { ["Option A", "Option B", "Option C"] }

    private var wave3SearchableSelectItems: [String] {
        [
            "Alabama", "Alaska", "Arizona", "Arkansas", "California",
            "Colorado", "Connecticut", "Delaware", "Florida", "Georgia",
        ]
    }

    private var wave3SelectionRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption(
                "Select, MultiSelect, Combobox, SearchableSelect — dropdowns now ALWAYS search; panel width ≥ field width"
            )
            HStack(alignment: .top, spacing: AinkradSpacing.md) {
                // Wide field + long list: opening it shows the search field and
                // a panel floored to this 260pt field width.
                AinkradSelect(items: wave3SearchableSelectItems, selection: $wave3SelectSelection) { $0 }
                    .frame(width: 260)
                AinkradMultiSelect(items: wave3SampleItems, selection: $wave3MultiSelectSelection) { $0 }
                AinkradCombobox(
                    items: wave3SampleItems,
                    selection: $wave3ComboboxSelection,
                    text: $wave3ComboboxText
                ) { $0 }
                // Narrow field: panel floors to this 110pt width (content wider
                // than that still wins), and AinkradSearchableSelect is now just
                // an alias of the always-searchable AinkradSelect.
                AinkradSearchableSelect(
                    items: wave3SearchableSelectItems,
                    selection: $wave3SearchableSelectSelection,
                    label: { $0 },
                    placeholder: "Search states…"
                )
                .frame(width: 110)
            }
        }
    }

    private var wave3ChoiceRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Checkbox, Radio Group")
            HStack(alignment: .top, spacing: AinkradSpacing.lg) {
                AinkradCheckbox(isOn: $wave3CheckboxOn, label: "Enable feature")
                AinkradRadioGroup(options: wave3SampleItems, selection: $wave3RadioSelection) { $0 }
            }
        }
    }

    private var wave3NumericRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Stepper, Range Slider")
            HStack(alignment: .top, spacing: AinkradSpacing.lg) {
                AinkradStepper(value: $wave3StepperValue, in: 0...10)
                AinkradRangeSlider(range: $wave3RangeSliderValue, bounds: 0...1)
            }
        }
    }

    private var wave3TextRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Search Field, Text Area")
            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                AinkradSearchField(text: $wave3SearchText, placeholder: "Search…")
                AinkradTextArea(text: $wave3TextAreaText, placeholder: "Text area")
            }
        }
    }

    private var wave3RestyledRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Restyled: Text Field, Secure Field, Toggle, Segmented Picker, Slider")
            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                AinkradTextField(text: $wave3TextFieldText, placeholder: "Text field")
                AinkradSecureField(text: $wave3SecureFieldText, placeholder: "Secure field")
                HStack(spacing: AinkradSpacing.lg) {
                    AinkradToggle(isOn: $wave3ToggleOn)
                    AinkradSegmentedPicker(items: Array(0..<3), selection: $wave3SegmentedSelection) { "Item \($0)" }
                }
                AinkradSlider(value: $wave3SliderValue, in: 0...1)
            }
        }
    }

    private var wave3FormRowSample: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Form Row")
            AinkradFormRow(title: "Enable feature", help: "A checkbox in a form row") {
                AinkradCheckbox(isOn: $wave3CheckboxOn)
            }
        }
    }
}
#endif
