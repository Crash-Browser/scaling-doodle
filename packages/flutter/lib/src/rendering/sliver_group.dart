// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';

import 'object.dart';
import 'sliver.dart';

/// A sliver that places multiple sliver children in a linear array along the cross
/// axis.
///
/// Since the extent of the viewport in the cross axis direction is finite,
/// this extent will be divided up and allocated to the children slivers.
///
/// The algorithm for dividing up the cross axis extent is as follows.
/// Every widget has a [SliverPhysicalParentData.crossAxisFlex] value associated with them.
/// First, lay out all of the slivers with flex of 0 or null, in which case the slivers themselves will
/// figure out how much cross axis extent to take up. For example, [SliverConstrainedCrossAxis]
/// is an example of a widget which sets its own flex to 0. Then [RenderSliverCrossAxisGroup] will
/// divide up the remaining space to all the remaining children proportionally
/// to each child's flex factor. By default, children of [SliverCrossAxisGroup]
/// are setup to have a flex factor of 1, but a different flex factor can be
/// specified via the [SliverCrossAxisExpanded] widgets.
class RenderSliverCrossAxisGroup extends RenderSliver with ContainerRenderObjectMixin<RenderSliver, SliverPhysicalContainerParentData> {
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverPhysicalContainerParentData) {
      child.parentData = SliverPhysicalContainerParentData();
      (child.parentData! as SliverPhysicalParentData).crossAxisFlex = 1;
    }
  }

  @override
  double childMainAxisPosition(RenderSliver child) => 0.0;

  @override
  double childCrossAxisPosition(RenderSliver child) {
    switch (constraints.axisDirection) {
      case AxisDirection.up:
      case AxisDirection.down:
        return (child.parentData! as SliverPhysicalParentData).paintOffset.dx;
      case AxisDirection.left:
      case AxisDirection.right:
        return (child.parentData! as SliverPhysicalParentData).paintOffset.dy;
    }
  }

  @override
  void performLayout() {
    // Iterate through each sliver.
    // Get the parent's dimensions.
    final double crossAxisExtent = constraints.crossAxisExtent;
    assert(crossAxisExtent.isFinite);

    // First, layout each child with flex == 0 or null.
    int totalFlex = 0;
    double remainingExtent = crossAxisExtent;
    RenderSliver? child = firstChild;
    while (child != null) {
      final SliverPhysicalParentData childParentData = child.parentData! as SliverPhysicalParentData;
      final int flex = childParentData.crossAxisFlex ?? 0;
      if (flex == 0) {
        // If flex is 0 or null, then the child sliver must provide their own crossAxisExtent.
        assert(_assertOutOfExtent(remainingExtent));
        child.layout(constraints.copyWith(crossAxisExtent: remainingExtent), parentUsesSize: true);
        final double? childCrossAxisExtent = child.geometry!.crossAxisExtent;
        assert(childCrossAxisExtent != null);
        remainingExtent = math.max(0.0, remainingExtent - childCrossAxisExtent!);
      } else {
        totalFlex += flex;
      }
      child = childAfter(child);
    }
    final double extentPerFlexValue = remainingExtent / totalFlex;

    child = firstChild;

    // At this point, all slivers with constrained cross axis should already be laid out.
    // Layout the rest and keep track of the child geometry with greatest scrollExtent.
    geometry = SliverGeometry.zero;
    while (child != null) {
      final SliverPhysicalParentData childParentData = child.parentData! as SliverPhysicalParentData;
      final int flex = childParentData.crossAxisFlex ?? 0;
      double childExtent;
      if (flex != 0) {
        childExtent = extentPerFlexValue * flex;
        assert(_assertOutOfExtent(childExtent));
        child.layout(constraints.copyWith(
          crossAxisExtent: extentPerFlexValue * flex,
        ), parentUsesSize: true);
      } else {
        childExtent = child.geometry!.crossAxisExtent!;
      }
      final SliverGeometry childLayoutGeometry = child.geometry!;
      if (geometry!.scrollExtent < childLayoutGeometry.scrollExtent) {
        geometry = childLayoutGeometry;
      }
      child = childAfter(child);
    }

    // Go back and correct any slivers using a negative paint offset if it tries
    // to paint outside the bounds of the sliver group.
    child = firstChild;
    double offset = 0.0;
    while (child != null) {
      final SliverPhysicalParentData childParentData = child.parentData! as SliverPhysicalParentData;
      final SliverGeometry childLayoutGeometry = child.geometry!;
      final double remainingExtent = geometry!.scrollExtent - constraints.scrollOffset;
      final double paintCorrection = childLayoutGeometry.paintExtent > remainingExtent
        ? childLayoutGeometry.paintExtent - remainingExtent
        : 0.0;
      final double childExtent = child.geometry!.crossAxisExtent ?? extentPerFlexValue * (childParentData.crossAxisFlex ?? 0);
      // Set child parent data.
      switch (constraints.axis) {
        case Axis.vertical:
          childParentData.paintOffset = Offset(offset, -paintCorrection);
        case Axis.horizontal:
          childParentData.paintOffset = Offset(-paintCorrection, offset);
      }
      offset += childExtent;
      child = childAfter(child);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderSliver? child = firstChild;

    while (child != null) {
      if (child.geometry!.visible) {
        final SliverPhysicalParentData childParentData = child.parentData! as SliverPhysicalParentData;
        context.paintChild(child, offset + childParentData.paintOffset);
      }
      child = childAfter(child);
    }
  }

  @override
  void applyPaintTransform(RenderSliver child, Matrix4 transform) {
    final SliverPhysicalParentData childParentData = child.parentData! as SliverPhysicalParentData;
    childParentData.applyPaintTransform(transform);
  }

  @override
  bool hitTestChildren(SliverHitTestResult result, {required double mainAxisPosition, required double crossAxisPosition}) {
    RenderSliver? child = lastChild;
    while (child != null) {
      final bool isHit = result.addWithAxisOffset(
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
        paintOffset: null,
        mainAxisOffset: childMainAxisPosition(child),
        crossAxisOffset: childCrossAxisPosition(child),
        hitTest: child.hitTest,
      );
      if (isHit) {
        return true;
      }
      child = childBefore(child);
    }
    return false;
  }
}

