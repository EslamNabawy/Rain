const int maxIceCandidatesPerRole = 80;
const int maxIceCandidateBatchSize = 12;
const Duration iceCandidateBatchWindow = Duration(milliseconds: 150);

final class SignalingCostBudgetExceeded implements Exception {
  const SignalingCostBudgetExceeded(this.message);

  final String message;

  @override
  String toString() => message;
}
