const http = require('http');
const fs = require('fs');
const path = require('path');
const {
  persistMenuItemsImages,
  serveMenuImage,
  ensureUploadDir,
  mapItemsForPublicApi,
} = require('./lib/menuImageStorage');
const {
  ROLES,
  DEFAULT_RESTAURANT_ID,
  loginSuperAdmin,
  loginRestaurantAdmin,
  loginCashierSession,
  findRestaurantByNameOrSlug,
  parseAuthHeader,
  verifyToken,
  buildAuthResponse,
  isSuperAdmin,
  isRestaurantAdmin,
  isCashier,
  canAccessRestaurant,
  resolveRestaurantId,
  authError,
} = require('./lib/adminAuth');
const {
  ensureRestaurantId,
  filterByRestaurant,
  migrateSettingsShape,
  defaultSettingsPayload,
  sanitizeRestaurant,
  sanitizeRestaurantAdmin,
  createRestaurantRecord,
  updateRestaurantRecord,
  normalizeRestaurantSlug,
  resolveRestaurantFromQuery,
  assertRestaurantAccess,
  nextNumericItemId,
} = require('./lib/tenantStore');

function warmMenuImageBundle() {
  const roots = [
    path.join(__dirname, 'uploads', 'menu'),
    path.join(__dirname, 'public', 'menu-images'),
  ];

  for (const root of roots) {
    if (!fs.existsSync(root)) continue;
    for (const filename of fs.readdirSync(root)) {
      if (filename.startsWith('.')) continue;
      try {
        fs.readFileSync(path.join(root, filename));
      } catch (_) {}
    }
  }
}

warmMenuImageBundle();

const { scrapeTalabatMenu } = require('./lib/talabatScraper');
const { translateCategoryName } = require('./lib/bilingualMenu');
const { normalizeWhatsappSettings } = require('./lib/whatsappPhone');
const {
  normalizePhoneDigits,
  phonesMatch,
  customerProfileFromRecord,
  customerProfileFromOrder,
  findCustomerByPhone,
  upsertCustomerFromSource,
  enrichCustomersForRestaurant,
  formatCustomerAddress,
} = require('./lib/customersStore');
const {
  ensureAutoTranslatedBilingual,
  ensureAutoTranslatedCategory,
} = require('./lib/autoTranslate');
const { normalizeMenuItemsForApi, autoTranslateMenuItems } = require('./lib/bilingualItemMigration');
const {
  applyPostCheckoutRewards,
  buildCheckoutPreview,
} = require('./lib/smartClosingEngine');
const {
  validatePersonalPromo,
  redeemPersonalPromo,
  round3: roundPromo3,
} = require('./lib/personalPromoCodes');
const {
  validateWalletPromo,
  validateWalletAmount,
  redeemWalletPromo,
  redeemWalletAmount,
  generateWalletPromoCode,
  readWalletBalance,
} = require('./lib/walletPromoCodes');
const {
  buildDeliveryNotificationPayload,
} = require('./lib/deliveryWhatsAppMessage');
const { previewEarnedCashback, applyLoyaltyCashbackToOrder } = require('./lib/loyaltyCashback');
const { computeTopMenuItems } = require('./lib/topItemsAnalytics');
const { computeFoodCostReport } = require('./lib/foodCostReportAnalytics');
const { computeDailySalesAnalytics } = require('./lib/platformSalesAnalytics');
const { enrichPlatformRows } = require('./lib/platformChannelUtils');
const { normalizeSalesPlatforms } = require('./lib/salesPlatforms');
const { normalizePosRoles } = require('./lib/posPermissions');
const { handlePosRoutes } = require('./lib/posRoutes');
const { handleKitchenRoutes } = require('./lib/kitchenRoutes');
const { handleDeliveryZoneRoutes } = require('./lib/deliveryZoneRoutes');
const {
  buildRestaurantOgData,
  buildOgMenuHtml,
  DEFAULT_FRONTEND_ORIGIN,
} = require('./lib/ogMenuMeta');
const { computeCartRecommendations } = require('./lib/recommendationsAnalytics');
const {
  assignTargetKitchen,
  getActiveKitchens,
  getDefaultKitchen,
  normalizeKitchen,
  kitchenRestaurantId,
} = require('./lib/kitchenRouting');
const {
  initDataStore,
  usesMongo,
  getStorageStatus,
  readItems,
  writeItems,
  readOrders,
  writeOrders,
  readCustomers,
  writeCustomers,
  ensureCustomersMigrated,
  readRestaurants,
  writeRestaurants,
  readSettingsMap,
  writeSettingsMap,
  readDeliveryZones,
  writeDeliveryZones,
  readKitchens,
  writeKitchens,
  readStaffUsers,
  writeStaffUsers,
  readShiftSessions,
  writeShiftSessions,
  appendAuditEvents,
  ensureBilingualMenuItemsFast,
  ensureBilingualMenuItemsWithAutoTranslate,
} = require('./lib/dataStore');

const PORT = Number(process.env.PORT) || 3000;
const IS_VERCEL = Boolean(process.env.VERCEL);

const categoryIds = new Map();
let nextCategoryId = 1;
let storeReady = initDataStore();

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Restaurant-Id',
  });
  res.end(JSON.stringify(payload));
}

function sendHtml(res, statusCode, html) {
  res.writeHead(statusCode, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'public, max-age=300',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(html);
}

function requestOrigin(req) {
  const proto = String(req.headers['x-forwarded-proto'] || 'https')
    .split(',')[0]
    .trim();
  const host = String(
    req.headers['x-forwarded-host'] || req.headers.host || 'almenupro-backend.vercel.app',
  )
    .split(',')[0]
    .trim();
  return `${proto}://${host}`;
}

const ALLOWED_IMAGE_HOSTS = new Set([
  'images.deliveryhero.io',
  'deliveryhero.io',
]);

function isAllowedImageUrl(rawUrl) {
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== 'https:') return false;
    const host = parsed.hostname.toLowerCase();
    if (
      [...ALLOWED_IMAGE_HOSTS].some(
        (allowed) => host === allowed || host.endsWith(`.${allowed}`),
      )
    ) {
      return true;
    }
    const path = parsed.pathname.toLowerCase();
    return /\.(png|jpe?g|gif|webp|svg|avif|ico)(\?|$)/i.test(path);
  } catch {
    return false;
  }
}

