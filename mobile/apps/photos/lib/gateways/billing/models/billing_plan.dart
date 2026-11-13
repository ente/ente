import 'dart:convert';

class BillingPlans {
  final List<BillingPlan> plans;
  final FreePlan freePlan;

  BillingPlans({required this.plans, required this.freePlan});

  Map<String, dynamic> toMap() {
    return {
      'plans': plans.map((x) => x.toMap()).toList(),
      'freePlan': freePlan.toMap(),
    };
  }

  static BillingPlans fromMap(Map<String, dynamic> map) {
    return BillingPlans(
      plans: List<BillingPlan>.from(
        map['plans']?.map((x) => BillingPlan.fromMap(x)),
      ),
      freePlan: FreePlan.fromMap(map['freePlan']),
    );
  }

  factory BillingPlans.fromJson(String source) =>
      BillingPlans.fromMap(json.decode(source));
}

class FreePlan {
  final int storage;
  final int duration;
  final String period;
  FreePlan({
    required this.storage,
    required this.duration,
    required this.period,
  });

  Map<String, dynamic> toMap() {
    return {'storage': storage, 'duration': duration, 'period': period};
  }

  static FreePlan fromMap(Map<String, dynamic> map) {
    return FreePlan(
      storage: map['storage'],
      duration: map['duration'],
      period: map['period'],
    );
  }
}

class BillingPlan {
  final String id;
  final String androidID;
  final String iosID;
  final String stripeID;
  final int storage;
  final String price;
  final String period;

  BillingPlan({
    required this.id,
    required this.androidID,
    required this.iosID,
    required this.stripeID,
    required this.storage,
    required this.price,
    required this.period,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'androidID': androidID,
      'iosID': iosID,
      'stripeID': stripeID,
      'storage': storage,
      'price': price,
      'period': period,
    };
  }

  static BillingPlan fromMap(Map<String, dynamic> map) {
    return BillingPlan(
      id: map['id'],
      androidID: map['androidID'],
      iosID: map['iosID'],
      stripeID: map['stripeID'],
      storage: map['storage'],
      price: map['price'],
      period: map['period'],
    );
  }
}
