import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/services/sync/backup_preparation_test.dart' as regression;
import '../tool/shared_checklist_validation/measure.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late regression.PreparationFixture fixture;
  regression.registerPreparationTests(
    registerTest: (name, body) {
      testWidgets(name, (tester) async => tester.runAsync(body));
    },
    onFixtureCreated: (value) => fixture = value,
  );
  testWidgets('measure integrated backup preparation', (tester) async {
    await tester.runAsync(() => measurePreparation(fixture));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
