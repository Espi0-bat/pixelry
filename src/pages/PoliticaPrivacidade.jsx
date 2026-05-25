import React from 'react';

export default function PoliticaPrivacidade() {
  return (
    <div style={{
      maxWidth: '800px',
      margin: '0 auto',
      padding: '120px 24px 80px',
      color: 'var(--text-primary, #fff)',
      lineHeight: '1.6',
      fontFamily: 'var(--font-sans)'
    }}>
      <h1 style={{ fontSize: '2.5rem', marginBottom: '24px', fontWeight: 'bold' }}>Política de Privacidade</h1>
      
      <p style={{ marginBottom: '16px', color: 'var(--text-secondary, #a0a0a0)' }}>
        Última atualização: [Data de hoje]
      </p>

      <p style={{ marginBottom: '24px' }}>
        A sua privacidade é importante para nós. É política da <strong>PIXELRY</strong> respeitar a sua privacidade em relação a qualquer informação sua que possamos coletar no site PIXELRY e outros sites que possuímos e operamos.
      </p>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>1. Informações que Coletamos</h2>
      <p style={{ marginBottom: '16px' }}>
        Solicitamos informações pessoais apenas quando realmente precisamos delas para lhe fornecer um serviço. Fazemo-lo por meios justos e legais, com o seu conhecimento e consentimento. Também informamos por que estamos coletando e como será usado.
      </p>
      <ul style={{ listStyleType: 'disc', paddingLeft: '24px', marginBottom: '24px' }}>
        <li style={{ marginBottom: '8px' }}>Dados de contato (ex: nome, e-mail, telefone) preenchidos em formulários.</li>
        <li style={{ marginBottom: '8px' }}>Dados de navegação e cookies, essenciais para o funcionamento do site e para análises de tráfego.</li>
      </ul>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>2. Uso das Informações</h2>
      <p style={{ marginBottom: '24px' }}>
        Apenas retemos as informações coletadas pelo tempo necessário para fornecer o serviço solicitado. Quando armazenamos dados, os protegemos dentro de meios comercialmente aceitáveis para evitar perdas e roubos, bem como acesso, divulgação, cópia, uso ou modificação não autorizados.
      </p>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>3. Compartilhamento de Dados</h2>
      <p style={{ marginBottom: '24px' }}>
        Não compartilhamos informações de identificação pessoal publicamente ou com terceiros, exceto quando exigido por lei.
      </p>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>4. Seus Direitos (LGPD)</h2>
      <p style={{ marginBottom: '16px' }}>
        De acordo com a Lei Geral de Proteção de Dados (Lei nº 13.709/2018), você tem o direito de:
      </p>
      <ul style={{ listStyleType: 'disc', paddingLeft: '24px', marginBottom: '24px' }}>
        <li style={{ marginBottom: '8px' }}>Confirmar a existência de tratamento de dados;</li>
        <li style={{ marginBottom: '8px' }}>Acessar seus dados;</li>
        <li style={{ marginBottom: '8px' }}>Corrigir dados incompletos, inexatos ou desatualizados;</li>
        <li style={{ marginBottom: '8px' }}>Solicitar a exclusão ou anonimização dos dados;</li>
        <li style={{ marginBottom: '8px' }}>Revogar o consentimento a qualquer momento.</li>
      </ul>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>5. Contato</h2>
      <p style={{ marginBottom: '24px' }}>
        Se você tiver alguma dúvida sobre como lidamos com dados do usuário e informações pessoais, entre em contato conosco através do e-mail: <strong>[SEU E-MAIL AQUI]</strong>.
      </p>
    </div>
  );
}
