import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme.dart';
import 'card_grid.dart';

/// A drag-reorderable responsive grid/list, built in-house (no package).
///
/// Long-press an item and it follows the finger; the others animate cleanly to
/// their new slots (one persistent element per item, so an item moving between
/// rows glides between positions rather than fading out/in); on release the
/// dragged item animates into its final slot. Reorder triggers as the pointer
/// crosses INTO a cell, not past its centre.
///
/// Columns come from the available width ([minColumnWidth] up to [maxColumns]),
/// so this is ONE widget for every width: a single column on a phone (a
/// reorderable list) and 2–3 columns when wide.
///
/// **All items are assumed to be the same height.** It's measured from the first
/// item at the current column width (never hardcoded) and used for row spacing;
/// cards self-size (no forced height), so an item taller/shorter than the first
/// would overlap the next row / leave a gap — keep items uniform.
///
/// ponytail: no edge auto-scroll while dragging — add it only if a real list
/// grows past the viewport.
class ReorderableCardGrid<T> extends StatefulWidget {
  final List<T> items;

  /// Stable identity per item — used to keep an item's element (and its
  /// animation) attached to it as it moves, and to reconcile external changes.
  final Object Function(T item) idOf;

  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Reports a completed drag as data indices into [items] (as
  /// `ReorderableListView.onReorder`: insert-style — `newIndex` is the final
  /// position after removal).
  final void Function(int oldIndex, int newIndex) onReorder;

  final double minColumnWidth;
  final int maxColumns;
  final double spacing;
  final EdgeInsets padding;

  const ReorderableCardGrid({
    super.key,
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    required this.onReorder,
    this.minColumnWidth = 360,
    this.maxColumns = 3,
    this.spacing = kCardGap,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<ReorderableCardGrid<T>> createState() => _ReorderableCardGridState<T>();
}

class _ReorderableCardGridState<T> extends State<ReorderableCardGrid<T>> {
  static const _anim = Duration(milliseconds: 240);

  final _stackKey = GlobalKey();

  /// Visual order — mirrors [widget.items], but reorders live during a drag.
  late List<T> _order = [...widget.items];

  Object? _dragId; // id of the item under the finger, or null
  Object? _droppingId; // id still animating into its slot after release
  int _dropToken = 0; // bumped per drop, so a stale cleanup timer no-ops
  Offset _pointer = Offset.zero; // finger position in stack-local coords
  Offset _grab = Offset.zero; // finger offset within the grabbed item

  double? _cellH; // measured item height
  // Last laid-out cell size — lets us tell a resize / column switch (snap, no
  // size tween → no transient overflow) from a reorder move (animate).
  double? _prevCellW;
  double? _prevCellH;

  @override
  void didUpdateWidget(ReorderableCardGrid<T> old) {
    super.didUpdateWidget(old);
    // Adopt external changes (add / delete / apply) only when not mid-drag.
    if (_dragId == null && !_sameOrder(_order, widget.items)) {
      _order = [...widget.items];
    }
  }

  bool _sameOrder(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (widget.idOf(a[i]) != widget.idOf(b[i])) return false;
    }
    return true;
  }

  Offset _toStack(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  int _slotFromPointer(Offset p, int cols, double cellW, double cellH, int n) {
    final rows = (n / cols).ceil();
    final col = (p.dx / (cellW + widget.spacing)).floor().clamp(0, cols - 1);
    final row = (p.dy / (cellH + widget.spacing)).floor().clamp(0, rows - 1);
    return (row * cols + col).clamp(0, n - 1);
  }

  void _startDrag(T item, Offset slot, Offset global) {
    final local = _toStack(global);
    setState(() {
      _dragId = widget.idOf(item);
      _pointer = local;
      _grab = local - slot;
    });
  }

  void _moveDrag(Offset global, int cols, double cellW) {
    final local = _toStack(global);
    final cur = _order.indexWhere((it) => widget.idOf(it) == _dragId);
    if (cur < 0) return;
    final tgt =
        _slotFromPointer(local, cols, cellW, _cellH ?? 0, _order.length);
    setState(() {
      _pointer = local;
      if (tgt != cur) _order.insert(tgt, _order.removeAt(cur));
    });
  }

  void _endDrag() {
    final id = _dragId;
    if (id == null) return;
    final from = widget.items.indexWhere((it) => widget.idOf(it) == id);
    final to = _order.indexWhere((it) => widget.idOf(it) == id);
    final token = ++_dropToken;
    setState(() {
      _dragId = null; // triggers the drop-into-slot animation
      _droppingId = id; // ...but keep it painted on top until it lands
    });
    if (from >= 0 && to >= 0 && from != to) widget.onReorder(from, to);
    // Only drop the "on top" flag once THIS drop's animation has finished, so
    // the z-order never flickers mid-flight — the token guards against a fast
    // re-drag whose timer would otherwise clear the new drop early.
    Future.delayed(_anim, () {
      if (mounted && _dropToken == token) setState(() => _droppingId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final avail = c.maxWidth - widget.padding.horizontal;
        final (columns: cols, cellWidth: cellW) = gridColumns(
          avail,
          minColumnWidth: widget.minColumnWidth,
          maxColumns: widget.maxColumns,
          spacing: widget.spacing,
        );

        // Invisible probe that measures a real item at the current width. Lives
        // in the Stack so it's always laid out; opacity 0 + IgnorePointer keep
        // it unseen and inert. Re-measures when the width (→ its height) changes.
        final measurer = Positioned(
          left: 0,
          top: 0,
          width: cellW,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0,
              child: _MeasureSize(
                onChange: (s) {
                  if (_cellH != s.height) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _cellH = s.height);
                    });
                  }
                },
                child: widget.itemBuilder(context, widget.items.first),
              ),
            ),
          ),
        );

        // Only the FIRST frame (height not yet measured) falls back to a plain
        // Wrap — laid out identically, so the swap to the grid is seamless. On
        // resize we keep the grid up with the last height and just re-measure,
        // so there's no Wrap↔grid flicker.
        if (_cellH == null) {
          return SingleChildScrollView(
            padding: widget.padding,
            child: Stack(
              children: [
                measurer,
                Wrap(
                  spacing: widget.spacing,
                  runSpacing: widget.spacing,
                  children: [
                    for (final it in _order)
                      SizedBox(
                          width: cellW,
                          child: widget.itemBuilder(context, it)),
                  ],
                ),
              ],
            ),
          );
        }

        final cellH = _cellH!;
        final n = _order.length;
        final rows = (n / cols).ceil();
        final totalH = rows * (cellH + widget.spacing) - widget.spacing;
        Offset slot(int d) => Offset(
              (d % cols) * (cellW + widget.spacing),
              (d ~/ cols) * (cellH + widget.spacing),
            );

        // A change in cell size = a resize / column switch: snap everyone (no
        // size tween, which would briefly overflow the card). A reorder keeps
        // the size and only moves items, so that still animates.
        final resized = _prevCellW != cellW || _prevCellH != cellH;
        _prevCellW = cellW;
        _prevCellH = cellH;
        // Whichever card is being dragged OR still dropping stays painted last.
        final topId = _dragId ?? _droppingId;
        final topIdx =
            topId == null ? -1 : _order.indexWhere((it) => widget.idOf(it) == topId);

        return SingleChildScrollView(
          padding: widget.padding,
          child: SizedBox(
            key: _stackKey,
            height: totalH,
            child: Stack(
              // Don't clip a card dragged past the last row / into empty space.
              clipBehavior: Clip.none,
              children: [
                measurer,
                for (var d = 0; d < n; d++)
                  if (d != topIdx) _cell(d, cols, cellW, slot(d), resized),
                // Dragged / dropping card painted LAST → always on top.
                if (topIdx >= 0) _cell(topIdx, cols, cellW, slot(topIdx), resized),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Screen-reader reorder actions (drag is pointer-only). Same labels
  /// `ReorderableListView` uses (`MaterialLocalizations`, no new strings). Only
  /// while idle — `d` is then the data index, which is what onReorder wants.
  Map<CustomSemanticsAction, VoidCallback> _reorderActions(
      BuildContext context, int d) {
    if (_dragId != null) return const {};
    final ml = Localizations.of<WidgetsLocalizations>(
        context, WidgetsLocalizations)!;
    final n = _order.length;
    return {
      if (d > 0)
        CustomSemanticsAction(label: ml.reorderItemToStart): () =>
            widget.onReorder(d, 0),
      if (d > 0)
        CustomSemanticsAction(label: ml.reorderItemUp): () =>
            widget.onReorder(d, d - 1),
      if (d < n - 1)
        CustomSemanticsAction(label: ml.reorderItemDown): () =>
            widget.onReorder(d, d + 1),
      if (d < n - 1)
        CustomSemanticsAction(label: ml.reorderItemToEnd): () =>
            widget.onReorder(d, n - 1),
    };
  }

  Widget _cell(int d, int cols, double cellW, Offset slot, bool resized) {
    final item = _order[d];
    final dragging = widget.idOf(item) == _dragId;
    var pos = dragging ? _pointer - _grab : slot;
    // Single column: lock X to the column so the card can't drift sideways.
    if (dragging && cols <= 1) pos = Offset(slot.dx, pos.dy);
    return AnimatedPositioned(
      key: ValueKey(widget.idOf(item)),
      // The dragged item tracks the finger 1:1 (no lag); everyone else animates
      // to their slot. On release `dragging` flips false, so the ex-dragged item
      // animates from the finger to its slot — the drop. A resize snaps (see
      // above) so sizes never tween.
      duration: (dragging || resized) ? Duration.zero : _anim,
      curve: Curves.easeInOut,
      left: pos.dx,
      top: pos.dy,
      width: cellW,
      // No forced height: the card self-sizes, so a stale measured height (one
      // frame behind a width change / chip re-wrap) can never overflow it. The
      // measured height is used only for row spacing (`slot`).
      child: Semantics(
        container: true,
        customSemanticsActions: _reorderActions(context, d),
        child: GestureDetector(
          onLongPressStart: (e) => _startDrag(item, slot, e.globalPosition),
          onLongPressMoveUpdate: (e) => _moveDrag(e.globalPosition, cols, cellW),
          onLongPressEnd: (_) => _endDrag(),
          onLongPressCancel: _endDrag,
          child: Material(
            type: MaterialType.transparency,
            elevation: dragging ? 8 : 0,
            child: widget.itemBuilder(context, item),
          ),
        ),
      ),
    );
  }
}

/// Reports its child's laid-out size via [onChange] (fires during layout, so
/// callers should defer any setState to a post-frame callback).
class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;
  const _MeasureSize({required this.onChange, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRender(onChange);

  @override
  void updateRenderObject(BuildContext context, _MeasureSizeRender obj) =>
      obj.onChange = onChange;
}

class _MeasureSizeRender extends RenderProxyBox {
  _MeasureSizeRender(this.onChange);
  ValueChanged<Size> onChange;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final s = child?.size ?? Size.zero;
    if (s != _last) {
      _last = s;
      onChange(s);
    }
  }
}
