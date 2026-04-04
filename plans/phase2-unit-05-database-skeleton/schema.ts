export interface TaskUnit {
  id: string;
  title: string;
  inputs?: any;
  outputs?: any;
  status: 'pending' | 'in_progress' | 'completed' | 'blocked';
  dependencies?: string[];
}

export interface Plan {
  id: string;
  name: string;
  units: TaskUnit[];
}

// In-memory storage (Phase 2, simple placeholder)
export const inMemoryStore: { plans: Plan[] } = { plans: [] };
