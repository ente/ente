import 'dart:convert';

import 'package:ente_ui/components/faq/faq_widgets.dart';
import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/material.dart';
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
        return FaqSection(
          children: [
            for (final faq in faqs)
              FaqItemWidget(question: faq.q ?? '', answer: faq.a ?? ''),
          ],
        );
      },
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
