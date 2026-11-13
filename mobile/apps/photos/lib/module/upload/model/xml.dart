// ignore_for_file: implementation_imports

import "package:xml/xml.dart";

abstract class XmlParsableObject {
  Map<String, dynamic> toMap();
  String get elementName;
}

String convertJs2Xml(Map<String, dynamic> json) {
  final builder = XmlBuilder();
  buildXml(builder, json);
  return builder.buildDocument().toXmlString(pretty: true, indent: '    ');
}

void buildXml(XmlBuilder builder, dynamic node) {
  if (node is Map<String, dynamic>) {
    node.forEach((key, value) {
      builder.element(key, nest: () => buildXml(builder, value));
    });
  } else if (node is List<dynamic>) {
    for (var item in node) {
      buildXml(builder, item);
    }
  } else if (node is XmlParsableObject) {
    builder.element(
      node.elementName,
      nest: () {
        buildXml(builder, node.toMap());
      },
    );
  } else {
    builder.text(node.toString());
  }
}