bool _assertOutOfExtent(double extent) {
  if (extent <= 0.0) {
    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary('SliverCrossAxisGroup ran out of extent before child could be laid out.'),
      ErrorDescription(
        'SliverCrossAxisGroup lays out any slivers with a constrained cross '
        'axis before laying out those which expand. In this case, cross axis '
        'extent was used up before the next sliver could be laid out.'
      ),
      ErrorHint(
        'Make sure that the total amount of extent allocated by constrained '
        'child slivers does not exceed the cross axis extent that is available '
        'for the SliverCrossAxisGroup.'
      ),
    ]);
  }
  return true;
}

/// A sliver that places multiple sliver children in a linear array along the
/// main axis.
///
/// The layout algorithm lays out slivers one by one. If the sliver is at the top
/// of the viewport or above the top, then we pass in a nonzero [SliverConstraints.scrollOffset]
/// to inform the sliver at what point along the main axis we should start layout.
/// For the slivers that come after it, we compute the amount of space taken up so
/// far to be used as the [SliverPhysicalParentData.paintOffset] and the
/// [SliverConstraints.remainingPaintExtent] to be passed in as a constraint.
///
/// Finally, this sliver will also ensure that all child slivers are painted within
/// the total scroll extent of the group by adjusting the child's
/// [SliverPhysicalParentData.paintOffset] as necessary. This can happen for
/// slivers such as [SliverPersistentHeader] which, when pinned, positions itself
/// at the top of the [Viewport] regardless of the scroll offset.
class RenderSliverMainAxisGroup extends RenderSliver with ContainerRenderObjectMixin<RenderSliver, SliverPhysicalContainerParentData> {
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverPhysicalContainerParentData) {
      child.parentData = SliverPhysicalContainerParentData();
    }
  }

  @override
  double childMainAxisPosition(RenderSliver child) {
    switch (constraints.axisDirection) {
      case AxisDirection.up:
      case AxisDirection.down:
        return (child.parentData! as SliverPhysicalParentData).paintOffset.dy;
      case AxisDirection.left:
      case AxisDirection.right:
        return (child.parentData! as SliverPhysicalParentData).paintOffset.dx;
    }
  }

  @override
  double childCrossAxisPosition(RenderSliver child) => 0.0;

  @override
  void performLayout() {
    double offset = 0;
    double maxPaintExtent = 0;

    RenderSliver? child = firstChild;


    while (child != null) {
      final double beforeOffsetPaintExtent = calculatePaintOffset(
        constraints,
        from: 0.0,
        to: offset,
      );
      child.layout(
        constraints.copyWith(
          scrollOffset: math.max(0.0, constraints.scrollOffset - offset),
          cacheOrigin: math.min(0.0, constraints.cacheOrigin + offset),
          overlap: math.max(0.0, constraints.overlap - beforeOffsetPaintExtent),
          remainingPaintExtent: constraints.remainingPaintExtent - beforeOffsetPaintExtent,
          remainingCacheExtent: constraints.remainingCacheExtent - calculateCacheOffset(constraints, from: 0.0, to: offset),
          precedingScrollExtent: offset + constraints.precedingScrollExtent,
        ),
        parentUsesSize: true,
      );
      final SliverGeometry childLayoutGeometry = child.geometry!;
      final SliverPhysicalParentData childParentData = child.parentData! as SliverPhysicalParentData;
      switch (constraints.axis) {
        case Axis.vertical:
          childParentData.paintOffset = Offset(0.0, beforeOffsetPaintExtent);
        case Axis.horizontal:
          childParentData.paintOffset = Offset(beforeOffsetPaintExtent, 0.0);
      }
      offset += childLayoutGeometry.scrollExtent;
      maxPaintExtent += child.geometry!.maxPaintExtent;
      child = childAfter(child);
    }

    final double totalScrollExtent = offset;
    offset = 0.0;
    child = firstChild;
    // Second pass to correct out of bound paintOffsets.
    while (child != null) {
      final double beforeOffsetPaintExtent = calculatePaintOffset(
        constraints,
        from: 0.0,
        to: offset,
      );
      final SliverGeometry childLayoutGeometry = child.geometry!;
      final SliverPhysicalParentData childParentData = child.parentData! as SliverPhysicalParentData;
      final double remainingExtent = totalScrollExtent - constraints.scrollOffset;
      if (childLayoutGeometry.paintExtent > remainingExtent) {
        final double paintCorrection = childLayoutGeometry.paintExtent - remainingExtent;
        switch (constraints.axis) {
          case Axis.vertical:
            childParentData.paintOffset = Offset(0.0, beforeOffsetPaintExtent - paintCorrection);
          case Axis.horizontal:
            childParentData.paintOffset = Offset(beforeOffsetPaintExtent - paintCorrection, 0.0);
        }
      }
      offset += child.geometry!.scrollExtent;
      child = childAfter(child);
    }
    geometry = SliverGeometry(
      scrollExtent: totalScrollExtent,
      paintExtent: calculatePaintOffset(constraints, from: 0, to: totalScrollExtent),
      maxPaintExtent: maxPaintExtent,
      hasVisualOverflow: totalScrollExtent > constraints.remainingPaintExtent || constraints.scrollOffset > 0.0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderSliver? child = lastChild;

    while (child != null) {
      if (child.geometry!.visible) {
        final SliverPhysicalParentData childParentData = child.parentData! as SliverPhysicalParentData;
        context.paintChild(child, offset + childParentData.paintOffset);
      }
      child = childBefore(child);
    }
  }

  @override
  void applyPaintTransform(RenderSliver child, Matrix4 transform) {
    final SliverPhysicalParentData childParentData = child.parentData! as SliverPhysicalParentData;
    childParentData.applyPaintTransform(transform);
  }

  @override
  bool hitTestChildren(SliverHitTestResult result, {required double mainAxisPosition, required double crossAxisPosition}) {
    RenderSliver? child = firstChild;
    while (child != null) {
      final bool isHit = result.addWithAxisOffset(
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
        paintOffset: null,
        mainAxisOffset: childMainAxisPosition(child),
        crossAxisOffset: childCrossAxisPosition(child),
        hitTest: child.hitTest,
      );
      if (isHit) {
        return true;
      }
      child = childAfter(child);
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    RenderSliver? child = firstChild;
    while (child != null) {
      if (child.geometry!.visible) {
        visitor(child);
      }
      child = childAfter(child);
    }
  }
}
