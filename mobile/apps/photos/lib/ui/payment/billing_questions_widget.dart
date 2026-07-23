import 'dart:convert';

import 'package:expansion_tile_card/expansion_tile_card.dart';
import 'package:flutter/material.dart';
import 'package:photos/core/network/network.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/ui/common/loading_widget.dart';

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
            for (final item in response.data as List) {
              faqItems.add(FaqItem.fromMap(item));
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
          for (final faq in snapshot.data) {
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

  final FaqItem? faq;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: ExpansionTileCard(
        elevation: 0,
        title: Text(faq!.q!),
        expandedTextColor: Theme.of(context).colorScheme.greenAlternative,
        baseColor: Theme.of(context).cardColor,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
            child: Text(faq!.a!, style: const TextStyle(height: 1.5)),
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
    return FaqItem(q: map['q'] ?? 'q', a: map['a'] ?? 'a');
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
