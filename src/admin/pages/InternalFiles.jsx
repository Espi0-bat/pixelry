import React, { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { FileArchive, Download, Clock } from 'lucide-react';
import { useOutletContext } from 'react-router-dom';
import { supabase } from '../../config/supabase';
import './InternalFiles.css';

function formatTime(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit', month: '2-digit', year: '2-digit',
    hour: '2-digit', minute: '2-digit',
  });
}

export default function InternalFiles() {
  const ctx = useOutletContext() || {};
  const authUser = ctx.user;

  const [files, setFiles]     = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!authUser?.id) return;
    loadFiles();
  }, [authUser?.id]);

  async function loadFiles() {
    const { data } = await supabase
      .from('internal_files')
      .select('id, from_id, to_id, file_url, file_name, file_size, message, created_at, read_at')
      .or(`from_id.eq.${authUser.id},to_id.eq.${authUser.id}`)
      .order('created_at', { ascending: false });
    setFiles(data || []);
    setLoading(false);

    // Mark unread as read
    if (data?.some(f => !f.read_at && f.to_id === authUser.id)) {
      await supabase
        .from('internal_files')
        .update({ read_at: new Date().toISOString() })
        .eq('to_id', authUser.id)
        .is('read_at', null);
    }
  }

  const unread = files.filter(f => !f.read_at && f.to_id === authUser?.id).length;

  return (
    <div className="ifiles-container">
      <div className="ifiles-header">
        <div>
          <h1 className="ifiles-title">Arquivos</h1>
          <p className="ifiles-sub">Arquivos enviados pela equipe para você.</p>
        </div>
        {unread > 0 && (
          <div className="ifiles-unread-badge">{unread} novo{unread > 1 ? 's' : ''}</div>
        )}
      </div>

      {loading ? (
        <div className="ifiles-state">Carregando arquivos...</div>
      ) : files.length === 0 ? (
        <div className="ifiles-empty">
          <FileArchive size={36} strokeWidth={1.5} style={{ color: 'rgba(128,64,245,0.3)', marginBottom: 10 }} />
          <p>Nenhum arquivo recebido ainda.</p>
        </div>
      ) : (
        <div className="ifiles-list">
          {files.map((file, idx) => {
            const isReceived = file.to_id === authUser?.id;
            const isNew = isReceived && !file.read_at;
            return (
              <motion.div
                key={file.id}
                className={`ifile-row${isNew ? ' new' : ''}`}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: idx * 0.04 }}
              >
                <div className="ifile-icon">
                  <FileArchive size={18} />
                </div>
                <div className="ifile-info">
                  <div className="ifile-name">{file.file_name}</div>
                  {file.message && <div className="ifile-msg">"{file.message}"</div>}
                  <div className="ifile-meta">
                    <Clock size={11} />
                    {formatTime(file.created_at)}
                    {file.file_size && ` · ${file.file_size}`}
                    {isReceived
                      ? <span className="ifile-direction received">Recebido</span>
                      : <span className="ifile-direction sent">Enviado</span>
                    }
                  </div>
                </div>
                <a
                  href={file.file_url}
                  target="_blank"
                  rel="noreferrer"
                  className="ifile-dl"
                  download
                >
                  <Download size={15} />
                  Baixar
                </a>
              </motion.div>
            );
          })}
        </div>
      )}
    </div>
  );
}
