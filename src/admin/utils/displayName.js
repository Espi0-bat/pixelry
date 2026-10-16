// Nome curto para saudações e para o painel de perfil: o primeiro nome do
// cadastro (profiles.full_name); sem cadastro, a parte local do e-mail.
export function displayName(profile, user) {
  const first = String(profile?.full_name || '').trim().split(/\s+/)[0];
  return first || String(user?.email || '').split('@')[0];
}
