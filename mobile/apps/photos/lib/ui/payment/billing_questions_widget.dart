import 'dart:convert';

import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:photos/core/network/network.dart';
import 'package:photos/ente_theme_data.dart';

class BillingQuestionsWidget extends StatelessWidget {
  const BillingQuestionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: NetworkClient.instance
          .getDio()
          .get("https://static.ente.com/faq.json")
          .then((response) {
            final faqItems = <FaqItem>[];
            if (response.data is List) {
              for (final item in response.data as List) {
                if (item is Map<String, dynamic>) {
                  faqItems.add(FaqItem.fromMap(item));
                }
              }
            }
            return faqItems;
          }),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.hasData) {
          final faqs = <Widget>[];
          faqs.add(
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "FAQs",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          );
          for (final faq in snapshot.data as List<FaqItem>) {
            faqs.add(FaqWidget(faq: faq));
          }
          faqs.add(const Padding(padding: EdgeInsets.all(16)));
          return SingleChildScrollView(child: Column(children: faqs));
        } else {
          return const EnteLoadingWidget();
        }
      },
    );
  }
}

class FaqWidget extends StatelessWidget {
  const FaqWidget({super.key, required this.faq});

  final FaqItem faq;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expandedColor = theme.colorScheme.greenAlternative;
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    );

    final question = faq.q ?? '';
    final answer = faq.a ?? '';

    return Padding(
      padding: const EdgeInsets.all(2),
      child: ExpansionTile(
        key: PageStorageKey(question),
        clipBehavior: Clip.antiAlias,
        title: Text(question),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18),
        textColor: expandedColor,
        collapsedTextColor: theme.textTheme.titleMedium?.color,
        iconColor: expandedColor,
        collapsedIconColor: theme.unselectedWidgetColor,
        backgroundColor: theme.cardColor,
        collapsedBackgroundColor: theme.cardColor,
        shape: shape,
        collapsedShape: shape,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
            child: Text(answer, style: const TextStyle(height: 1.5)),
          ),
        ],
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
