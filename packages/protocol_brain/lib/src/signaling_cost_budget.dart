/// # signaling_cost_budget.dart — protocol_brain package
///
/// Defines constants and exceptions for signaling cost budgeting. Limits ICE candidates per role and batch sizes to control Firebase RTDB write costs, with a custom exception for budget exceeded scenarios.
///
/// **Key types:** SignalingCostBudgetExceeded (exception), maxIceCandidatesPerRole, maxIceCandidateBatchSize, iceCandidateBatchWindow
///
/// **Package:** protocol_brain
///
/// **Depends on:** None (standalone constants)
const int maxIceCandidatesPerRole = 80;
const int maxIceCandidateBatchSize = 12;
const Duration iceCandidateBatchWindow = Duration(milliseconds: 150);

final class SignalingCostBudgetExceeded implements Exception {
  const SignalingCostBudgetExceeded(this.message);

  final String message;

  @override
  String toString() => message;
}
