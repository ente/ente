enum FlexLayoutTuningField { targetHeightScale, maximumHeightFactor }

enum FlexFullRowsLayoutTuningField {
  targetHeightScale,
  maximumHeightFactor,
  minimumNonFinalSingletonAspectRatio,
}

enum ComfortLargeLayoutTuningField {
  targetHeightScale,
  maximumHeightFactor,
  wideFinalMaximumHeightFactor,
  minimumLandscapeHeightFactor,
}

class FlexLayoutTuning {
  static const defaults = FlexLayoutTuning();

  final double targetHeightScale;
  final double maximumHeightFactor;

  const FlexLayoutTuning({
    this.targetHeightScale = 1.12,
    this.maximumHeightFactor = 1.6,
  });

  double valueFor(FlexLayoutTuningField field) {
    return switch (field) {
      FlexLayoutTuningField.targetHeightScale => targetHeightScale,
      FlexLayoutTuningField.maximumHeightFactor => maximumHeightFactor,
    };
  }
}

extension FlexLayoutTuningFieldValue on FlexLayoutTuningField {
  double get defaultValue => FlexLayoutTuning.defaults.valueFor(this);

  double get maximumValue => 10;

  double get minimumValue => switch (this) {
    FlexLayoutTuningField.targetHeightScale => 0.1,
    FlexLayoutTuningField.maximumHeightFactor => 1,
  };

  bool isValid(double value) =>
      value.isFinite && value >= minimumValue && value <= maximumValue;
}

class FlexFullRowsLayoutTuning {
  static const defaults = FlexFullRowsLayoutTuning();

  final double targetHeightScale;
  final double maximumHeightFactor;
  final double minimumNonFinalSingletonAspectRatio;

  const FlexFullRowsLayoutTuning({
    this.targetHeightScale = 1.12,
    this.maximumHeightFactor = 1.6,
    this.minimumNonFinalSingletonAspectRatio = 0.75,
  });

  double valueFor(FlexFullRowsLayoutTuningField field) {
    return switch (field) {
      FlexFullRowsLayoutTuningField.targetHeightScale => targetHeightScale,
      FlexFullRowsLayoutTuningField.maximumHeightFactor => maximumHeightFactor,
      FlexFullRowsLayoutTuningField.minimumNonFinalSingletonAspectRatio =>
        minimumNonFinalSingletonAspectRatio,
    };
  }
}

extension FlexFullRowsLayoutTuningFieldValue on FlexFullRowsLayoutTuningField {
  double get defaultValue => FlexFullRowsLayoutTuning.defaults.valueFor(this);

  double get maximumValue => 10;

  double get minimumValue => switch (this) {
    FlexFullRowsLayoutTuningField.targetHeightScale ||
    FlexFullRowsLayoutTuningField.minimumNonFinalSingletonAspectRatio => 0.1,
    FlexFullRowsLayoutTuningField.maximumHeightFactor => 1,
  };

  bool isValid(double value) =>
      value.isFinite && value >= minimumValue && value <= maximumValue;
}

class ComfortLargeLayoutTuning {
  static const defaults = ComfortLargeLayoutTuning();

  final double targetHeightScale;
  final double maximumHeightFactor;
  final double wideFinalMaximumHeightFactor;
  final double minimumLandscapeHeightFactor;

  const ComfortLargeLayoutTuning({
    this.targetHeightScale = 1.5,
    this.maximumHeightFactor = 2.4,
    this.wideFinalMaximumHeightFactor = 1.0,
    this.minimumLandscapeHeightFactor = 0.88,
  });

  double valueFor(ComfortLargeLayoutTuningField field) {
    return switch (field) {
      ComfortLargeLayoutTuningField.targetHeightScale => targetHeightScale,
      ComfortLargeLayoutTuningField.maximumHeightFactor => maximumHeightFactor,
      ComfortLargeLayoutTuningField.wideFinalMaximumHeightFactor =>
        wideFinalMaximumHeightFactor,
      ComfortLargeLayoutTuningField.minimumLandscapeHeightFactor =>
        minimumLandscapeHeightFactor,
    };
  }
}

extension ComfortLargeLayoutTuningFieldValue on ComfortLargeLayoutTuningField {
  double get defaultValue => ComfortLargeLayoutTuning.defaults.valueFor(this);

  double get maximumValue => 10;

  double get minimumValue => switch (this) {
    ComfortLargeLayoutTuningField.targetHeightScale ||
    ComfortLargeLayoutTuningField.minimumLandscapeHeightFactor => 0.1,
    ComfortLargeLayoutTuningField.maximumHeightFactor ||
    ComfortLargeLayoutTuningField.wideFinalMaximumHeightFactor => 1,
  };

  bool isValid(double value) =>
      value.isFinite && value >= minimumValue && value <= maximumValue;
}
