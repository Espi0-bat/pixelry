-- Índice em profiles.role (usado em múltiplas queries de filtro)
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);

-- Índice em profiles.assigned_employee_id (usado em Equipe e EmployeeDashboard)
CREATE INDEX IF NOT EXISTS idx_profiles_assigned_employee ON profiles(assigned_employee_id);

-- Índices em deliveries (filtro por status e client_id)
CREATE INDEX IF NOT EXISTS idx_deliveries_status ON deliveries(status);
CREATE INDEX IF NOT EXISTS idx_deliveries_client_id ON deliveries(client_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_created_at ON deliveries(created_at DESC);

-- Índices em projects (filtro por client_id e ordenação)
CREATE INDEX IF NOT EXISTS idx_projects_client_id ON projects(client_id);
CREATE INDEX IF NOT EXISTS idx_projects_created_at ON projects(created_at DESC);

-- Índice em weekly_goals.week_start (filtro semanal)
CREATE INDEX IF NOT EXISTS idx_weekly_goals_week_start ON weekly_goals(week_start);

-- Índices em kanban_tasks (ordenação por created_at)
CREATE INDEX IF NOT EXISTS idx_kanban_tasks_created_at ON kanban_tasks(created_at ASC);
CREATE INDEX IF NOT EXISTS idx_kanban_tasks_status ON kanban_tasks(status);

-- Índices em employee_notes (filtro por employee_id)
CREATE INDEX IF NOT EXISTS idx_employee_notes_employee_id ON employee_notes(employee_id);

-- Índices em internal_files (filtro por from_id e to_id)
CREATE INDEX IF NOT EXISTS idx_internal_files_from_id ON internal_files(from_id);
CREATE INDEX IF NOT EXISTS idx_internal_files_to_id ON internal_files(to_id);

-- Índices em invoices (filtro por client_id)
CREATE INDEX IF NOT EXISTS idx_invoices_client_id ON invoices(client_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status);
