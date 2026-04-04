// Minimal backend skeleton for phase 2
export function planHandler() {
  return { ok: true, plan: [] as any[] }
}

export function executeUnit(unitId: string, payload: any) {
  // placeholder implementation
  return { unitId, status: 'not-implemented' as const, payload }
}