async function proxyImage(res, rawUrl) {
  if (!isAllowedImageUrl(rawUrl)) {
    sendJson(res, 400, { error: 'Invalid or disallowed image URL' });
    return;
  }

  try {
    const upstream = await fetch(rawUrl, {
      headers: {
        'User-Agent': 'AlmenuproImageProxy/1.0',
        Accept: 'image/*,*/*;q=0.8',
      },
    });

    if (!upstream.ok) {
      sendJson(res, upstream.status, { error: 'Failed to fetch image' });
      return;
    }

    const contentType = upstream.headers.get('content-type') || 'image/jpeg';
    const buffer = Buffer.from(await upstream.arrayBuffer());

    res.writeHead(200, {
      'Content-Type': contentType,
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'public, max-age=86400, immutable',
    });
    res.end(buffer);
  } catch (error) {
    sendJson(res, 502, { error: error.message || 'Image proxy failed' });
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

function normalizeSettings(raw) {
  const base = defaultSettingsPayload();
  const source = raw && typeof raw === 'object' ? raw : {};
  const workingHours = Array.isArray(source.workingHours) && source.workingHours.length
    ? source.workingHours
    : base.workingHours;
  const whatsapp = normalizeWhatsappSettings(source);

  return {
    ...whatsapp,
    workingHours: workingHours.map((day) => ({
      weekday: Number(day.weekday) || 6,
      isOpen: day.isOpen !== false && day.is_open !== false,
      open: String(day.open || day.openTime || '10:00'),
      close: String(day.close || day.closeTime || '22:00'),
    })),
    smartUpsellEnabled: source.smartUpsellEnabled !== false,
    freeDeliveryThreshold:
      Number(source.freeDeliveryThreshold ?? source.free_delivery_threshold ?? 0) || 0,
    impulseBumpItemIds: Array.isArray(source.impulseBumpItemIds)
      ? source.impulseBumpItemIds
          .map((id) => Number(id))
          .filter((id) => Number.isFinite(id) && id > 0)
      : [],
    impulseBumpMaxPrice:
      Number(source.impulseBumpMaxPrice ?? source.impulse_bump_max_price ?? 2) || 2,
    smartRecommendationsEnabled: source.smartRecommendationsEnabled !== false,
    smartClosingEnabled:
      source.smartClosingEnabled !== false && source.smart_closing_enabled !== false,
    cashbackType: String(
      source.cashbackType ?? source.cashback_type ?? 'PERCENTAGE',
    ).toUpperCase(),
    cashbackValue:
      Number(source.cashbackValue ?? source.cashback_value ?? 0) || 0,
    minOrderForLoyalty:
      Number(source.minOrderForLoyalty ?? source.min_order_for_loyalty ?? 0) || 0,
    loyaltyEnabled:
      source.loyaltyEnabled !== false && source.loyalty_enabled !== false,
    logoUrl: String(source.logoUrl ?? source.logo_url ?? '').trim(),
    restaurantDescription: String(
      source.restaurantDescription ?? source.restaurant_description ?? '',
    ).trim(),
    salesPlatforms: normalizeSalesPlatforms(
      source.salesPlatforms || source.sales_platforms,
    ),
    posRoles: normalizePosRoles(source.posRoles || source.pos_roles),
    posAutoLockMinutes:
      Number(source.posAutoLockMinutes ?? source.pos_auto_lock_minutes ?? 5) || 5,
    notificationEmail: String(
      source.notificationEmail ?? source.notification_email ?? '',
    ).trim(),
    notifyOnNewOrderEmail:
      source.notifyOnNewOrderEmail !== false &&
      source.notify_on_new_order_email !== false,
    notifyOnShiftCloseEmail:
      source.notifyOnShiftCloseEmail === true ||
      source.notify_on_shift_close_email === true,
    updatedAt: source.updatedAt || new Date().toISOString(),
  };
}

async function readSettings(restaurantId = DEFAULT_RESTAURANT_ID) {
  const map = await readSettingsMap();
  const scoped = map.byRestaurant?.[restaurantId];
  return normalizeSettings(scoped || defaultSettingsPayload());
}

async function writeSettings(restaurantId, settings) {
  const map = await readSettingsMap();
  if (!map.byRestaurant || typeof map.byRestaurant !== 'object') {
    map.byRestaurant = {};
  }
  map.byRestaurant[restaurantId] = normalizeSettings(settings);
  await writeSettingsMap(map);
  return map.byRestaurant[restaurantId];
}

function assertOrderItemsBelongToRestaurant(body, restaurantId, menuItems) {
  const allowedIds = new Set(
    (menuItems || []).map((entry) => String(entry.id)),
  );
  const orderItems = Array.isArray(body.items) ? body.items : [];
  for (const line of orderItems) {
    const menuItemId = String(
      line.menuItemId ?? line.menu_item_id ?? '',
    ).trim();
    if (!menuItemId) continue;
    if (!allowedIds.has(menuItemId)) {
      return {
        ok: false,
        error: `Menu item ${menuItemId} does not belong to this restaurant`,
        code: 'ORDER_ITEM_TENANT_MISMATCH',
      };
    }
  }
  return { ok: true };
}

function normalizeOrder(raw, id, restaurantId = DEFAULT_RESTAURANT_ID) {
  const createdAt = raw.createdAt || new Date().toISOString();
  const items = Array.isArray(raw.items) ? raw.items : [];
  const itemsSubtotal = items.reduce(
    (sum, item) => sum + (Number(item.lineTotal ?? item.line_total) || 0),
    0,
  );
  const subtotal = Number(raw.subtotal ?? raw.sub_total ?? itemsSubtotal) || 0;
  const deliveryFee = Number(raw.deliveryFee ?? raw.delivery_fee ?? 0) || 0;
  const promoDiscount = roundPromo3(raw.promoDiscount ?? raw.promo_discount ?? 0);
  const promoCode = String(raw.promoCode ?? raw.promo_code ?? '').trim();
  const walletDiscount = roundPromo3(raw.walletDiscount ?? raw.wallet_discount ?? 0);
  const walletCode = String(raw.walletCode ?? raw.wallet_code ?? '').trim();
  const totalFromBody = Number(raw.totalPrice ?? raw.total_price ?? 0) || 0;
  const computedTotal = Math.max(
    0,
    subtotal + deliveryFee - promoDiscount - walletDiscount,
  );
  const totalPrice = totalFromBody > 0 ? totalFromBody : computedTotal;

  const addressDetailsRaw = raw.addressDetails || raw.address_details || {};
  const addressDetails = {
    block: String(addressDetailsRaw.block || raw.block || '').trim(),
    street: String(addressDetailsRaw.street || raw.street || '').trim(),
    avenue: String(addressDetailsRaw.avenue || raw.avenue || '').trim(),
    houseNumber: String(
      addressDetailsRaw.houseNumber ||
        addressDetailsRaw.house_number ||
        raw.houseNumber ||
        raw.house_number ||
        '',
    ).trim(),
    floorApartment: String(
      addressDetailsRaw.floorApartment ||
        addressDetailsRaw.floor_apartment ||
        raw.floorApartment ||
        raw.floor_apartment ||
        '',
    ).trim(),
  };

  let address = String(raw.address || '').trim();
  if (!address) {
    const parts = [
      raw.governorate,
      raw.areaName || raw.area_name,
      addressDetails.block ? `قطعة ${addressDetails.block}` : '',
      addressDetails.street ? `شارع ${addressDetails.street}` : '',
      addressDetails.avenue ? `جادة ${addressDetails.avenue}` : '',
      addressDetails.houseNumber ? `مبنى ${addressDetails.houseNumber}` : '',
      addressDetails.floorApartment ? `طابق/شقة ${addressDetails.floorApartment}` : '',
    ].filter(Boolean);
    address = parts.join('، ');
  }

  return ensureRestaurantId(
    {
      id: String(id),
      customerName: String(raw.customerName || raw.customer_name || '').trim(),
      phone: String(raw.phone || '').trim(),
      address,
      governorate: String(raw.governorate || '').trim(),
      areaName: String(raw.areaName || raw.area_name || '').trim(),
      deliveryZoneId: raw.deliveryZoneId?.toString() || raw.delivery_zone_id?.toString() || null,
      addressDetails,
      items,
      subtotal,
      deliveryFee,
      promoCode: promoCode || null,
      promoDiscount,
      promo_code: promoCode || null,
      promo_discount: promoDiscount,
      walletCode: walletCode || null,
      walletDiscount,
      wallet_code: walletCode || null,
      wallet_discount: walletDiscount,
      totalPrice,
      orderType: String(raw.orderType || raw.order_type || 'Delivery'),
      status: String(raw.status || 'pending'),
      createdAt,
      invoiceNumber: raw.invoiceNumber?.toString() || raw.invoice_number?.toString() || null,
      paymentMethod: raw.paymentMethod?.toString() || raw.payment_method?.toString() || null,
      orderSource: String(raw.orderSource || raw.order_source || '').trim() || null,
      externalOrderId: String(
        raw.externalOrderId || raw.external_order_id || '',
      ).trim() || null,
      platformGrossTotal:
        Number(raw.platformGrossTotal ?? raw.platform_gross_total ?? 0) || null,
      platformCommission:
        Number(raw.platformCommission ?? raw.platform_commission ?? 0) || null,
      platformCommissionPercent:
        Number(
          raw.platformCommissionPercent ?? raw.platform_commission_percent ?? 0,
        ) || null,
      targetKitchenId:
        String(raw.targetKitchenId || raw.target_kitchen_id || '').trim() || null,
      target_kitchen_id:
        String(raw.targetKitchenId || raw.target_kitchen_id || '').trim() || null,
      targetKitchenName:
        String(raw.targetKitchenName || raw.target_kitchen_name || '').trim() || null,
      target_kitchen_name:
        String(raw.targetKitchenName || raw.target_kitchen_name || '').trim() || null,
      kitchenAssignment: raw.kitchenAssignment || raw.kitchen_assignment || null,
      kitchen_assignment: raw.kitchenAssignment || raw.kitchen_assignment || null,
      cashierId: String(raw.cashierId || raw.cashier_id || '').trim() || null,
      cashier_id: String(raw.cashierId || raw.cashier_id || '').trim() || null,
      cashierName: String(raw.cashierName || raw.cashier_name || '').trim() || null,
      cashier_name: String(raw.cashierName || raw.cashier_name || '').trim() || null,
    },
    raw.restaurant_id || raw.restaurantId || restaurantId,
  );
}

function normalizeDeliveryZone(raw, id, restaurantId = DEFAULT_RESTAURANT_ID) {
  const defaultKitchenId = String(
    raw.defaultKitchenId ||
      raw.default_kitchen_id ||
      raw.kitchenId ||
      raw.kitchen_id ||
      '',
  ).trim();

  return ensureRestaurantId(
    {
      id: String(id),
      governorate: String(raw.governorate || raw.governorateName || '').trim(),
      areaName: String(raw.areaName || raw.area_name || '').trim(),
      deliveryFee: Number(raw.deliveryFee ?? raw.delivery_fee ?? 0) || 0,
      defaultKitchenId: defaultKitchenId || null,
      default_kitchen_id: defaultKitchenId || null,
      isActive:
        raw.isActive === false ||
        raw.is_active === false ||
        raw.isActive === 0 ||
        raw.is_active === 0
          ? false
          : true,
      createdAt: raw.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    restaurantId,
  );
}

function findDeliveryZoneById(zones, zoneId) {
  return zones.find((zone) => String(zone.id) === String(zoneId));
}

function sortOrdersDesc(orders) {
  return [...orders].sort((a, b) => {
    const aTime = Date.parse(a.createdAt || 0);
    const bTime = Date.parse(b.createdAt || 0);
    return bTime - aTime;
  });
}

function itemDisplayOrder(item, fallbackIndex = 0) {
  const raw = item.display_order ?? item.displayOrder;
  if (raw == null || raw === '') return fallbackIndex;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallbackIndex;
}

function parseOptionalCostPrice(body) {
  const raw = body?.costPrice ?? body?.cost_price;
  if (raw == null || raw === '') return null;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : null;
}

function applyCostPriceFields(target, body) {
  if (body == null) return;
  if (body.costPrice != null || body.cost_price != null) {
    const costPrice = parseOptionalCostPrice(body);
    if (costPrice == null) {
      delete target.costPrice;
      delete target.cost_price;
    } else {
      target.costPrice = costPrice;
      target.cost_price = costPrice;
    }
  }
}

function sortItemsByDisplayOrder(items) {
  return [...items]
    .map((item, index) => ({ item, index }))
    .sort((a, b) => {
      const left = itemDisplayOrder(a.item, a.index);
      const right = itemDisplayOrder(b.item, b.index);
      if (left !== right) return left - right;
      return Number(a.item.id) - Number(b.item.id);
    })
    .map((entry) => entry.item);
}

function maxDisplayOrder(items) {
  return items.reduce(
    (max, item, index) => Math.max(max, itemDisplayOrder(item, index)),
    -1,
  );
}

function categoryIdFor(name) {
  const key = String(name || 'عام').trim() || 'عام';
  if (!categoryIds.has(key)) {
    categoryIds.set(key, nextCategoryId++);
  }
  return categoryIds.get(key);
}

function rebuildCategoryIds(items) {
  categoryIds.clear();
  nextCategoryId = 1;
  for (const item of items) {
    categoryIdFor(item.category_name);
  }
}

function normalizeBilingualText(raw = {}) {
  const nameAr = String(raw.name_ar ?? raw.nameAr ?? raw.name ?? '').trim();
  const nameEn = String(raw.name_en ?? raw.nameEn ?? '').trim();
  const descriptionAr = String(
    raw.description_ar ?? raw.descriptionAr ?? raw.description ?? '',
  ).trim();
  const descriptionEn = String(raw.description_en ?? raw.descriptionEn ?? '').trim();
  const name = nameAr || nameEn || String(raw.name ?? '').trim();
  const description = descriptionAr || descriptionEn || String(raw.description ?? '').trim();

  return { name_ar: nameAr, name_en: nameEn, description_ar: descriptionAr, description_en: descriptionEn, name, description };
}

function normalizeMenuOptions(raw) {
  if (!Array.isArray(raw)) return [];

  return raw
    .map((opt, index) => {
      const nameAr = String(opt.name_ar ?? opt.nameAr ?? opt.name ?? '').trim();
      const nameEn = String(opt.name_en ?? opt.nameEn ?? '').trim();
      const name = nameAr || nameEn || String(opt.name ?? '').trim();
      const groupRequired = !!(
        opt.group_required ??
        opt.groupRequired ??
        opt.isRequired
      );

      return {
        id: String(opt.id || `addon_${index + 1}_${Date.now()}`),
        name,
        name_ar: nameAr,
        name_en: nameEn,
        group: String(opt.group || 'إضافات').trim() || 'إضافات',
        price: Number(opt.price) || 0,
        group_required: groupRequired,
        groupRequired,
        isRequired: groupRequired,
        allow_multiple: !!(opt.allow_multiple ?? opt.allowMultiple),
        allowMultiple: !!(opt.allow_multiple ?? opt.allowMultiple),
        is_available:
          opt.is_available === 0 ||
          opt.is_available === false ||
          opt.isAvailable === false
            ? 0
            : 1,
        isAvailable: !(
          opt.is_available === 0 ||
          opt.is_available === false ||
          opt.isAvailable === false
        ),
        ...(Number(opt.linked_menu_item_id ?? opt.linkedMenuItemId) > 0
          ? {
              linked_menu_item_id: Number(
                opt.linked_menu_item_id ?? opt.linkedMenuItemId,
              ),
              linkedMenuItemId: Number(
                opt.linked_menu_item_id ?? opt.linkedMenuItemId,
              ),
            }
          : {}),
      };
    })
    .filter((opt) => opt.name);
}

function normalizeLinkedItemIds(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((id) => Number(id))
    .filter((id) => Number.isFinite(id) && id > 0);
}

function normalizeIncoming(raw, index, restaurantId = DEFAULT_RESTAURANT_ID) {
  const categoryName =
    raw.category_name || raw.categoryName || raw.category || 'عام';
  const categoryNameEn =
    String(raw.category_name_en ?? raw.categoryNameEn ?? '').trim() ||
    translateCategoryName(categoryName);
  const talabatId = raw.talabat_id ?? raw.talabatId ?? null;
  const bilingual = normalizeBilingualText(raw);

  return ensureRestaurantId(
    {
      id: Number(raw.id ?? talabatId ?? index + 1),
      category_id: Number(raw.category_id ?? raw.categoryId ?? categoryIdFor(categoryName)),
      category_name: String(categoryName).trim() || 'عام',
      category_name_en: categoryNameEn,
      categoryNameEn: categoryNameEn,
      ...bilingual,
      price: Number(raw.price) || 0,
      image_url: String(raw.image_url || raw.imageUrl || ''),
      is_available:
        raw.is_available === 0 || raw.is_available === false || raw.isAvailable === false
          ? 0
          : 1,
      talabat_id: talabatId,
      source: raw.source || 'Talabat',
      display_order: Number(raw.display_order ?? raw.displayOrder ?? 0) || 0,
      ...(raw.options != null ? { options: normalizeMenuOptions(raw.options) } : {}),
      ...(raw.linkedItemIds != null || raw.linked_item_ids != null
        ? {
            linkedItemIds: normalizeLinkedItemIds(
              raw.linkedItemIds ?? raw.linked_item_ids,
            ),
            linked_item_ids: normalizeLinkedItemIds(
              raw.linkedItemIds ?? raw.linked_item_ids,
            ),
          }
        : {}),
    },
    restaurantId,
  );
}

function mergeItems(existing, incoming, restaurantId = DEFAULT_RESTAURANT_ID) {
  const scopedExisting = filterByRestaurant(existing, restaurantId);
  const otherRestaurants = existing.filter(
    (item) =>
      String(item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID) !==
      String(restaurantId),
  );

  const byTalabatId = new Map();
  const byId = new Map();
  const byName = new Map();
  let added = 0;
  let updated = 0;
  let skipped = 0;

  for (const item of scopedExisting) {
    if (item.talabat_id != null) byTalabatId.set(String(item.talabat_id), item);
    byId.set(String(item.id), item);
    byName.set(String(item.name || '').trim().toLowerCase(), item);
  }

  const merged = [...scopedExisting];

  incoming.forEach((raw, index) => {
    const item = normalizeIncoming(raw, index, restaurantId);
    if (!item.name) {
      skipped += 1;
      return;
    }

    const talabatKey = item.talabat_id != null ? String(item.talabat_id) : null;
    let existingItem = talabatKey ? byTalabatId.get(talabatKey) : null;
    if (!existingItem) {
      existingItem = byId.get(String(item.id)) || byName.get(item.name.toLowerCase());
    }

    if (existingItem) {
      Object.assign(existingItem, item, { id: existingItem.id });
      if (talabatKey) byTalabatId.set(talabatKey, existingItem);
      byName.set(item.name.toLowerCase(), existingItem);
      updated += 1;
      return;
    }

    merged.push(item);
    added += 1;
    byId.set(String(item.id), item);
    if (talabatKey) byTalabatId.set(talabatKey, item);
    byName.set(item.name.toLowerCase(), item);
  });

  return {
    items: [...otherRestaurants, ...merged.filter((item) => item.name)],
    added,
    updated,
    skipped,
  };
}

function requireAuth(req, res) {
  const auth = parseAuthHeader(req);
  if (!auth) {
    authError(res, 401, 'Unauthorized');
    return null;
  }
  return auth;
}

function rejectCashier(auth, res, message = 'Cashiers cannot perform this admin action') {
  if (isCashier(auth)) {
    authError(res, 403, message);
    return true;
  }
  return false;
}

function requireSuperAdmin(req, res) {
  const auth = requireAuth(req, res);
  if (!auth) return null;
  if (!isSuperAdmin(auth)) {
    authError(res, 403, 'Super admin access required');
    return null;
  }
  return auth;
}

async function resolveScopedRestaurantId(req, url, auth, { allowPublicDefault = false } = {}) {
  const restaurants = await readRestaurants();
  const slugParam =
    url.searchParams.get('restaurant_slug') || url.searchParams.get('slug');
  const restaurantIdParam =
    url.searchParams.get('restaurant_id') ||
    url.searchParams.get('restaurantId') ||
    req.headers['x-restaurant-id'];

  if (slugParam) {
    const match = restaurants.find(
      (entry) =>
        String(entry.slug || '').toLowerCase() === String(slugParam).toLowerCase(),
    );
    if (!match) return null;
    return resolveRestaurantId(auth, match.id, { allowPublicDefault });
  }

  if (restaurantIdParam) {
    return resolveRestaurantId(auth, restaurantIdParam, { allowPublicDefault });
  }

  const requested = resolveRestaurantFromQuery(url, restaurants);
  return resolveRestaurantId(auth, requested, { allowPublicDefault });
}

function findItemById(items, itemId) {
  return items.find((item) => String(item.id) === String(itemId));
}

const server = http.createServer(async (req, res) => {
  try {
    await storeReady;
  } catch (error) {
    sendJson(res, 503, { error: 'Data store unavailable', details: error.message });
    return;
  }

  if (req.method === 'OPTIONS') {
    sendJson(res, 204, {});
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);

  const kitchenHandled = await handleKitchenRoutes(req, res, url, {
    readBody,
    sendJson,
    authError,
    parseAuthHeader,
    requireAuth,
    rejectCashier,
    resolveScopedRestaurantId,
    resolveRestaurantId,
    assertRestaurantAccess,
    filterByRestaurant,
    readKitchens,
    writeKitchens,
    readOrders,
    DEFAULT_RESTAURANT_ID,
  });
  if (kitchenHandled) return;

  const deliveryZoneHandled = await handleDeliveryZoneRoutes(req, res, url, {
    readBody,
    sendJson,
    authError,
    parseAuthHeader,
    requireAuth,
    rejectCashier,
    resolveScopedRestaurantId,
    resolveRestaurantId,
    assertRestaurantAccess,
    filterByRestaurant,
    readDeliveryZones,
    writeDeliveryZones,
    DEFAULT_RESTAURANT_ID,
  });
  if (deliveryZoneHandled) return;

  const posHandled = await handlePosRoutes(req, res, url, {
    readBody,
    sendJson,
    authError,
    parseAuthHeader,
    requireAuth,
    isSuperAdmin,
    isCashier,
    assertRestaurantAccess,
    resolveScopedRestaurantId,
    filterByRestaurant,
    readSettings,
    readRestaurants,
    readStaffUsers,
    writeStaffUsers,
    readShiftSessions,
    writeShiftSessions,
    readOrders,
    writeOrders,
    appendAuditEvents,
    DEFAULT_RESTAURANT_ID,
    loginCashierSession,
    findRestaurantByNameOrSlug,
  });
  if (posHandled) return;

  if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '')) {
    sendJson(res, 200, {
      ok: true,
      service: 'almenupro-api',
      message: 'Almenupro backend is running.',
      endpoints: {
        health: '/api/health',
        auth: '/api/auth/login',
        restaurants: '/api/restaurants',
        restaurantPublic: '/api/restaurants/public',
        restaurantBySlug: '/api/restaurants/public/{slug}',
        menu: '/api/items?slug={slug}',
        topItems: '/api/analytics/top-items?slug={slug}',
        foodCostReport: '/api/analytics/food-cost-report?restaurantId={id}&days=30',
        dailySales: '/api/analytics/daily-sales?restaurantId={id}&days=7',
        recommendations: '/api/recommendations?slug={slug}&cart=1,2,3',
        customerLookup: '/api/customers/lookup?phone={phone}&slug={slug}',
        customers: '/api/customers',
        customerDetail: '/api/customers/{id}',
        orders: '/api/orders',
        settings: '/api/settings',
        kitchens: '/api/kitchens?restaurant_id={id}',
        deliveryZones: '/api/delivery-zones?restaurant_id={id}',
        images: '/menu-images/{filename}',
      },
      frontend: 'https://almenupro-frontend-three.vercel.app',
      admin: 'https://almenupro-frontend-three.vercel.app/admin',
    });
    return;
  }

  const menuImageMatch = url.pathname.match(/^\/menu-images\/([^/]+)$/);
  if (req.method === 'GET' && menuImageMatch) {
    serveMenuImage(res, decodeURIComponent(menuImageMatch[1]));
    return;
  }

  const ogMenuMatch = url.pathname.match(/^\/og\/menu\/([^/]+)$/);
  if (req.method === 'GET' && ogMenuMatch) {
    const slug = decodeURIComponent(ogMenuMatch[1]).trim().toLowerCase();
    const siteOrigin = String(url.searchParams.get('site') || DEFAULT_FRONTEND_ORIGIN).trim();
    const restaurants = await readRestaurants();
    const match = restaurants.find(
      (entry) =>
        String(entry.slug || '').toLowerCase() === slug &&
        String(entry.status || 'active') !== 'inactive',
    );

    if (!match) {
      sendHtml(
        res,
        404,
        '<!DOCTYPE html><html lang="ar"><head><meta charset="UTF-8"><title>Not found</title></head><body>Restaurant not found</body></html>',
      );
      return;
    }

    const restaurantId = String(match.id);
    const backendOrigin = requestOrigin(req);
    const settings = await readSettings(restaurantId);
    const items = filterByRestaurant(await readItems(), restaurantId);
    const restaurant = {
      ...sanitizeRestaurant(match),
      logoUrl: settings.logoUrl,
      restaurantDescription: settings.restaurantDescription,
    };
    const ogData = buildRestaurantOgData(restaurant, {
      slug,
      siteOrigin,
      frontendOrigin: siteOrigin,
      backendOrigin,
      menuItems: mapItemsForPublicApi(items, backendOrigin),
    });
    sendHtml(res, 200, buildOgMenuHtml(ogData));
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/auth/login') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      let session = null;

      if (body.username != null || body.user != null) {
        session = loginSuperAdmin(body.username ?? body.user, body.password);
      } else if (body.restaurantSlug != null || body.restaurant_slug != null) {
        session = loginRestaurantAdmin(
          body.restaurantSlug ?? body.restaurant_slug,
          body.password,
          await readRestaurants(),
        );
      }

      if (!session) {
        sendJson(res, 401, { error: 'Invalid credentials' });
        return;
      }

      sendJson(res, 200, session);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/auth/me') {
    const auth = requireAuth(req, res);
    if (!auth) return;

    const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const session = buildAuthResponse(token);
    sendJson(res, 200, session || auth);
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/restaurants') {
    const auth = requireSuperAdmin(req, res);
    if (!auth) return;

    const restaurants = (await readRestaurants()).map(sanitizeRestaurantAdmin);
    sendJson(res, 200, restaurants);
    return;
  }

  const restaurantByIdMatch = url.pathname.match(/^\/api\/restaurants\/([^/]+)$/);
  if (restaurantByIdMatch && restaurantByIdMatch[1] !== 'public') {
    const restaurantId = decodeURIComponent(restaurantByIdMatch[1]);
    const auth = requireSuperAdmin(req, res);
    if (!auth) return;

    if (req.method === 'PATCH' || req.method === 'PUT') {
      try {
        const body = JSON.parse((await readBody(req)) || '{}');
        const restaurants = await readRestaurants();
        const index = restaurants.findIndex((entry) => entry.id === restaurantId);
        if (index === -1) {
          sendJson(res, 404, { error: 'Restaurant not found' });
          return;
        }

        const nextSlug = normalizeRestaurantSlug(body.slug ?? restaurants[index].slug);
        const slugTaken = restaurants.some(
          (entry, idx) =>
            idx !== index &&
            String(entry.slug).toLowerCase() === String(nextSlug).toLowerCase(),
        );
        if (slugTaken) {
          sendJson(res, 409, { error: 'Restaurant slug already exists' });
          return;
        }

        restaurants[index] = updateRestaurantRecord(restaurants[index], body);
        await writeRestaurants(restaurants);

        const saved = restaurants[index];
        sendJson(res, 200, {
          ...sanitizeRestaurantAdmin(saved),
          menuUrl: `/menu/${saved.slug}`,
          persisted: true,
        });
      } catch (error) {
        sendJson(res, 400, {
          error: error.message || 'Invalid payload',
          code: 'UPDATE_RESTAURANT_FAILED',
        });
      }
      return;
    }
  }

  const publicRestaurantMatch = url.pathname.match(
    /^\/api\/restaurants\/public\/([^/]+)$/,
  );
  if (req.method === 'GET' && url.pathname === '/api/restaurants/public') {
    const restaurants = (await readRestaurants())
      .filter((entry) => String(entry.status || 'active') !== 'inactive')
      .map(sanitizeRestaurant);
    sendJson(res, 200, restaurants);
    return;
  }
  if (req.method === 'GET' && publicRestaurantMatch) {
    const slug = decodeURIComponent(publicRestaurantMatch[1]).trim().toLowerCase();
    const restaurants = await readRestaurants();
    const match = restaurants.find(
      (entry) =>
        String(entry.slug || '').toLowerCase() === slug &&
        String(entry.status || 'active') !== 'inactive',
    );

    if (!match) {
      sendJson(res, 404, { error: 'Restaurant not found' });
      return;
    }

    sendJson(res, 200, sanitizeRestaurant(match));
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/restaurants') {
    const auth = requireSuperAdmin(req, res);
    if (!auth) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurants = await readRestaurants();
      const record = createRestaurantRecord(body);

      if (
        restaurants.some(
          (entry) => String(entry.slug).toLowerCase() === String(record.slug).toLowerCase(),
        )
      ) {
        sendJson(res, 409, { error: 'Restaurant slug already exists' });
        return;
      }

      restaurants.push(record);
      await writeRestaurants(restaurants);
      await writeSettings(record.id, defaultSettingsPayload());

      const saved = (await readRestaurants()).find((entry) => entry.id === record.id);
      if (!saved) {
        sendJson(res, 500, { error: 'Restaurant was not persisted after save' });
        return;
      }

      sendJson(res, 201, {
        ...sanitizeRestaurantAdmin(saved),
        menuUrl: `/menu/${saved.slug}`,
        persisted: true,
      });
    } catch (error) {
      const statusCode = error.code === 'PERSISTENCE_REQUIRED' ? 503 : 400;
      sendJson(res, statusCode, {
        error: error.message || 'Invalid payload',
        code: error.code || 'CREATE_RESTAURANT_FAILED',
      });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/health') {
    const items = await readItems();
    const kitchens = await readKitchens();
    const { resolveImageDiskPath } = require('./lib/menuImageStorage');
    const storage = getStorageStatus();
    sendJson(res, 200, {
      ok: true,
      service: 'almenupro-api',
      apiVersion: 'kitchen-zones-v9',
      deployTag: 'kitchen-zones-v9-entrypoint',
      kitchensApi: true,
      deliveryZonesApi: true,
      kitchenCount: kitchens.length,
      storage: storage.mode,
      persistent: storage.persistent,
      persistenceMessage: storage.message,
      items: items.length,
      imagesReady: Boolean(resolveImageDiskPath('1962105681.jpg')),
    });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/items/migrate-bilingual') {
    const auth = requireSuperAdmin(req, res);
    if (!auth) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const targetRestaurantId =
        body.restaurantId || body.restaurant_id || url.searchParams.get('restaurant_id');

      const allItems = await readItems();
      const scoped = targetRestaurantId
        ? filterByRestaurant(allItems, targetRestaurantId)
        : allItems;

      const { items: migrated, updated, scanned } = await autoTranslateMenuItems(scoped, {
        delayMs: 150,
      });

      if (targetRestaurantId) {
        const others = allItems.filter(
          (item) =>
            String(item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID) !==
            String(targetRestaurantId),
        );
        await writeItems([...others, ...migrated]);
      } else {
        await writeItems(migrated);
      }

      sendJson(res, 200, {
        ok: true,
        updated,
        scanned,
        restaurantId: targetRestaurantId || 'all',
      });
    } catch (error) {
      sendJson(res, 500, {
        error: error.message || 'Bilingual migration failed',
      });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/analytics/top-items') {
    const auth = parseAuthHeader(req);
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });

    if (!restaurantId) {
      const slugParam =
        url.searchParams.get('restaurant_slug') || url.searchParams.get('slug');
      if (slugParam) {
        sendJson(res, 404, { error: 'Restaurant not found' });
      } else {
        authError(res, 401, 'Restaurant context required');
      }
      return;
    }

    if (auth && !canAccessRestaurant(auth, restaurantId)) {
      authError(res, 403, 'Access denied for this restaurant');
      return;
    }

    const days = Number(url.searchParams.get('days') || 90);
    const limit = Number(url.searchParams.get('limit') || 12);
    const orders = filterByRestaurant(await readOrders(), restaurantId);
    const menuItems = filterByRestaurant(await readItems(), restaurantId);
    const result = computeTopMenuItems(orders, menuItems, restaurantId, {
      days,
      limit,
    });

    sendJson(res, 200, {
      restaurantId,
      days,
      limit,
      source: result.source,
      items: result.items,
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/analytics/daily-sales') {
    const auth = requireAuth(req, res);
    if (!auth) return;

    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: false,
    });
    if (!restaurantId || !canAccessRestaurant(auth, restaurantId)) {
      authError(res, 403, 'Access denied for this restaurant');
      return;
    }

    const days = Number(url.searchParams.get('days') || 7);
    const orders = filterByRestaurant(await readOrders(), restaurantId);
    const settings = await readSettings(restaurantId);
    const analytics = computeDailySalesAnalytics(orders, restaurantId, { days });
    const platforms = enrichPlatformRows(
      analytics.platforms,
      settings.salesPlatforms || settings.sales_platforms || [],
    );

    sendJson(res, 200, {
      ...analytics,
      platforms,
      restaurantId,
      days,
      meta: {
        dataState: analytics.orderCount > 0 ? 'live' : 'no_orders',
      },
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/analytics/food-cost-report') {
    const auth = requireAuth(req, res);
    if (!auth) return;

    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: false,
    });

    if (!restaurantId) {
      authError(res, 401, 'Restaurant context required');
      return;
    }

    if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return;
    }

    const days = Number(url.searchParams.get('days') || 30);
    const startDate =
      url.searchParams.get('startDate') || url.searchParams.get('start_date');
    const endDate =
      url.searchParams.get('endDate') || url.searchParams.get('end_date');
    const orders = filterByRestaurant(await readOrders(), restaurantId);
    const menuItems = filterByRestaurant(await readItems(), restaurantId);
    const result = computeFoodCostReport(orders, menuItems, restaurantId, {
      days,
      startDate,
      endDate,
    });

    sendJson(res, 200, result);
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/recommendations') {
    const auth = parseAuthHeader(req);
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });

    if (!restaurantId) {
      const slugParam =
        url.searchParams.get('restaurant_slug') || url.searchParams.get('slug');
      if (slugParam) {
        sendJson(res, 404, { error: 'Restaurant not found' });
      } else {
        authError(res, 401, 'Restaurant context required');
      }
      return;
    }

    const cartRaw =
      url.searchParams.get('cart') ||
      url.searchParams.get('cartItemIds') ||
      url.searchParams.get('cart_item_ids') ||
      '';
    const cartItemIds = String(cartRaw)
      .split(',')
      .map((id) => Number(id.trim()))
      .filter((id) => Number.isFinite(id) && id > 0);
    const limit = Number(url.searchParams.get('limit') || 8);
    const subtotal = Number(url.searchParams.get('subtotal') || 0);
    const settings = await readSettings(restaurantId);
    const orders = filterByRestaurant(await readOrders(), restaurantId);
    const menuItems = filterByRestaurant(await readItems(), restaurantId);
    const result = computeCartRecommendations(
      orders,
      menuItems,
      restaurantId,
      cartItemIds,
      {
        limit,
        subtotal,
        freeDeliveryThreshold: settings.freeDeliveryThreshold || 0,
      },
    );

    sendJson(res, 200, {
      restaurantId,
      cartItemIds,
      subtotal,
      source: result.source,
      recommendations: result.recommendations,
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/items') {
    const auth = parseAuthHeader(req);
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });

    if (!restaurantId) {
      const slugParam =
        url.searchParams.get('restaurant_slug') || url.searchParams.get('slug');
      if (slugParam) {
        sendJson(res, 404, { error: 'Restaurant not found' });
      } else {
        authError(res, 401, 'Restaurant context required');
      }
      return;
    }

    if (auth && !canAccessRestaurant(auth, restaurantId)) {
      authError(res, 403, 'Access denied for this restaurant');
      return;
    }

    const scopedItems = sortItemsByDisplayOrder(
      filterByRestaurant(await readItems(), restaurantId),
    );
    const items = mapItemsForPublicApi(
      normalizeMenuItemsForApi(scopedItems),
      requestOrigin(req),
    );
    rebuildCategoryIds(items);
    sendJson(res, 200, items);
    return;
  }

  const itemImageMatch = url.pathname.match(/^\/api\/items\/image\/([^/]+)$/);
  if (req.method === 'GET' && itemImageMatch) {
    serveMenuImage(res, decodeURIComponent(itemImageMatch[1]));
    return;
  }

  const menuImageApiMatch = url.pathname.match(/^\/api\/menu-image\/([^/]+)$/);
  if (req.method === 'GET' && menuImageApiMatch) {
    serveMenuImage(res, decodeURIComponent(menuImageApiMatch[1]));
    return;
  }

  const menuImageShortMatch = url.pathname.match(/^\/menu-image\/([^/]+)$/);
  if (req.method === 'GET' && menuImageShortMatch) {
    serveMenuImage(res, decodeURIComponent(menuImageShortMatch[1]));
    return;
  }

  const uploadMatch = url.pathname.match(/^\/api\/uploads\/menu\/([^/]+)$/);
  if (req.method === 'GET' && uploadMatch) {
    serveMenuImage(res, decodeURIComponent(uploadMatch[1]));
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/image-proxy') {
    const imageUrl = url.searchParams.get('url');
    if (!imageUrl) {
      sendJson(res, 400, { error: 'Missing url query parameter' });
      return;
    }
    await proxyImage(res, imageUrl);
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/items/sync') {
    const auth = requireSuperAdmin(req, res);
    if (!auth) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const incoming = Array.isArray(body.items) ? body.items : [];
      const downloadImages = body.downloadImages !== false;
      const restaurantId = String(
        body.restaurantId || body.restaurant_id || DEFAULT_RESTAURANT_ID,
      );

      const restaurants = await readRestaurants();
      if (!restaurants.some((entry) => entry.id === restaurantId)) {
        sendJson(res, 404, { error: 'Restaurant not found' });
        return;
      }

      const normalizedIncoming = incoming.map((raw, index) =>
        normalizeIncoming(raw, index, restaurantId),
      );
      const preparedIncoming = downloadImages
        ? await persistMenuItemsImages(normalizedIncoming)
        : normalizedIncoming;
      const existing = await readItems();
      const mergeResult = mergeItems(existing, preparedIncoming, restaurantId);
      rebuildCategoryIds(filterByRestaurant(mergeResult.items, restaurantId));
      await writeItems(mergeResult.items);
      sendJson(res, 200, {
        ok: true,
        restaurantId,
        total: filterByRestaurant(mergeResult.items, restaurantId).length,
        synced: incoming.length,
        added: mergeResult.added,
        updated: mergeResult.updated,
        skipped: mergeResult.skipped,
        imagesStoredLocally: preparedIncoming.filter((item) =>
          String(item.image_url || '').startsWith('/api/uploads/menu/'),
        ).length,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/talabat/import') {
    const auth = requireSuperAdmin(req, res);
    if (!auth) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const inputUrl = String(body.url || body.menuUrl || '').trim();
      const downloadImages = body.downloadImages !== false;
      const restaurantId = String(
        body.restaurantId || body.restaurant_id || DEFAULT_RESTAURANT_ID,
      );

      if (!inputUrl) {
        sendJson(res, 400, { error: 'Missing Talabat menu URL' });
        return;
      }

      const restaurants = await readRestaurants();
      if (!restaurants.some((entry) => entry.id === restaurantId)) {
        sendJson(res, 404, { error: 'Restaurant not found' });
        return;
      }

      const scrapeResult = await scrapeTalabatMenu(inputUrl);
      const incoming = Array.isArray(scrapeResult.items) ? scrapeResult.items : [];

      if (!incoming.length) {
        sendJson(res, 400, { error: 'No menu items found at this Talabat URL' });
        return;
      }

      const normalizedIncoming = incoming.map((raw, index) =>
        normalizeIncoming(raw, index, restaurantId),
      );
      const preparedIncoming = downloadImages
        ? await persistMenuItemsImages(normalizedIncoming)
        : normalizedIncoming;
      const existing = await readItems();
      const mergeResult = mergeItems(existing, preparedIncoming, restaurantId);
      rebuildCategoryIds(filterByRestaurant(mergeResult.items, restaurantId));
      await writeItems(mergeResult.items);

      sendJson(res, 200, {
        ok: true,
        menuUrl: scrapeResult.menuUrl,
        restaurantId,
        total: filterByRestaurant(mergeResult.items, restaurantId).length,
        synced: incoming.length,
        added: mergeResult.added,
        updated: mergeResult.updated,
        skipped: mergeResult.skipped,
        imagesStoredLocally: preparedIncoming.filter((item) =>
          String(item.image_url || '').startsWith('/api/uploads/menu/'),
        ).length,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Talabat import failed' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/items') {
    const auth = requireAuth(req, res);
    if (!auth) return;
    if (rejectCashier(auth, res, 'Cashiers cannot manage menu items')) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurantId = resolveRestaurantId(
        auth,
        body.restaurantId ||
          body.restaurant_id ||
          req.headers['x-restaurant-id'],
      );

      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      const items = await readItems();
      const scoped = filterByRestaurant(items, restaurantId);
      const [category, bilingual] = await Promise.all([
        ensureAutoTranslatedCategory(body),
        ensureAutoTranslatedBilingual(body),
      ]);
      const item = ensureRestaurantId(
        {
          id: nextNumericItemId(scoped),
          category_id: categoryIdFor(category.category_name),
          ...category,
          ...bilingual,
          price: Number(body.price) || 0,
          image_url: String(body.image_url || body.imageUrl || ''),
          is_available:
            body.is_available === 0 ||
            body.is_available === false ||
            body.isAvailable === false
              ? 0
              : 1,
          source: body.source || 'Manual',
          display_order:
            Number(body.display_order ?? body.displayOrder) ||
            maxDisplayOrder(scoped) + 1,
          options: normalizeMenuOptions(body.options),
          linkedItemIds: normalizeLinkedItemIds(
            body.linkedItemIds ?? body.linked_item_ids ?? [],
          ),
          linked_item_ids: normalizeLinkedItemIds(
            body.linkedItemIds ?? body.linked_item_ids ?? [],
          ),
        },
        restaurantId,
      );
      applyCostPriceFields(item, body);

      if (!item.name && !item.name_ar && !item.name_en) {
        sendJson(res, 400, { error: 'Item name is required' });
        return;
      }

      items.push(item);
      await writeItems(items);
      sendJson(res, 201, item);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'PUT' && url.pathname === '/api/items/reorder') {
    const auth = requireAuth(req, res);
    if (!auth) return;
    if (rejectCashier(auth, res, 'Cashiers cannot manage menu items')) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const orderedIds = body.orderedIds || body.ordered_ids;
      if (!Array.isArray(orderedIds) || orderedIds.length === 0) {
        sendJson(res, 400, { error: 'orderedIds array is required' });
        return;
      }

      const restaurantId = resolveRestaurantId(
        auth,
        body.restaurantId ||
          body.restaurant_id ||
          req.headers['x-restaurant-id'],
      );

      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      const items = await readItems();
      const idSet = new Set(orderedIds.map((id) => String(id)));

      orderedIds.forEach((id, index) => {
        const item = findItemById(items, id);
        if (!item) return;
        const itemRestaurantId =
          item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID;
        if (String(itemRestaurantId) !== String(restaurantId)) return;
        item.display_order = index;
      });

      // Keep any restaurant items missing from payload at the end.
      const scoped = sortItemsByDisplayOrder(filterByRestaurant(items, restaurantId));
      let nextOrder = orderedIds.length;
      for (const item of scoped) {
        if (idSet.has(String(item.id))) continue;
        item.display_order = nextOrder;
        nextOrder += 1;
      }

      await writeItems(items);
      sendJson(res, 200, {
        ok: true,
        restaurantId,
        count: orderedIds.length,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid reorder payload' });
    }
    return;
  }

  const itemMatch = url.pathname.match(/^\/api\/items\/([^/]+)$/);
  if (itemMatch && (req.method === 'PUT' || req.method === 'DELETE')) {
    const auth = requireAuth(req, res);
    if (!auth) return;
    if (rejectCashier(auth, res, 'Cashiers cannot manage menu items')) return;

    try {
      const itemId = decodeURIComponent(itemMatch[1]);
      const items = await readItems();
      const item = findItemById(items, itemId);

      if (!item) {
        sendJson(res, 404, { error: 'Item not found' });
        return;
      }

      const restaurantId = item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      if (req.method === 'DELETE') {
        await writeItems(items.filter((entry) => String(entry.id) !== String(itemId)));
        sendJson(res, 200, { ok: true, id: itemId });
        return;
      }

      const body = JSON.parse((await readBody(req)) || '{}');
      const [category, bilingual] = await Promise.all([
        ensureAutoTranslatedCategory(body, item),
        ensureAutoTranslatedBilingual({ ...item, ...body }),
      ]);

      Object.assign(item, {
        ...bilingual,
        ...category,
        price: Number(body.price ?? item.price) || 0,
        category_id: Number(
          body.category_id ?? body.categoryId ?? categoryIdFor(category.category_name),
        ),
        image_url: String(body.image_url ?? body.imageUrl ?? item.image_url ?? ''),
        is_available:
          body.is_available === 0 ||
          body.is_available === false ||
          body.isAvailable === false
            ? 0
            : body.is_available != null || body.isAvailable != null
              ? 1
              : item.is_available,
        source: body.source || item.source || 'Manual',
        display_order:
          body.display_order != null || body.displayOrder != null
            ? Number(body.display_order ?? body.displayOrder) || 0
            : itemDisplayOrder(item, 0),
      });

      if (body.options != null) {
        item.options = normalizeMenuOptions(body.options);
      }

      if (body.linkedItemIds != null || body.linked_item_ids != null) {
        const linked = normalizeLinkedItemIds(
          body.linkedItemIds ?? body.linked_item_ids,
        );
        item.linkedItemIds = linked;
        item.linked_item_ids = linked;
      }

      applyCostPriceFields(item, body);

      await writeItems(items);
      sendJson(res, 200, item);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  const itemAvailabilityMatch = url.pathname.match(/^\/api\/items\/([^/]+)\/availability$/);
  if (req.method === 'PATCH' && itemAvailabilityMatch) {
    const auth = requireAuth(req, res);
    if (!auth) return;
    if (rejectCashier(auth, res, 'Cashiers cannot manage menu items')) return;

    try {
      const itemId = decodeURIComponent(itemAvailabilityMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const items = await readItems();
      const item = findItemById(items, itemId);

      if (!item) {
        sendJson(res, 404, { error: 'Item not found' });
        return;
      }

      const restaurantId = item.restaurant_id || item.restaurantId || DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      const nextAvailable =
        body.is_available ?? body.isAvailable ?? body.available ?? item.is_available;
      item.is_available =
        nextAvailable === 0 || nextAvailable === false || nextAvailable === '0' ? 0 : 1;

      await writeItems(items);
      sendJson(res, 200, item);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/customers/lookup') {
    try {
      const phone = url.searchParams.get('phone');
      const normalizedPhone = normalizePhoneDigits(phone);
      if (!normalizedPhone || normalizedPhone.length < 8) {
        sendJson(res, 400, { error: 'Invalid phone number' });
        return;
      }

      const restaurants = await readRestaurants();
      let restaurantId = resolveRestaurantFromQuery(url, restaurants);
      if (!restaurantId) {
        const slug = String(
          url.searchParams.get('slug') || url.searchParams.get('restaurant_slug') || '',
        )
          .trim()
          .toLowerCase();
        if (slug) {
          const match = restaurants.find(
            (entry) => String(entry.slug || '').toLowerCase() === slug,
          );
          restaurantId = match ? match.id : null;
        }
      }

      if (!restaurantId) {
        sendJson(res, 400, { error: 'Restaurant not found' });
        return;
      }

      const customers = await ensureCustomersMigrated();
      const customer = findCustomerByPhone(customers, restaurantId, normalizedPhone);
      if (customer) {
        sendJson(res, 200, {
          found: true,
          source: 'customers',
          profile: customerProfileFromRecord(customer),
        });
        return;
      }

      const orders = sortOrdersDesc(
        filterByRestaurant(await readOrders(), restaurantId),
      );
      const match = orders.find((order) => phonesMatch(order.phone, normalizedPhone));
      if (!match) {
        sendJson(res, 404, { found: false });
        return;
      }

      sendJson(res, 200, {
        found: true,
        source: 'orders',
        profile: customerProfileFromOrder(match),
      });
    } catch (error) {
      sendJson(res, 500, { error: error.message || 'Lookup failed' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/customers') {
    const auth = requireAuth(req, res);
    if (!auth) return;

    if (isSuperAdmin(auth)) {
      authError(res, 403, 'Customers are managed by restaurant admins only');
      return;
    }

    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return;
    }

    const customers = await ensureCustomersMigrated();
    const orders = await readOrders();
    const list = enrichCustomersForRestaurant(customers, orders, restaurantId);
    sendJson(res, 200, list);
    return;
  }

  const customerDetailMatch = url.pathname.match(/^\/api\/customers\/([^/]+)$/);
  if (req.method === 'GET' && customerDetailMatch) {
    const auth = requireAuth(req, res);
    if (!auth) return;

    if (isSuperAdmin(auth)) {
      authError(res, 403, 'Customers are managed by restaurant admins only');
      return;
    }

    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return;
    }

    const customerId = decodeURIComponent(customerDetailMatch[1]);
    const customers = await ensureCustomersMigrated();
    const customer = customers.find(
      (entry) =>
        String(entry.id) === customerId &&
        String(entry.restaurant_id || entry.restaurantId || '') === String(restaurantId),
    );

    if (!customer) {
      sendJson(res, 404, { error: 'Customer not found' });
      return;
    }

    const orders = sortOrdersDesc(
      filterByRestaurant(await readOrders(), restaurantId),
    ).filter((order) => phonesMatch(order.phone, customer.phone));

    sendJson(res, 200, {
      customer: {
        ...customer,
        formattedAddress: formatCustomerAddress(customer),
        totalOrders: orders.length,
      },
      orders,
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/orders') {
    const auth = requireAuth(req, res);
    if (!auth) return;

    if (isSuperAdmin(auth)) {
      authError(res, 403, 'Orders are managed by restaurant admins only');
      return;
    }

    const restaurantId = await resolveScopedRestaurantId(req, url, auth);
    if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
      return;
    }

    const orders = sortOrdersDesc(filterByRestaurant(await readOrders(), restaurantId));
    sendJson(res, 200, orders);
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/promo/validate') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const phone = normalizePhoneDigits(body.phone);
      const promoCode = String(body.promoCode ?? body.promo_code ?? '').trim();
      const restaurants = await readRestaurants();
      let restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        resolveRestaurantFromQuery(url, restaurants);

      if (!restaurantId && (body.restaurantSlug || body.restaurant_slug || body.slug)) {
        const slug = String(
          body.restaurantSlug || body.restaurant_slug || body.slug,
        )
          .trim()
          .toLowerCase();
        const match = restaurants.find(
          (entry) => String(entry.slug || '').toLowerCase() === slug,
        );
        restaurantId = match ? match.id : null;
      }

      if (!restaurantId) {
        sendJson(res, 404, { error: 'Restaurant not found' });
        return;
      }
      if (!phone || phone.length < 8) {
        sendJson(res, 400, { error: 'Invalid phone number' });
        return;
      }

      const subtotal = Number(body.subtotal ?? body.sub_total ?? 0) || 0;
      const deliveryFee = Number(body.deliveryFee ?? body.delivery_fee ?? 0) || 0;
      const orderTotal = subtotal + deliveryFee;
      const customers = await ensureCustomersMigrated();
      const result = validatePersonalPromo({
        customers,
        restaurantId,
        phone,
        code: promoCode,
        orderTotal,
      });

      if (!result.valid) {
        sendJson(res, 400, {
          valid: false,
          error: result.error,
          message: result.message,
        });
        return;
      }

      sendJson(res, 200, {
        valid: true,
        promoCode: result.promoCode,
        discount: result.discount,
        message: result.message,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/wallet/validate') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const phone = normalizePhoneDigits(body.phone);
      const walletAmount = roundPromo3(
        body.walletAmount ?? body.wallet_amount ?? body.walletDiscount ?? body.wallet_discount ?? 0,
      );
      const restaurants = await readRestaurants();
      let restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        resolveRestaurantFromQuery(url, restaurants);

      if (!restaurantId && (body.restaurantSlug || body.restaurant_slug || body.slug)) {
        const slug = String(
          body.restaurantSlug || body.restaurant_slug || body.slug,
        )
          .trim()
          .toLowerCase();
        const match = restaurants.find(
          (entry) => String(entry.slug || '').toLowerCase() === slug,
        );
        restaurantId = match ? match.id : null;
      }

      if (!restaurantId) {
        sendJson(res, 404, { error: 'Restaurant not found' });
        return;
      }
      if (!phone || phone.length < 8) {
        sendJson(res, 400, { error: 'Invalid phone number' });
        return;
      }
      if (walletAmount <= 0) {
        sendJson(res, 400, {
          valid: false,
          error: 'invalid_amount',
          message: 'Wallet amount must be greater than zero',
        });
        return;
      }

      const subtotal = Number(body.subtotal ?? body.sub_total ?? 0) || 0;
      const deliveryFee = Number(body.deliveryFee ?? body.delivery_fee ?? 0) || 0;
      const promoDiscount = roundPromo3(body.promoDiscount ?? body.promo_discount ?? 0);
      const orderTotal = Math.max(0, subtotal + deliveryFee - promoDiscount);
      const customers = await ensureCustomersMigrated();
      const result = validateWalletAmount({
        customers,
        restaurantId,
        phone,
        amount: walletAmount,
        orderTotal,
      });

      if (!result.valid) {
        sendJson(res, 400, {
          valid: false,
          error: result.error,
          message: result.message,
        });
        return;
      }

      sendJson(res, 200, {
        valid: true,
        walletAmount: result.walletAmount,
        discount: result.discount,
        walletBalance: result.walletBalance,
        remainingBalance: result.remainingBalance,
        coversFullOrder: result.coversFullOrder,
        message: result.message,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/orders') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurants = await readRestaurants();
      let restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        resolveRestaurantFromQuery(url, restaurants);

      if (!restaurantId && (body.restaurantSlug || body.restaurant_slug)) {
        const slug = String(body.restaurantSlug || body.restaurant_slug).trim();
        const match = restaurants.find(
          (entry) => String(entry.slug || '').toLowerCase() === slug.toLowerCase(),
        );
        restaurantId = match ? match.id : null;
      }

      if (!restaurantId) {
        sendJson(res, 404, { error: 'Restaurant not found' });
        return;
      }

      const tenantMenuItems = filterByRestaurant(await readItems(), restaurantId);
      const itemCheck = assertOrderItemsBelongToRestaurant(
        body,
        restaurantId,
        tenantMenuItems,
      );
      if (!itemCheck.ok) {
        sendJson(res, 400, {
          error: itemCheck.error,
          code: itemCheck.code,
        });
        return;
      }

      const id = `ord_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      let customers = await readCustomers();
      const promoCodeInput = String(body.promoCode ?? body.promo_code ?? '').trim();
      const walletAmountInput = roundPromo3(
        body.walletAmount ?? body.wallet_amount ?? body.walletDiscount ?? body.wallet_discount ?? 0,
      );
      const phoneDigits = normalizePhoneDigits(body.phone);
      const subtotalPreview =
        Number(body.subtotal ?? body.sub_total ?? 0) ||
        (Array.isArray(body.items)
          ? body.items.reduce(
              (sum, item) => sum + (Number(item.lineTotal ?? item.line_total) || 0),
              0,
            )
          : 0);
      const deliveryFeePreview = Number(body.deliveryFee ?? body.delivery_fee ?? 0) || 0;
      let orderTotalAfterPromo = subtotalPreview + deliveryFeePreview;

      if (promoCodeInput && phoneDigits.length >= 8) {
        const promoResult = validatePersonalPromo({
          customers,
          restaurantId,
          phone: phoneDigits,
          code: promoCodeInput,
          orderTotal: orderTotalAfterPromo,
        });
        if (!promoResult.valid) {
          sendJson(res, 400, {
            error: promoResult.message || 'Invalid promo code',
            code: 'INVALID_PROMO_CODE',
          });
          return;
        }
        body.promoCode = promoResult.promoCode;
        body.promoDiscount = promoResult.discount;
        body.promo_code = promoResult.promoCode;
        body.promo_discount = promoResult.discount;
        orderTotalAfterPromo = Math.max(
          0,
          orderTotalAfterPromo - promoResult.discount,
        );
      }

      if (walletAmountInput > 0 && phoneDigits.length >= 8) {
        const walletResult = validateWalletAmount({
          customers,
          restaurantId,
          phone: phoneDigits,
          amount: walletAmountInput,
          orderTotal: orderTotalAfterPromo,
        });
        if (!walletResult.valid) {
          sendJson(res, 400, {
            error: walletResult.message || 'Invalid wallet amount',
            code: 'INVALID_WALLET_AMOUNT',
          });
          return;
        }
        body.walletAmount = walletResult.walletAmount;
        body.walletDiscount = walletResult.discount;
        body.wallet_amount = walletResult.walletAmount;
        body.wallet_discount = walletResult.discount;
        orderTotalAfterPromo = Math.max(
          0,
          orderTotalAfterPromo - walletResult.discount,
        );
        if (walletResult.coversFullOrder) {
          body.paymentMethod = body.paymentMethod || body.payment_method || 'محفظة';
          body.payment_method = body.paymentMethod;
        }
      }

      body.totalPrice = orderTotalAfterPromo;
      body.total_price = orderTotalAfterPromo;

      const authHeader = parseAuthHeader(req);
      if (authHeader) {
        if (!body.cashierId && !body.cashier_id && authHeader.staffId) {
          body.cashierId = authHeader.staffId;
          body.cashier_id = authHeader.staffId;
        }
        if (!body.cashierName && !body.cashier_name) {
          const cashierLabel =
            authHeader.staffName || authHeader.cashierName || authHeader.name || null;
          if (cashierLabel) {
            body.cashierName = cashierLabel;
            body.cashier_name = cashierLabel;
          }
        }
      }

      let order = normalizeOrder(body, id, restaurantId);

      try {
        const kitchenFields = await assignTargetKitchen({
          body,
          restaurantId,
          auth: authHeader,
          deliveryZoneId: order.deliveryZoneId || order.delivery_zone_id,
        });
        order = { ...order, ...kitchenFields };
      } catch (kitchenError) {
        sendJson(res, 422, {
          error: kitchenError.message || 'Kitchen assignment failed',
          code: kitchenError.code || 'KITCHEN_ASSIGNMENT_FAILED',
        });
        return;
      }

      const orders = await readOrders();
      orders.unshift(order);
      await writeOrders(orders);

      const nextCustomers = upsertCustomerFromSource(customers, order, restaurantId);
      let rewardCustomers = nextCustomers;
      if (promoCodeInput) {
        rewardCustomers = redeemPersonalPromo(rewardCustomers, {
          restaurantId,
          phone: order.phone,
          code: promoCodeInput,
        });
      }
      if (walletAmountInput > 0 && roundPromo3(order.walletDiscount ?? order.wallet_discount ?? 0) > 0) {
        rewardCustomers = redeemWalletAmount(rewardCustomers, {
          restaurantId,
          phone: order.phone,
          amount: roundPromo3(order.walletDiscount ?? order.wallet_discount ?? 0),
          orderId: order.id,
        });
      }
      const customerBefore = findCustomerByPhone(
        rewardCustomers,
        restaurantId,
        order.phone,
      );
      const settings = await readSettings(restaurantId);
      const rewardResult = applyPostCheckoutRewards({
        customers: rewardCustomers,
        order,
        restaurantId,
        settings,
        customerBefore,
      });
      await writeCustomers(rewardResult.customers);

      if ((rewardResult.rewards?.earnedCashback ?? 0) > 0) {
        const now = new Date().toISOString();
        order.earnedCashback = rewardResult.rewards.earnedCashback;
        order.loyaltyCashbackApplied = true;
        order.loyalty_cashback_applied = true;
        order.loyaltyCashbackAppliedAt = now;
        order.loyalty_cashback_applied_at = now;
        orders[0] = order;
        await writeOrders(orders);
      }

      sendJson(res, 201, {
        order,
        smartClosing: rewardResult.smartClosing,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  const orderStatusMatch = url.pathname.match(/^\/api\/orders\/([^/]+)\/status$/);
  const orderKitchenMatch = url.pathname.match(/^\/api\/orders\/([^/]+)\/kitchen$/);
  if (req.method === 'PATCH' && orderKitchenMatch) {
    const auth = requireAuth(req, res);
    if (!auth) return;

    try {
      const orderId = decodeURIComponent(orderKitchenMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const targetKitchenId = String(
        body.targetKitchenId || body.target_kitchen_id || '',
      ).trim();

      if (!targetKitchenId) {
        sendJson(res, 400, { error: 'targetKitchenId is required', code: 'MISSING_KITCHEN' });
        return;
      }

      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return;
      }

      const order = orders[index];
      const restaurantId = String(order.restaurant_id || order.restaurantId || DEFAULT_RESTAURANT_ID);
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      const kitchens = await getActiveKitchens(restaurantId);
      const kitchen = kitchens.find((entry) => String(entry.id) === targetKitchenId);
      if (!kitchen) {
        sendJson(res, 400, { error: 'Invalid target kitchen', code: 'INVALID_TARGET_KITCHEN' });
        return;
      }

      const previousKitchenId =
        order.target_kitchen_id || order.targetKitchenId || null;
      const now = new Date().toISOString();
      const assignment = {
        source: 'dispatch_manual',
        assigned_at: now,
        assigned_by_id: auth.staffId || auth.id || null,
        assigned_by_name: auth.name || auth.cashierName || null,
        overridden: previousKitchenId != null && previousKitchenId !== targetKitchenId,
        previous_kitchen_id: previousKitchenId,
      };

      orders[index] = {
        ...order,
        targetKitchenId: kitchen.id,
        target_kitchen_id: kitchen.id,
        targetKitchenName: kitchen.name_en || kitchen.name || kitchen.name_ar,
        target_kitchen_name: kitchen.name_en || kitchen.name || kitchen.name_ar,
        kitchenAssignment: assignment,
        kitchen_assignment: assignment,
        updatedAt: now,
      };

      await writeOrders(orders);
      sendJson(res, 200, { order: orders[index] });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'PATCH' && orderStatusMatch) {
    try {
      const orderId = decodeURIComponent(orderStatusMatch[1]);
      const body = JSON.parse((await readBody(req)) || '{}');
      const nextStatus = String(body.status || '').trim();
      if (!nextStatus) {
        sendJson(res, 400, { error: 'Missing status' });
        return;
      }

      const orders = await readOrders();
      const index = orders.findIndex((order) => String(order.id) === orderId);
      if (index === -1) {
        sendJson(res, 404, { error: 'Order not found' });
        return;
      }

      const auth = requireAuth(req, res);
      if (!auth) return;

      if (isSuperAdmin(auth)) {
        authError(res, 403, 'Orders are managed by restaurant admins only');
        return;
      }

      const restaurantId =
        orders[index].restaurant_id ||
        orders[index].restaurantId ||
        DEFAULT_RESTAURANT_ID;
      if (!assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      orders[index] = { ...orders[index], status: nextStatus };
      await writeOrders(orders);

      let deliveryNotification = null;
      if (String(nextStatus).toLowerCase() === 'delivered') {
        const order = orders[index];
        let customers = await ensureCustomersMigrated();
        const settings = await readSettings(restaurantId);
        const cashbackResult = applyLoyaltyCashbackToOrder(
          order,
          settings,
          customers,
          restaurantId,
        );
        if (cashbackResult.applied) {
          orders[index] = cashbackResult.order;
          customers = cashbackResult.customers;
          await writeOrders(orders);
          await writeCustomers(customers);
        } else if (
          cashbackResult.order?.loyaltyCashbackApplied === true ||
          cashbackResult.order?.loyalty_cashback_applied === true
        ) {
          orders[index] = cashbackResult.order;
          await writeOrders(orders);
        }

        const customer = findCustomerByPhone(customers, restaurantId, order.phone);
        const restaurants = await readRestaurants();
        const restaurantMatch = restaurants.find(
          (entry) => String(entry.id) === String(restaurantId),
        );
        deliveryNotification = buildDeliveryNotificationPayload({
          order: orders[index],
          customer,
          restaurantName: restaurantMatch?.name || 'المطعم',
          restaurantWhatsapp: settings.whatsappNumber,
          settings,
          previewEarnedCashback,
          restaurantId,
        });
      }

      sendJson(res, 200, {
        order: orders[index],
        deliveryNotification,
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/settings') {
    const auth = parseAuthHeader(req);
    const restaurantId = await resolveScopedRestaurantId(req, url, auth, {
      allowPublicDefault: true,
    });

    if (!restaurantId) {
      const slugParam =
        url.searchParams.get('restaurant_slug') || url.searchParams.get('slug');
      if (slugParam) {
        sendJson(res, 404, { error: 'Restaurant not found' });
      } else {
        authError(res, 401, 'Restaurant context required');
      }
      return;
    }

    if (auth && !canAccessRestaurant(auth, restaurantId)) {
      authError(res, 403, 'Access denied for this restaurant');
      return;
    }

    sendJson(res, 200, await readSettings(restaurantId));
    return;
  }

  if (req.method === 'PUT' && url.pathname === '/api/settings') {
    const auth = requireAuth(req, res);
    if (!auth) return;
    if (rejectCashier(auth, res, 'Cashiers cannot update restaurant settings')) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurantId = resolveRestaurantId(
        auth,
        body.restaurantId ||
          body.restaurant_id ||
          url.searchParams.get('restaurant_id') ||
          req.headers['x-restaurant-id'],
      );

      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      const current = await readSettings(restaurantId);
      const merged = await writeSettings(restaurantId, {
        ...current,
        ...body,
        workingHours: Array.isArray(body.workingHours)
          ? body.workingHours
          : current.workingHours,
        impulseBumpItemIds: Array.isArray(body.impulseBumpItemIds)
          ? body.impulseBumpItemIds
          : current.impulseBumpItemIds,
        updatedAt: new Date().toISOString(),
      });
      sendJson(res, 200, merged);
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/smart-closing/checkout-preview') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurants = await readRestaurants();
      let restaurantId =
        body.restaurantId ||
        body.restaurant_id ||
        resolveRestaurantFromQuery(url, restaurants);

      if (!restaurantId && (body.restaurantSlug || body.restaurant_slug)) {
        const slug = String(body.restaurantSlug || body.restaurant_slug).trim();
        const match = restaurants.find(
          (entry) => String(entry.slug || '').toLowerCase() === slug.toLowerCase(),
        );
        restaurantId = match ? match.id : null;
      }

      if (!restaurantId) {
        sendJson(res, 404, { error: 'Restaurant not found' });
        return;
      }

      const settings = await readSettings(restaurantId);
      const customers = await readCustomers();
      const phone = String(body.phone || '').trim();
      const customer = phone
        ? findCustomerByPhone(customers, restaurantId, phone)
        : null;
      sendJson(res, 200, buildCheckoutPreview({ customer, settings, body }));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/loyalty/preview') {
    const auth = requireAuth(req, res);
    if (!auth) return;

    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const restaurantId = resolveRestaurantId(
        auth,
        body.restaurantId ||
          body.restaurant_id ||
          url.searchParams.get('restaurant_id') ||
          req.headers['x-restaurant-id'],
      );

      if (!restaurantId || !assertRestaurantAccess(auth, restaurantId, authError, res)) {
        return;
      }

      const orderTotal =
        Number(body.orderTotal ?? body.order_total ?? 0) || 0;
      const settings = await readSettings(restaurantId);
      const { previewEarnedCashback } = require('./lib/loyaltyCashback');
      sendJson(res, 200, previewEarnedCashback(orderTotal, settings));
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/analytics/upsell-events') {
    try {
      const body = JSON.parse((await readBody(req)) || '{}');
      const events = Array.isArray(body.events) ? body.events : [];
      sendJson(res, 200, { ok: true, received: events.length });
    } catch (error) {
      sendJson(res, 400, { error: error.message || 'Invalid payload' });
    }
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
});

ensureUploadDir();
storeReady = storeReady.then(async () => {
  const items = await readItems();
  rebuildCategoryIds(items);
  try {
    const result = await ensureBilingualMenuItemsFast();
    if (result.updated > 0) {
      console.log(`Bilingual menu normalize: updated ${result.updated}/${result.total} items`);
    }
  } catch (error) {
    console.warn('Bilingual menu normalize skipped:', error.message || error);
  }
});

module.exports = server;

if (require.main === module) {
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`Almenupro API running at http://127.0.0.1:${PORT}`);
    console.log(`GET  http://127.0.0.1:${PORT}/api/items`);
  });
}
