enum FlavorType { customer, vendor }

class FlavorConfig {
  final FlavorType flavor;
  final String appName;
  final String appTitle;

  static FlavorConfig? _instance;

  FlavorConfig._({
    required this.flavor,
    required this.appName,
    required this.appTitle,
  });

  static void initialize({
    required FlavorType flavor,
    required String appName,
    required String appTitle,
  }) {
    _instance = FlavorConfig._(
      flavor: flavor,
      appName: appName,
      appTitle: appTitle,
    );
  }

  static FlavorConfig get instance {
    assert(_instance != null, 'FlavorConfig not initialized');
    return _instance!;
  }

  static bool get isCustomer =>
      _instance?.flavor == FlavorType.customer;

  static bool get isVendor =>
      _instance?.flavor == FlavorType.vendor;
}
