import 'dart:convert';

import 'package:ente_components/ente_components.dart';
import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/core/network/network.dart';

class BillingQuestionsWidget extends StatefulWidget {
  const BillingQuestionsWidget({super.key});

  @override
  State<BillingQuestionsWidget> createState() => _BillingQuestionsWidgetState();
}

class _BillingQuestionsWidgetState extends State<BillingQuestionsWidget> {
  late final Future<List<FaqItem>> _faqs = _loadFaqs();

  Future<List<FaqItem>> _loadFaqs() async {
    final response = await NetworkClient.instance.getDio().get(
      "https://static.ente.com/faq.json",
    );
    final faqItems = <FaqItem>[];
    if (response.data is List) {
      for (final item in response.data as List) {
        if (item is Map<String, dynamic>) {
          faqItems.add(FaqItem.fromMap(item));
        }
      }
    }
    return faqItems;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FaqItem>>(
      future: _faqs,
      builder: (BuildContext context, AsyncSnapshot<List<FaqItem>> snapshot) {
        final faqs = snapshot.data;
        if (faqs == null) {
          return const EnteLoadingWidget();
        }
        return Column(
          children: [
            for (var i = 0; i < faqs.length; i++) ...[
              if (i > 0) const SizedBox(height: Spacing.sm),
              FaqWidget(faq: faqs[i]),
            ],
          ],
        );
      },
    );
  }
}

class FaqWidget extends StatefulWidget {
  const FaqWidget({super.key, required this.faq});

  final FaqItem faq;

  @override
  State<FaqWidget> createState() => _FaqWidgetState();
}

class _FaqWidgetState extends State<FaqWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Material(
      color: colors.fillLight,
      borderRadius: BorderRadius.circular(Radii.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.xl,
                Spacing.lg,
                Spacing.xl,
                Spacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.faq.q ?? '',
                      style: TextStyles.bodyBold.copyWith(
                        color: colors.textBase,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  HugeIcon(
                    icon: _isExpanded
                        ? HugeIcons.strokeRoundedArrowUp01
                        : HugeIcons.strokeRoundedArrowDown01,
                    size: IconSizes.small,
                    color: colors.textBase,
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: Motion.standard,
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: _isExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.xl,
                        0,
                        Spacing.xl,
                        Spacing.lg,
                      ),
                      child: Text(
                        widget.faq.a ?? '',
                        style: TextStyles.mini.copyWith(
                          color: colors.textLight,
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class FaqItem {
  final String? q;
  final String? a;
  FaqItem({this.q, this.a});

  FaqItem copyWith({String? q, String? a}) {
    return FaqItem(q: q ?? this.q, a: a ?? this.a);
  }

  Map<String, dynamic> toMap() {
    return {'q': q, 'a': a};
  }

  factory FaqItem.fromMap(Map<String, dynamic> map) {
    return FaqItem(
      q: map['q']?.toString() ?? '',
      a: map['a']?.toString() ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory FaqItem.fromJson(String source) =>
      FaqItem.fromMap(json.decode(source));

  @override
  String toString() => 'FaqItem(q: $q, a: $a)';

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) return true;

    return o is FaqItem && o.q == q && o.a == a;
  }

  @override
  int get hashCode => q.hashCode ^ a.hashCode;
}
