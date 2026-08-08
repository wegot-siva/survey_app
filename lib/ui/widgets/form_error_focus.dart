import 'package:flutter/material.dart';

/// Brings the first field that failed validation into view after a save
/// attempt, and focuses it when it can take focus.
///
/// The survey forms validate on save and set a per-field `errorText` (see
/// [AppTextField]/[AppDropdownField]) rather than going through
/// Form/FormField. That already puts the message next to the offending
/// field, but these forms are long — source points alone has 25 required
/// fields — so the field is routinely several screens away from the Save
/// button at the bottom. A failed save then showed only a SnackBar
/// ("Please fill in the required fields"), leaving the user to scroll the
/// whole form hunting for red text. This closes that gap; it does not
/// change what counts as invalid.
///
/// ## Why it walks the tree instead of keying every field
///
/// Every field here ultimately renders an [InputDecorator] carrying the
/// resolved [InputDecoration] — [TextField], [DropdownButtonFormField] and
/// [AppDropdownField]'s empty-state placeholder alike. So the first
/// [InputDecorator] with a non-null `errorText` in depth-first order *is*
/// the topmost error on screen, and depth-first order over a Column is
/// exactly top-to-bottom visual order.
///
/// That means no per-field key registry to declare, pass down, and keep in
/// sync — adding, removing or reordering a field keeps working with no
/// extra wiring, across all five forms.
///
/// ## Requirement on the caller
///
/// The form's scrollable must build all its children. The survey forms use
/// `SingleChildScrollView` + `Column` for precisely this reason: a
/// lazily-built `ListView` leaves off-screen fields out of the element
/// tree, where they are invisible to this walk and unreachable by
/// [Scrollable.ensureVisible] — which is the case that matters most, since
/// the error is usually off-screen when Save is pressed.
class FormErrorFocus {
  const FormErrorFocus._();

  /// Scrolls to the first field under [formRoot] currently showing an
  /// error. No-op when nothing is in error or the form has gone away, so
  /// it's safe to call unconditionally on a failed save.
  static void revealFirst(GlobalKey formRoot) {
    // Deferred to after this frame for two reasons: callers reach here
    // straight after the setState that assigns the new errorText values, so
    // the fields don't carry them until the frame is built; and reading the
    // context inside the callback rather than across an `await` keeps the
    // lookup honest about the tree still existing by then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final root = formRoot.currentContext;
      if (root is! Element) return;

      final target = _firstErrorField(root);
      if (target == null) return;

      Scrollable.ensureVisible(
        target,
        // Just below the top edge rather than flush against it, so the
        // field's own label stays readable and the error doesn't sit under
        // the AppBar's shadow.
        alignment: 0.15,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      _focusFirstEditable(target);
    });
  }

  /// Depth-first (= top-to-bottom) search for a decorated field in error.
  static Element? _firstErrorField(Element root) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is InputDecorator && widget.decoration.errorText != null) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
  }

  /// Focuses the field's text input if it has one, so the user can start
  /// typing straight away. Dropdowns own no [EditableText] and are simply
  /// scrolled to — stealing focus there would pop the menu open uninvited.
  static void _focusFirstEditable(Element field) {
    Element? editable;
    void visit(Element element) {
      if (editable != null) return;
      if (element.widget is EditableText) {
        editable = element;
        return;
      }
      element.visitChildren(visit);
    }

    field.visitChildren(visit);
    final widget = editable?.widget;
    if (widget is EditableText) widget.focusNode.requestFocus();
  }
}
