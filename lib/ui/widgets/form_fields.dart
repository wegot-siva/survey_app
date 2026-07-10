import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable form field widgets, shared across survey forms (Source points now,
/// Inlet points next slice) so spacing/decoration stay consistent.

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.errorText,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// Shown below the field in the error color, e.g. "Required" — set by the
  /// caller after a failed save attempt on a mandatory field.
  final String? errorText;

  /// Lets a caller drive focus (e.g. auto-focusing a pre-filled field for
  /// review right after it opens) — optional, unused unless supplied.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: errorText,
        ),
      ),
    );
  }
}

class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.emptyHint,
    this.errorText,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;

  /// Shown (disabled) when [items] is empty, e.g. "Add blocks first".
  final String? emptyHint;

  /// Shown below the field in the error color, e.g. "Required" — set by the
  /// caller after a failed save attempt on a mandatory field.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && emptyHint != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            errorText: errorText,
          ),
          child: Text(
            emptyHint!,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: errorText,
        ),
        items: [
          for (final item in items)
            DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// A wrap of [FilterChip]s for picking a set of values (mirrors the water
/// sources picker on Client inputs). When [items] is empty, shows [emptyHint].
class MultiSelectChips<T> extends StatelessWidget {
  const MultiSelectChips({
    super.key,
    required this.label,
    required this.items,
    required this.itemLabel,
    required this.selected,
    required this.onChanged,
    this.emptyHint,
    this.helperText,
    this.errorText,
  });

  final String label;
  final List<T> items;
  final String Function(T) itemLabel;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;

  /// Shown when [items] is empty, e.g. "Add inlet points first".
  final String? emptyHint;

  /// Optional advisory text under the chips, e.g. "Max 20 sensors per unit".
  final String? helperText;

  /// Shown below the chips in the error color, e.g. "Select at least one" —
  /// set by the caller after a failed save attempt on a mandatory field.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              emptyHint ?? 'No options available.',
              style: TextStyle(color: Theme.of(context).hintColor),
            )
          else
            Wrap(
              spacing: 8,
              children: [
                for (final item in items)
                  FilterChip(
                    label: Text(itemLabel(item)),
                    selected: selected.contains(item),
                    onSelected: (sel) {
                      final next = {...selected};
                      if (sel) {
                        next.add(item);
                      } else {
                        next.remove(item);
                      }
                      onChanged(next);
                    },
                  ),
              ],
            ),
          if (helperText != null) ...[
            const SizedBox(height: 6),
            Text(
              helperText!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 6),
            Text(
              errorText!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class YesNoField extends StatelessWidget {
  const YesNoField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.labelTrailing,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  /// Optional widget shown to the right of the label, e.g. a [ReferenceLink].
  final Widget? labelTrailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              ?labelTrailing,
            ],
          ),
          const SizedBox(height: 4),
          SegmentedButton<bool>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Yes')),
              ButtonSegment(value: false, label: Text('No')),
            ],
            selected: value == null ? const {} : {value!},
            onSelectionChanged: (sel) =>
                onChanged(sel.isEmpty ? null : sel.first),
          ),
        ],
      ),
    );
  }
}

/// Disabled placeholder for a photo capture field (camera arrives in a later
/// phase). Renders a greyed-out button so the field is visible but inert.
class DisabledPhotoField extends StatelessWidget {
  const DisabledPhotoField({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.photo_camera_outlined),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text('$label (photo — coming soon)'),
        ),
      ),
    );
  }
}

class FormSectionLabel extends StatelessWidget {
  const FormSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// A small tappable "view reference" link that opens [asset] full-screen so the
/// engineer can compare a figure against the field. Reference only — nothing is
/// captured or saved.
class ReferenceLink extends StatelessWidget {
  const ReferenceLink({super.key, required this.asset, required this.title});

  /// Asset path, e.g. `assets/figures/FIG1_pipe_full_outlet_above.png`.
  final String asset;

  /// Short label shown on the link and in the viewer app bar, e.g. `FIG1`.
  final String title;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _ReferenceImageScreen(asset: asset, title: title),
        ),
      ),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, size: 18),
            const SizedBox(width: 4),
            Text(
              'View $title',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceImageScreen extends StatelessWidget {
  const _ReferenceImageScreen({required this.asset, required this.title});

  final String asset;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      backgroundColor: Colors.black,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Reference image not found.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
