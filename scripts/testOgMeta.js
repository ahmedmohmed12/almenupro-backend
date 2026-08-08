#!/usr/bin/env node
const assert = require('assert');
const {
  buildRestaurantOgData,
  buildOgMenuHtml,
  isLikelyDirectImageUrl,
  parseMenuSlugFromPath,
} = require('../lib/ogMenuMeta');

function test(name, fn) {
  try {
    fn();
    console.log(`✓ ${name}`);
  } catch (error) {
    console.error(`✗ ${name}`);
    throw error;
  }
}

test('parseMenuSlugFromPath resolves menu and root slugs', () => {
  assert.strictEqual(parseMenuSlugFromPath('/menu/molton-cookies'), 'molton-cookies');
  assert.strictEqual(parseMenuSlugFromPath('/molton-cookies'), 'molton-cookies');
  assert.strictEqual(parseMenuSlugFromPath('/admin/settings/store'), null);
});

test('Talabat logo URLs are treated as direct images', () => {
  const url =
    'https://images.deliveryhero.io/image/talabat/restaurants/Logo_(36)_637718681262652052.jpg?width=180';
  assert.strictEqual(isLikelyDirectImageUrl(url), true);
});

test('buildRestaurantOgData uses restaurant settings per slug', () => {
  const og = buildRestaurantOgData(
    {
      slug: 'suhail-alyamani',
      name: 'Suhail Al Yamani',
      logoUrl:
        'https://images.deliveryhero.io/image/talabat/restaurants/LOGO638428357329821296.jpg?width=180',
      restaurantDescription: 'عيش الأجواء اليمنية',
    },
    {
      slug: 'suhail-alyamani',
      siteOrigin: 'https://almenupro-frontend-three.vercel.app',
      backendOrigin: 'https://almenupro-backend.vercel.app',
      menuItems: [],
    },
  );

  assert.strictEqual(og.name, 'Suhail Al Yamani');
  assert.strictEqual(og.ogDescription, 'عيش الأجواء اليمنية');
  assert.ok(og.logoUrl.includes('/api/image-proxy?url='));
  assert.ok(og.imageIsSecure);
});

test('buildOgMenuHtml includes dynamic meta tags', () => {
  const html = buildOgMenuHtml({
    slug: 'molton-cookies',
    name: 'Molton Cookies',
    title: 'Molton Cookies — المنيو الإلكتروني',
    description: 'وصف مخصص',
    ogDescription: 'وصف مخصص',
    canonicalUrl: 'https://almenupro-frontend-three.vercel.app/menu/molton-cookies',
    logoUrl:
      'https://almenupro-backend.vercel.app/api/image-proxy?url=https%3A%2F%2Fexample.com%2Flogo.jpg',
    imageIsSecure: true,
    twitterDescription: 'وصف مخصص',
  });

  assert.ok(html.includes('property="og:site_name" content="Molton Cookies"'));
  assert.ok(html.includes('property="og:locale" content="ar_KW"'));
  assert.ok(html.includes('property="og:image:secure_url"'));
  assert.ok(!html.includes('Suhail Al Yamani'));
});

console.log('\nAll OG meta tests passed.');
