import 'dart:convert';

const freeProductID = "free";
const popularProductIDs = ["200gb_yearly", "200gb_monthly"];
const stripe = "stripe";
const appStore = "appstore";
const playStore = "playstore";

class Subscription {
  final String productID;
  final int storage;
  final String originalTransactionID;
  final String paymentProvider;
  final int expiryTime;
  final String price;
  final String period;
  final Attributes? attributes;

  Subscription({
    required this.productID,
    required this.storage,
    required this.originalTransactionID,
    required this.paymentProvider,
    required this.expiryTime,
    required this.price,
    required this.period,
    this.attributes,
  });

  bool isValid() {
    return expiryTime > DateTime.now().microsecondsSinceEpoch;
  }

  bool isCancelled() {
    return attributes?.isCancelled ?? false;
  }

  bool isPastDue() {
    return !isCancelled() &&
        expiryTime < DateTime.now().microsecondsSinceEpoch &&
        expiryTime >=
            DateTime.now()
                .subtract(const Duration(days: 30))
                .microsecondsSinceEpoch;
  }

  bool isYearlyPlan() {
    return 'year' == period;
  }

  bool isFreePlan() {
    return productID == freeProductID;
  }

  static Subscription fromMap(Map<String, dynamic> map) {
    return Subscription(
      productID: map['productID'],
      storage: map['storage'],
      originalTransactionID: map['originalTransactionID'],
      paymentProvider: map['paymentProvider'],
      expiryTime: map['expiryTime'],
      price: map['price'],
      period: map['period'],
      attributes: map["attributes"] != null
          ? Attributes.fromMap(map["attributes"])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productID': productID,
      'storage': storage,
      'originalTransactionID': originalTransactionID,
      'paymentProvider': paymentProvider,
      'expiryTime': expiryTime,
      'price': price,
      'period': period,
      'attributes': attributes?.toMap(),
    };
  }

  String toJson() => json.encode(toMap());

  factory Subscription.fromJson(String source) =>
      Subscription.fromMap(json.decode(source));
}

class Attributes {
  bool? isCancelled;
  String? customerID;

  Attributes({this.isCancelled, this.customerID});

  Map<String, dynamic> toMap() {
    return {'isCancelled': isCancelled, 'customerID': customerID};
  }

  factory Attributes.fromMap(Map<String, dynamic> map) {
    return Attributes(
      isCancelled: map['isCancelled'],
      customerID: map['customerID'],
    );
  }

  String toJson() => json.encode(toMap());

  factory Attributes.fromJson(String source) =>
      Attributes.fromMap(json.decode(source));
}
