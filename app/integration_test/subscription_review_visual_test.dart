import 'package:integration_test/integration_test.dart';

import '../test/subscription_review_ui_test.dart' as suite;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.registerSubscriptionReviewUiTests(captureScreenshots: true);
}
