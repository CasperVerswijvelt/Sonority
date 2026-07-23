import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
/// Rows are spaced by the TALLEST measured item (dynamic, never hardcoded), so
/// cards of differing height never overlap — a shorter card just leaves a little
/// slack in its slot. Dragging near the top/bottom edge auto-scrolls the list.
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

  /// When true, items drag immediately (no long-press) and their content is
  /// inert (the caller shows a drag affordance instead). When false, there is no
  /// drag gesture and items are fully interactive. Screen-reader reorder actions
  /// are available in both cases.
  final bool reordering;

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
    this.reordering = false,
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

  // Measured natural height per item id. The uniform row height is the MAX of
  // these, so cards of differing height (a long name, chips that wrap to a
  // second line at narrow columns) never overlap — a shorter card just leaves a
  // little space in its slot. Never hardcoded; re-measured live.
  final Map<Object, double> _heights = {};
  double? _cellH; // cached max height (for _moveDrag hit-testing)
  // Last laid-out cell size — lets us tell a resize / column switch (snap, no
  // size tween → no transient overflow) from a reorder move (animate).
  double? _prevCellW;
  double? _prevCellH;

  // Current grid geometry, cached so the drag/auto-scroll callbacks (which run
  // outside build) can reuse it.
  int _cols = 1;
  double _cellW = 0;
  Offset _lastGlobal = Offset.zero; // last pointer position (global)
  // Scroll offset captured when `_pointer` was last set from a finger move. The
  // dragged card's position adds (live offset − this), so it stays pinned under
  // the finger as the list auto-scrolls — computed in build, no per-frame lag.
  double _pointerScrollOffset = 0;
  final ScrollController _scroll = ScrollController();
  // Auto-scrolls the list when the dragged card nears the top/bottom edge, so a
  // card can be dropped off-screen. Flutter's own drag auto-scroller.
  EdgeDraggingAutoScroller? _autoScroller;

  @override
  void dispose() {
    _autoScroller?.stopAutoScroll();
    _scroll.dispose();
    super.dispose();
  }

  double get _scrollDelta =>
      _scroll.hasClients ? _scroll.offset - _pointerScrollOffset : 0;

  @override
  void didUpdateWidget(ReorderableCardGrid<T> old) {
    super.didUpdateWidget(old);
    // Adopt external changes (add / delete / apply) only when not mid-drag.
    if (_dragId == null && !_sameOrder(_order, widget.items)) {
      _order = [...widget.items];
    }
    // Drop measurements for items that are gone.
    final ids = {for (final it in widget.items) widget.idOf(it)};
    _heights.removeWhere((id, _) => !ids.contains(id));
  }

  void _reportHeight(Object id, double h) {
    if (_heights[id] == h) return;
    _heights[id] = h;
    // onChange fires during layout; defer the rebuild that repositions rows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Wraps an item so its laid-out height feeds the max-height measurement.
  Widget _measured(BuildContext context, T item) => _MeasureSize(
        onChange: (s) => _reportHeight(widget.idOf(item), s.height),
        child: widget.itemBuilder(context, item),
      );

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
    final ctx = _stackKey.currentContext;
    if (ctx != null) {
      _autoScroller = EdgeDraggingAutoScroller(
        Scrollable.of(ctx),
        velocityScalar: 20, // scroll speed near the edge; tune to taste
      );
    }
    // Reposition + re-target EVERY frame the list scrolls. The auto-scroller's
    // own onScrollViewScrolled only fires per animation chunk (too coarse — the
    // card visibly lags the content); the position notifies per frame, in the
    // transient phase, so this setState lands in the SAME frame the viewport
    // repaints → the card stays pinned under the finger with no lag.
    _scroll.addListener(_onScrollTick);
    setState(() {
      _dragId = widget.idOf(item);
      _pointer = _toStack(global);
      _grab = _pointer - slot;
      _lastGlobal = global;
      _pointerScrollOffset = _scroll.hasClients ? _scroll.offset : 0;
    });
  }

  /// Finger moved: re-anchor the pointer (and the scroll baseline, so the
  /// offset delta resets to 0) and reorder.
  void _moveDrag(Offset global) {
    _lastGlobal = global;
    setState(() {
      _pointer = _toStack(global);
      _pointerScrollOffset = _scroll.hasClients ? _scroll.offset : 0;
    });
    _updateTarget(_pointer);
    _updateAutoScroll();
  }

  /// List auto-scrolled under a held finger: the content under the finger is its
  /// anchor plus how far we've scrolled since. Re-target the reorder and rebuild
  /// so the dragged card's `_scrollDelta`-offset position tracks the scroll.
  void _onScrollTick() {
    if (_dragId == null) return;
    _updateTarget(_pointer + Offset(0, _scrollDelta));
    // Re-pin the edge rect to the finger's (fixed) SCREEN position. The auto
    // scroller stores it in content space, which drifts out of the edge zone as
    // the list scrolls under a still finger and stops it — re-asserting each
    // frame keeps it scrolling until the finger leaves the edge or the list ends.
    _updateAutoScroll();
    setState(() {}); // reposition the dragged card live with the scroll
  }

  void _updateTarget(Offset contentPointer) {
    final cur = _order.indexWhere((it) => widget.idOf(it) == _dragId);
    if (cur < 0) return;
    final tgt = _slotFromPointer(
        contentPointer, _cols, _cellW, _cellH ?? 0, _order.length);
    if (tgt != cur) setState(() => _order.insert(tgt, _order.removeAt(cur)));
  }

  void _updateAutoScroll() {
    // The finger's global position drives edge detection (it's fixed while the
    // list auto-scrolls under a held finger).
    _autoScroller?.startAutoScrollIfNecessary(
      Rect.fromCenter(
          center: _lastGlobal, width: _cellW, height: _cellH ?? 0),
    );
  }

  void _endDrag() {
    _autoScroller?.stopAutoScroll();
    _scroll.removeListener(_onScrollTick);
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

        // Uniform row height = the TALLEST measured item (null until the first
        // measurement lands). Each rendered card reports its own height via
        // `_measured`, so no separate probe is needed.
        double? maxH;
        for (final it in _order) {
          final h = _heights[widget.idOf(it)];
          if (h != null) maxH = maxH == null ? h : math.max(maxH, h);
        }
        _cellH = maxH; // cache for _moveDrag

        // Only the FIRST frame(s) — before any height is measured — fall back to
        // a plain self-sizing Wrap, which lays cards out identically (and feeds
        // the measurement) so the swap to the positioned grid is seamless. On
        // resize the grid stays up with the last height and just re-measures.
        if (maxH == null) {
          return SingleChildScrollView(
            padding: widget.padding,
            child: Wrap(
              spacing: widget.spacing,
              runSpacing: widget.spacing,
              children: [
                for (final it in _order)
                  SizedBox(width: cellW, child: _measured(context, it)),
              ],
            ),
          );
        }

        final cellH = maxH;
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
        _cols = cols;
        _cellW = cellW;
        // Whichever card is being dragged OR still dropping stays painted last.
        final topId = _dragId ?? _droppingId;
        final topIdx =
            topId == null ? -1 : _order.indexWhere((it) => widget.idOf(it) == topId);

        return SingleChildScrollView(
          controller: _scroll,
          padding: widget.padding,
          child: SizedBox(
            key: _stackKey,
            height: totalH,
            child: Stack(
              // Don't clip a card dragged past the last row / into empty space.
              clipBehavior: Clip.none,
              children: [
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
    // The dragged card follows the finger; `_scrollDelta` keeps it pinned there
    // (in content space) as the list auto-scrolls — computed live so no lag.
    var pos = dragging
        ? Offset(_pointer.dx - _grab.dx, _pointer.dy - _grab.dy + _scrollDelta)
        : slot;
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
      // Keep this subtree structurally CONSTANT across the reorder toggle (only
      // the callbacks / absorbing / elevation change) so the item's element —
      // and any AnimatedSize inside it — persists and can animate the switch.
      // In reorder mode: drag immediately (no long-press) and make the content
      // inert; otherwise the GestureDetector has no recognizers and taps pass
      // straight through to an interactive card.
      // A multi-drag recognizer (like ReorderableListView) so a card-drag WINS
      // the gesture arena over the enclosing scroll view — the list stays
      // normally scrollable (trackpad / wheel / dragging empty space) while
      // dragging a card reorders. Only wired in reorder mode.
      child: Semantics(
        container: true,
        customSemanticsActions: _reorderActions(context, d),
        child: RawGestureDetector(
          gestures: widget.reordering
              ? <Type, GestureRecognizerFactory>{
                  ImmediateMultiDragGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          ImmediateMultiDragGestureRecognizer>(
                    () => ImmediateMultiDragGestureRecognizer(),
                    (r) => r.onStart = (global) {
                      _startDrag(item, slot, global);
                      return _GridDrag(_moveDrag, _endDrag);
                    },
                  ),
                }
              : const {},
          child: Material(
            type: MaterialType.transparency,
            elevation: dragging ? 8 : 0,
            child: AbsorbPointer(
              absorbing: widget.reordering,
              child: _measured(context, item),
            ),
          ),
        ),
      ),
    );
  }
}

/// Forwards a multi-drag's movement/end to the grid's drag handlers.
class _GridDrag extends Drag {
  final void Function(Offset global) _onUpdate;
  final VoidCallback _onEnd;
  _GridDrag(this._onUpdate, this._onEnd);

  @override
  void update(DragUpdateDetails details) => _onUpdate(details.globalPosition);
  @override
  void end(DragEndDetails details) => _onEnd();
  @override
  void cancel() => _onEnd();
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
