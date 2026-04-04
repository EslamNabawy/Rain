// Minimal frontend skeleton for Phase 2
export type PlanUnit = { id: string; title: string; status: string };
export type Plan = { id: string; name: string; units: PlanUnit[] };

export function renderPlan(plan: Plan) {
  // Placeholder rendering logic (no framework dependencies)
  return `Plan: ${plan.name} with ${plan.units.length} units`;
}
