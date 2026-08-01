const KUWAIT_GOVERNORATES = [
  'العاصمة',
  'حولي',
  'الفروانية',
  'الجهراء',
  'مبارك الكبير',
  'الأحمدي',
];

const GOVERNORATE_ALIASES = {
  احمد: 'الأحمدي',
  أحمد: 'الأحمدي',
  احمدي: 'الأحمدي',
  أحمدي: 'الأحمدي',
  العاصمه: 'العاصمة',
  capital: 'العاصمة',
};

const HEADER_MAP = {
  governorate: 'governorate',
  'governorate name': 'governorate',
  governorate_name: 'governorate',
  المحافظة: 'governorate',
  محافظة: 'governorate',
  areaname: 'areaName',
  area_name: 'areaName',
  area: 'areaName',
  'area name': 'areaName',
  المنطقة: 'areaName',
  منطقة: 'areaName',
  deliveryfee: 'deliveryFee',
  delivery_fee: 'deliveryFee',
  fee: 'deliveryFee',
  'delivery fee': 'deliveryFee',
  رسوم_التوصيل: 'deliveryFee',
  'رسوم التوصيل': 'deliveryFee',
  رسوم: 'deliveryFee',
  isactive: 'isActive',
  is_active: 'isActive',
  active: 'isActive',
  نشط: 'isActive',
  enabled: 'isActive',
};

const CSV_TEMPLATE = [
  'governorate,areaName,deliveryFee,isActive',
  'حولي,السالمية,1.000,true',
  'الفروانية,جليب الشيوخ,1.500,true',
  'الأحمدي,الفحيحيل,2.000,true',
].join('\n');

function normalizeGovernorate(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  const alias = GOVERNORATE_ALIASES[raw] || GOVERNORATE_ALIASES[raw.toLowerCase()];
  if (alias) return alias;
  const match = KUWAIT_GOVERNORATES.find(
    (entry) => entry.toLowerCase() === raw.toLowerCase(),
  );
  return match || raw;
}

function parseBoolean(value, fallback = true) {
  if (value == null || value === '') return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (['false', '0', 'no', 'off', 'inactive', 'لا', 'غير نشط'].includes(normalized)) {
    return false;
  }
  if (['true', '1', 'yes', 'on', 'active', 'نعم', 'نشط'].includes(normalized)) {
    return true;
  }
  return fallback;
}

function parseCsvLine(line) {
  const cells = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i += 1) {
    const char = line[i];
    if (char === '"') {
      if (inQuotes && line[i + 1] === '"') {
        current += '"';
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (char === ',' && !inQuotes) {
      cells.push(current.trim());
      current = '';
      continue;
    }
    current += char;
  }
  cells.push(current.trim());
  return cells;
}

function normalizeHeader(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/^\uFEFF/, '');
}

function mapHeaderToField(header) {
  const key = normalizeHeader(header);
  return HEADER_MAP[key] || null;
}

function parseDeliveryZonesCsv(csvText) {
  const text = String(csvText || '').replace(/^\uFEFF/, '').trim();
  if (!text) {
    throw new Error('CSV file is empty');
  }

  const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length < 2) {
    throw new Error('CSV must include a header row and at least one data row');
  }

  const headerCells = parseCsvLine(lines[0]);
  const fieldIndexes = headerCells.map((header) => mapHeaderToField(header));

  if (!fieldIndexes.includes('governorate') || !fieldIndexes.includes('areaName')) {
    throw new Error(
      'CSV headers must include governorate (المحافظة) and areaName (المنطقة)',
    );
  }

  const rows = [];
  const errors = [];

  for (let lineIndex = 1; lineIndex < lines.length; lineIndex += 1) {
    const cells = parseCsvLine(lines[lineIndex]);
    const record = {
      governorate: '',
      areaName: '',
      deliveryFee: 0,
      isActive: true,
    };

    for (let col = 0; col < fieldIndexes.length; col += 1) {
      const field = fieldIndexes[col];
      if (!field) continue;
      record[field] = cells[col] ?? '';
    }

    const governorate = normalizeGovernorate(record.governorate);
    const areaName = String(record.areaName || '').trim();
    const deliveryFee = Number(String(record.deliveryFee || '0').replace(',', '.')) || 0;
    const isActive = parseBoolean(record.isActive, true);
    const rowNumber = lineIndex + 1;

    if (!governorate || !areaName) {
      errors.push({ row: rowNumber, error: 'Missing governorate or area name' });
      continue;
    }

    const knownGovernorate = KUWAIT_GOVERNORATES.some(
      (entry) => entry.toLowerCase() === governorate.toLowerCase(),
    );
    if (!knownGovernorate) {
      errors.push({
        row: rowNumber,
        error: `Unknown governorate "${governorate}" — use one of: ${KUWAIT_GOVERNORATES.join(', ')}`,
      });
      continue;
    }

    rows.push({
      governorate,
      areaName,
      deliveryFee: Math.max(0, deliveryFee),
      isActive,
      row: rowNumber,
    });
  }

  return { rows, errors };
}

function zoneIdentityKey(governorate, areaName) {
  return `${String(governorate).trim().toLowerCase()}::${String(areaName).trim().toLowerCase()}`;
}

function importDeliveryZonesForRestaurant({
  existingZones,
  rows,
  restaurantId,
  normalizeDeliveryZone,
}) {
  const scopedId = String(restaurantId);
  const restaurantZones = (existingZones || []).filter(
    (zone) =>
      String(zone.restaurant_id || zone.restaurantId) === scopedId,
  );
  const otherZones = (existingZones || []).filter(
    (zone) =>
      String(zone.restaurant_id || zone.restaurantId) !== scopedId,
  );

  const indexByKey = new Map();
  restaurantZones.forEach((zone, index) => {
    indexByKey.set(
      zoneIdentityKey(zone.governorate, zone.areaName || zone.area_name),
      index,
    );
  });

  let added = 0;
  let updated = 0;
  const now = new Date().toISOString();

  for (const row of rows) {
    const key = zoneIdentityKey(row.governorate, row.areaName);
    const existingIndex = indexByKey.get(key);

    if (existingIndex != null) {
      const zone = restaurantZones[existingIndex];
      zone.governorate = row.governorate;
      zone.areaName = row.areaName;
      zone.deliveryFee = row.deliveryFee;
      zone.isActive = row.isActive;
      zone.updatedAt = now;
      updated += 1;
      continue;
    }

    const id = `zone_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const created = normalizeDeliveryZone(
      {
        governorate: row.governorate,
        areaName: row.areaName,
        deliveryFee: row.deliveryFee,
        isActive: row.isActive,
        createdAt: now,
        updatedAt: now,
      },
      id,
      scopedId,
    );
    restaurantZones.push(created);
    indexByKey.set(key, restaurantZones.length - 1);
    added += 1;
  }

  return {
    zones: [...otherZones, ...restaurantZones],
    summary: {
      added,
      updated,
      totalRows: rows.length,
    },
  };
}

module.exports = {
  CSV_TEMPLATE,
  KUWAIT_GOVERNORATES,
  normalizeGovernorate,
  parseDeliveryZonesCsv,
  importDeliveryZonesForRestaurant,
};
