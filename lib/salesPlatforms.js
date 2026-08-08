const DEFAULT_SALES_PLATFORMS = [
  {
    id: 'pos',
    name: 'محلي / POS',
    commissionPercent: 0,
    color: '#6B1124',
    isBuiltIn: true,
  },
  {
    id: 'talabat',
    name: 'Talabat',
    commissionPercent: 15,
    color: '#FF5A00',
    isBuiltIn: true,
  },
  {
    id: 'keeta',
    name: 'Keeta',
    commissionPercent: 12,
    color: '#00A651',
    isBuiltIn: true,
  },
  {
    id: 'jahez',
    name: 'Jahez',
    commissionPercent: 12,
    color: '#E4002B',
    isBuiltIn: true,
  },
];

function normalizeSalesPlatforms(raw) {
  if (!Array.isArray(raw) || raw.length === 0) {
    return DEFAULT_SALES_PLATFORMS.map((row) => ({ ...row }));
  }

  const byId = new Map(
    DEFAULT_SALES_PLATFORMS.map((row) => [row.id, { ...row }]),
  );

  for (const row of raw) {
    if (!row || typeof row !== 'object') continue;
    const id = String(row.id || row.key || '').trim().toLowerCase();
    if (!id) continue;
    const base = byId.get(id) || {
      id,
      name: String(row.name || row.label || id).trim(),
      commissionPercent: 0,
      color: '#475569',
      isBuiltIn: false,
    };
    byId.set(id, {
      id,
      name: String(row.name || row.label || base.name || id).trim(),
      commissionPercent:
        Number(row.commissionPercent ?? row.commission_percent ?? base.commissionPercent) || 0,
      color: String(row.color || row.colorArgb || row.color_argb || base.color || '#475569'),
      isBuiltIn:
        row.isBuiltIn === true ||
        row.is_built_in === true ||
        base.isBuiltIn === true,
    });
  }

  const ordered = DEFAULT_SALES_PLATFORMS.map(
    (row) => byId.get(row.id) || { ...row },
  );
  for (const [id, row] of byId.entries()) {
    if (!DEFAULT_SALES_PLATFORMS.some((entry) => entry.id === id)) {
      ordered.push(row);
    }
  }
  return ordered;
}

module.exports = {
  DEFAULT_SALES_PLATFORMS,
  normalizeSalesPlatforms,
};
