const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { test } = require('node:test');

test('market discovery and orders enforce visibility and block client writes', async () => {
  const { GCLOUD_PROJECT: project, FIREBASE_AUTH_EMULATOR_HOST: auth, FIRESTORE_EMULATOR_HOST: store } = process.env;
  assert.ok(project?.startsWith('demo-') && auth && store, 'Use Firebase emulators with a demo project.');
  const endpoint = `http://${store}/v1/projects/${project}/databases/(default)/documents`;
  async function account() {
    const response = await fetch(`http://${auth}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: `${randomUUID()}@example.test`, password: 'fixture-password', returnSecureToken: true }),
    });
    assert.equal(response.status, 200, await response.clone().text());
    return response.json();
  }
  async function request(status, path, token, method = 'GET', body) {
    const response = await fetch(`${endpoint}${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token && { Authorization: `Bearer ${token}` }) },
      body: body && JSON.stringify(body),
    });
    assert.equal(response.status, status, await response.text());
  }
  const patch = (status, path, data, token = 'owner') => request(status, path, token, 'PATCH', {
    fields: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, { stringValue: value }])),
  });
  const [seller, buyer, other] = await Promise.all([account(), account(), account()]);
  const profile = `/market_profiles/${seller.localId}`;
  const listing = `${profile}/listings/tomatoes`;
  const order = '/market_orders/fixture';
  const query = (status, parent, collectionId, fieldPath, value, token) =>
    request(status, `${parent}:runQuery`, token, 'POST', {
      structuredQuery: {
        from: [{ collectionId }],
        where: { fieldFilter: { field: { fieldPath }, op: 'EQUAL', value: { stringValue: value } } },
      },
    });
  await patch(200, '/market_places/fixture', { name: 'Dambulla' });
  await patch(200, profile, { status: 'published' });
  await patch(200, listing, { status: 'active' });
  await patch(200, order, { buyerUid: buyer.localId, sellerUid: seller.localId });
  await request(403, '/market_places/fixture');
  await request(200, '/market_places/fixture', buyer.idToken);
  await request(200, profile, buyer.idToken);
  await request(200, listing, buyer.idToken);
  await query(200, '', 'market_profiles', 'status', 'published', buyer.idToken);
  await query(200, profile, 'listings', 'status', 'active', buyer.idToken);
  await request(200, order, buyer.idToken);
  await request(200, order, seller.idToken);
  await request(403, order, other.idToken);
  await request(403, '/market_orders', buyer.idToken);
  await query(200, '', 'market_orders', 'buyerUid', buyer.localId, buyer.idToken);
  await query(403, '', 'market_orders', 'buyerUid', buyer.localId, other.idToken);
  await patch(403, profile, { status: 'hidden' }, seller.idToken);
  await patch(200, profile, { status: 'hidden' });
  await request(403, profile, buyer.idToken);
  await request(403, listing, buyer.idToken);
  await request(200, listing, seller.idToken);
  await request(200, order, buyer.idToken);
});
