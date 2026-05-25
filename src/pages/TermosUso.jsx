import React from 'react';

export default function TermosUso() {
  return (
    <div style={{
      maxWidth: '800px',
      margin: '0 auto',
      padding: '120px 24px 80px',
      color: 'var(--text-primary, #fff)',
      lineHeight: '1.6',
      fontFamily: 'var(--font-sans)'
    }}>
      <h1 style={{ fontSize: '2.5rem', marginBottom: '24px', fontWeight: 'bold' }}>Termos de Uso</h1>
      
      <p style={{ marginBottom: '16px', color: 'var(--text-secondary, #a0a0a0)' }}>
        Última atualização: [Data de hoje]
      </p>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>1. Termos</h2>
      <p style={{ marginBottom: '24px' }}>
        Ao acessar ao site <strong>PIXELRY</strong>, você concorda em cumprir estes termos de serviço, todas as leis e regulamentos aplicáveis e concorda que é responsável pelo cumprimento de todas as leis locais aplicáveis. Se você não concordar com algum desses termos, está proibido de usar ou acessar este site. Os materiais contidos neste site são protegidos pelas leis de direitos autorais e marcas comerciais aplicáveis.
      </p>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>2. Uso de Licença</h2>
      <p style={{ marginBottom: '16px' }}>
        É concedida permissão para baixar temporariamente uma cópia dos materiais (informações ou software) no site PIXELRY, apenas para visualização transitória pessoal e não comercial. Esta é a concessão de uma licença, não uma transferência de título e, sob esta licença, você não pode:
      </p>
      <ul style={{ listStyleType: 'disc', paddingLeft: '24px', marginBottom: '24px' }}>
        <li style={{ marginBottom: '8px' }}>modificar ou copiar os materiais;</li>
        <li style={{ marginBottom: '8px' }}>usar os materiais para qualquer finalidade comercial ou para exibição pública (comercial ou não comercial);</li>
        <li style={{ marginBottom: '8px' }}>tentar descompilar ou fazer engenharia reversa de qualquer software contido no site PIXELRY;</li>
        <li style={{ marginBottom: '8px' }}>remover quaisquer direitos autorais ou outras notações de propriedade dos materiais; ou</li>
        <li style={{ marginBottom: '8px' }}>transferir os materiais para outra pessoa ou 'espelhe' os materiais em qualquer outro servidor.</li>
      </ul>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>3. Isenção de responsabilidade</h2>
      <p style={{ marginBottom: '24px' }}>
        Os materiais no site da PIXELRY são fornecidos 'como estão'. A PIXELRY não oferece garantias, expressas ou implícitas, e, por este meio, isenta e nega todas as outras garantias, incluindo, sem limitação, garantias implícitas ou condições de comercialização, adequação a um fim específico ou não violação de propriedade intelectual ou outra violação de direitos.
      </p>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>4. Limitações</h2>
      <p style={{ marginBottom: '24px' }}>
        Em nenhum caso a PIXELRY ou seus fornecedores serão responsáveis por quaisquer danos (incluindo, sem limitação, danos por perda de dados ou lucro ou devido a interrupção dos negócios) decorrentes do uso ou da incapacidade de usar os materiais em PIXELRY.
      </p>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>5. Modificações</h2>
      <p style={{ marginBottom: '24px' }}>
        A PIXELRY pode revisar estes termos de serviço do site a qualquer momento, sem aviso prévio. Ao usar este site, você concorda em ficar vinculado à versão atual desses termos de serviço.
      </p>

      <h2 style={{ fontSize: '1.5rem', marginTop: '32px', marginBottom: '16px' }}>6. Lei Aplicável</h2>
      <p style={{ marginBottom: '24px' }}>
        Estes termos e condições são regidos e interpretados de acordo com as leis do Brasil e você se submete irrevogavelmente à jurisdição exclusiva dos tribunais naquele estado ou localidade.
      </p>
    </div>
  );
}
