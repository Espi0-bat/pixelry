import html2canvas from 'html2canvas';

export const shatterElement = async (element, options = {}) => {
  const {
    particleSize = 10,
    totalDuration = 1400,
    flashDuration = 180,
    onComplete
  } = options;

  element.style.pointerEvents = 'none';

  const sourceCanvas = await html2canvas(element, {
    backgroundColor: null,
    scale: window.devicePixelRatio || 1,
    logging: false,
    useCORS: true,
  });

  const rect = element.getBoundingClientRect();
  const W = rect.width;
  const H = rect.height;

  const overlay = document.createElement('canvas');
  overlay.width  = window.innerWidth;
  overlay.height = window.innerHeight;
  Object.assign(overlay.style, {
    position: 'fixed',
    top: '0',
    left: '0',
    width: '100vw',
    height: '100vh',
    zIndex: '99999',
    pointerEvents: 'none',
  });
  document.body.appendChild(overlay);
  const ctx = overlay.getContext('2d');

  element.style.visibility = 'hidden';

  const cols = Math.ceil(W / particleSize);
  const rows = Math.ceil(H / particleSize);

  const srcCtx = sourceCanvas.getContext('2d');
  const scaleX = sourceCanvas.width  / W;
  const scaleY = sourceCanvas.height / H;

  const particles = [];

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const sx = Math.floor((c * particleSize + particleSize / 2) * scaleX);
      const sy = Math.floor((r * particleSize + particleSize / 2) * scaleY);
      const px = srcCtx.getImageData(sx, sy, 1, 1).data;
      if (px[3] < 10) continue;

      const x0 = rect.left + c * particleSize;
      const y0 = rect.top  + r * particleSize;

      const dx = (c - cols / 2) / (cols / 2);
      const dy = (r - rows / 2) / (rows / 2);
      const dist = Math.sqrt(dx * dx + dy * dy);

      const speed = (0.8 + dist * 1.4) * (2.5 + Math.random() * 3.5);
      const angle = Math.atan2(dy, dx) + (Math.random() - 0.5) * 0.9;

      const waveDelay = dist * 180 + Math.random() * 60;

      particles.push({
        x: x0, y: y0,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed - Math.random() * 2,
        rot: 0,
        vrot: (Math.random() - 0.5) * 12,
        alpha: 1,
        size: particleSize,
        color: `rgba(${px[0]},${px[1]},${px[2]},1)`,
        r: px[0], g: px[1], b: px[2],
        delay: waveDelay,
        started: false,
      });
    }
  }

  const gravity   = 0.18;
  const friction  = 0.97;
  const startTime = performance.now();

  let flashActive = true;

  const draw = (now) => {
    const elapsed = now - startTime;
    ctx.clearRect(0, 0, overlay.width, overlay.height);

    if (flashActive) {
      const fp = Math.min(elapsed / flashDuration, 1);
      const flashAlpha = fp < 0.5 ? fp * 2 : 1 - (fp - 0.5) * 2;
      ctx.save();
      ctx.fillStyle = `rgba(200,180,255,${flashAlpha * 0.55})`;
      ctx.fillRect(rect.left, rect.top, W, H);
      ctx.restore();
      if (fp >= 1) flashActive = false;
    }

    let anyAlive = false;

    for (const p of particles) {
      if (elapsed < p.delay) {
        ctx.save();
        ctx.globalAlpha = 1;
        ctx.fillStyle = p.color;
        ctx.fillRect(p.x, p.y, p.size, p.size);
        ctx.shadowColor = `rgba(${p.r},${p.g},${p.b},0.6)`;
        ctx.shadowBlur = 4;
        ctx.fillRect(p.x, p.y, p.size, p.size);
        ctx.restore();
        anyAlive = true;
        continue;
      }

      const life = elapsed - p.delay;
      const lifeFrac = life / (totalDuration - p.delay);

      p.vx *= friction;
      p.vy  = p.vy * friction + gravity;
      p.x  += p.vx;
      p.y  += p.vy;
      p.rot += p.vrot;
      p.alpha = Math.max(0, 1 - lifeFrac * 1.6);

      if (p.alpha <= 0) continue;
      anyAlive = true;

      const half = p.size / 2;

      ctx.save();
      ctx.translate(p.x + half, p.y + half);
      ctx.rotate((p.rot * Math.PI) / 180);
      ctx.globalAlpha = p.alpha;

      const glowIntensity = p.alpha * 12;
      ctx.shadowColor = `rgba(160,100,255,${p.alpha * 0.9})`;
      ctx.shadowBlur  = glowIntensity;

      ctx.fillStyle = p.color;
      ctx.fillRect(-half, -half, p.size, p.size);

      ctx.strokeStyle = `rgba(220,190,255,${p.alpha * 0.4})`;
      ctx.lineWidth = 0.5;
      ctx.strokeRect(-half, -half, p.size, p.size);

      ctx.restore();
    }

    if (anyAlive && elapsed < totalDuration + 400) {
      requestAnimationFrame(draw);
    } else {
      if (document.body.contains(overlay)) {
        document.body.removeChild(overlay);
      }
      if (onComplete) onComplete();
    }
  };

  requestAnimationFrame(draw);
};
