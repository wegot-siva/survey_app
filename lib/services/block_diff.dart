/// One block row as currently stored locally, before an edit is applied.
class ExistingBlock {
  const ExistingBlock({required this.id, required this.label});

  final String id;
  final String label;
}

/// What to do with one position when reconciling a site's stored blocks
/// against the freshly-edited label list from [ManageBlocksScreen].
sealed class BlockDiffOp {
  const BlockDiffOp();
}

/// A brand-new block at [position] — no existing row occupies it.
class InsertBlockOp extends BlockDiffOp {
  const InsertBlockOp({required this.position, required this.label});

  final int position;
  final String label;
}

/// The existing row [id] (currently at [position]) has a new label.
class UpdateBlockOp extends BlockDiffOp {
  const UpdateBlockOp({
    required this.id,
    required this.position,
    required this.label,
  });

  final String id;
  final int position;
  final String label;
}

/// The existing row [id] no longer has a corresponding position in the new
/// list — mark it deleted.
class TombstoneBlockOp extends BlockDiffOp {
  const TombstoneBlockOp({required this.id});

  final String id;
}

/// Reconciles a site's stored blocks (each with a stable id) against a
/// freshly-edited flat label list from the UI, producing the minimal set of
/// per-row operations needed to make storage match — instead of the old
/// delete-all-and-reinsert approach, which had no way to tell a genuinely
/// unchanged block from a deleted-then-recreated one and could resurrect a
/// block another device had already deleted (see Full sync Group 1's
/// blocks-push investigation).
///
/// [ManageBlocksScreen] has no concept of a block's identity beyond its
/// position in the list — a user editing "Block 2"'s text field could mean
/// "fix a typo" or "this is now a different block entirely," and the UI
/// can't distinguish them, nor does it need to. So identity here is
/// necessarily positional: position i's existing row (if any) is treated as
/// "the same block" whose label may have changed; a position beyond the old
/// list's length is a genuinely new block; an old position beyond the new
/// list's length is gone.
///
/// This can misattribute identity under a *middle-of-list* deletion (every
/// row after the deleted one shifts down a position, so the row that ends
/// up "renamed" to the last surviving label isn't the row a human would
/// call the same block) — but block ids are never shown to a user or read
/// by any other feature, so that's invisible and harmless. What matters for
/// correctness is that every row ends up with the right *content* and the
/// right dirty/tombstone state, which this achieves regardless: an
/// unchanged position produces no op at all (never re-dirties untouched
/// content), so a block nobody touched — including one just re-pushed
/// elsewhere and pulled back down — never gets swept up in an unrelated
/// edit's push.
List<BlockDiffOp> diffBlocks(
  List<ExistingBlock> existing,
  List<String> newLabels,
) {
  final ops = <BlockDiffOp>[];
  for (var i = 0; i < newLabels.length; i++) {
    if (i < existing.length) {
      if (existing[i].label != newLabels[i]) {
        ops.add(UpdateBlockOp(id: existing[i].id, position: i, label: newLabels[i]));
      }
    } else {
      ops.add(InsertBlockOp(position: i, label: newLabels[i]));
    }
  }
  for (var i = newLabels.length; i < existing.length; i++) {
    ops.add(TombstoneBlockOp(id: existing[i].id));
  }
  return ops;
}
