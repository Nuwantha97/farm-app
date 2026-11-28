const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { test } = require('node:test');

test('sellers can publish and hide only their own validated profiles', async () => {
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
    fields: Object.fromEntries(Object.entries(data).map(([key, value]) => [
      key, typeof value === 'number' ? { integerValue: String(value) } : { stringValue: value },
    ])),
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
  await request(200, '/market_places/fixture', 'owner', 'PATCH', {
    fields: {
      name: { stringValue: 'Fixture town' },
      districtId: { stringValue: 'Matale' },
      location: { geoPointValue: { latitude: 7.87, longitude: 80.65 } },
    },
  });
  const profileFields = {
    displayName: 'Fixture farm', introduction: '', placeId: 'fixture',
    districtId: 'Matale', status: 'published',
  };
  const writeProfile = (status, token, data, mask, path = profile) => request(status, ':commit', token, 'POST', {
    writes: [{
      update: {
        name: `projects/${project}/databases/(default)/documents${path}`,
        fields: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, { stringValue: value }])),
      },
      ...(mask && { updateMask: { fieldPaths: mask } }),
      updateTransforms: [{ fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }],
    }],
  });
  await writeProfile(403, buyer.idToken, profileFields);
  await writeProfile(403, seller.idToken, { ...profileFields, districtId: 'Colombo' });
  await writeProfile(403, seller.idToken, { ...profileFields, placeId: 'missing' });
  await writeProfile(403, seller.idToken, { ...profileFields, email: 'private@example.test' });
  await writeProfile(200, seller.idToken, profileFields);
  await writeProfile(200, other.idToken, { ...profileFields, displayName: 'Second farm' }, null,
    `/market_profiles/${other.localId}`);
  async function districtSellers(expectedNames) {
    const filter = (fieldPath, stringValue) => ({
      fieldFilter: { field: { fieldPath }, op: 'EQUAL', value: { stringValue } },
    });
    const response = await fetch(`${endpoint}:runQuery`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${buyer.idToken}` },
      body: JSON.stringify({ structuredQuery: {
        from: [{ collectionId: 'market_profiles' }],
        where: { compositeFilter: { op: 'AND', filters: [filter('status', 'published'), filter('districtId', 'Matale')] } },
        orderBy: [{ field: { fieldPath: 'updatedAt' }, direction: 'DESCENDING' }],
      } }),
    });
    assert.equal(response.status, 200, await response.clone().text());
    const profiles = (await response.json()).filter((row) => row.document).map((row) => row.document.fields);
    assert.deepEqual(profiles.map((fields) => fields.displayName.stringValue).sort(), expectedNames);
    assert.ok(profiles.every((fields) => fields.placeId.stringValue === 'fixture'));
  }
  await districtSellers(['Fixture farm', 'Second farm']);
  const offer = {
    produceName: 'Tomatoes', unit: 'kg', pricePerUnitCents: 30000,
    availableQuantity: 20000, minimumQuantity: 500, pickupWindow: 'Saturday 8–10 AM',
    status: 'active',
  };
  await patch(403, listing, offer, buyer.idToken);
  await patch(403, listing, { ...offer, minimumQuantity: 21000 }, seller.idToken);
  await patch(403, listing, { ...offer, pricePerUnitCents: 0 }, seller.idToken);
  await patch(200, listing, offer, seller.idToken);
  const requestPath = `/market_orders/${buyer.localId}~${randomUUID()}`;
  const purchase = {
    buyerUid: buyer.localId, sellerUid: seller.localId, listingId: 'tomatoes',
    produceName: 'Tomatoes', unit: 'kg', pricePerUnitCents: 30000, quantity: 5000,
    totalCents: 150000, status: 'requested',
  };
  const submit = (status, path, data, token) => request(status, ':commit', token, 'POST', {
    writes: [{
      update: {
        name: `projects/${project}/databases/(default)/documents${path}`,
        fields: Object.fromEntries(Object.entries(data).map(([key, value]) => [
          key, typeof value === 'number' ? { integerValue: String(value) } : { stringValue: value },
        ])),
      },
      updateTransforms: ['createdAt', 'updatedAt'].map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })),
    }],
  });
  await request(404, requestPath, buyer.idToken);
  await request(403, requestPath, other.idToken);
  await submit(403, requestPath, purchase, other.idToken);
  await submit(403, requestPath, { ...purchase, quantity: 25000, totalCents: 750000 }, buyer.idToken);
  await submit(403, requestPath, { ...purchase, totalCents: 149999 }, buyer.idToken);
  await submit(200, requestPath, purchase, buyer.idToken);
  await submit(403, requestPath, purchase, buyer.idToken);
  await request(200, requestPath, seller.idToken);
  await request(403, requestPath, other.idToken);
  const storedOffer = await fetch(`${endpoint}${listing}`, {
    headers: { Authorization: `Bearer ${buyer.idToken}` },
  });
  assert.equal((await storedOffer.json()).fields.availableQuantity.integerValue, '20000');
  await patch(200, listing, { ...offer, pricePerUnitCents: 32500 }, seller.idToken);
  await submit(403, `/market_orders/${buyer.localId}~${randomUUID()}`, purchase, buyer.idToken);
  const savedOrder = await fetch(`${endpoint}${requestPath}`, {
    headers: { Authorization: `Bearer ${buyer.idToken}` },
  });
  assert.equal((await savedOrder.json()).fields.totalCents.integerValue, '150000');
  await patch(200, listing, { ...offer, status: 'paused' }, seller.idToken);
  await submit(403, `/market_orders/${buyer.localId}~${randomUUID()}`, purchase, buyer.idToken);
  await request(403, listing, buyer.idToken);
  await request(200, listing, seller.idToken);
  await patch(200, listing, offer, seller.idToken);
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
  await writeProfile(403, buyer.idToken, { status: 'hidden' }, ['status']);
  await writeProfile(403, seller.idToken, { status: 'hidden', displayName: 'Edited while hiding' }, ['status', 'displayName']);
  await writeProfile(200, seller.idToken, { status: 'hidden' }, ['status']);
  await districtSellers(['Second farm']);
  await request(403, profile, buyer.idToken);
  await request(403, listing, buyer.idToken);
  await request(200, listing, seller.idToken);
  await patch(403, `${profile}/listings/new`, offer, seller.idToken);
  await request(200, order, buyer.idToken);
  await writeProfile(200, seller.idToken, { ...profileFields, displayName: 'Updated farm' });
  await request(200, listing, buyer.idToken);
  const secondRequest = `/market_orders/${other.localId}~${randomUUID()}`;
  await patch(200, listing, { ...offer, availableQuantity: 5000 }, seller.idToken);
  await submit(200, secondRequest, { ...purchase, buyerUid: other.localId }, other.idToken);
  const documentName = (path) => `projects/${project}/databases/(default)/documents${path}`;
  const update = (path, fields) => ({
    update: { name: documentName(path), fields },
    updateMask: { fieldPaths: Object.keys(fields) },
  });
  const orderUpdate = (path, fields) => ({
    ...update(path, fields),
    updateTransforms: [{ fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }],
  });
  const stockUpdate = (path, available, reserved) => [
    update(listing, {
      availableQuantity: { integerValue: String(available) },
      reservedQuantity: { integerValue: String(reserved) },
    }),
    update(`${listing}/operations/stock`, { orderId: { stringValue: path.split('/').at(-1) } }),
  ];
  const change = (path, status) => orderUpdate(path, { status: { stringValue: status } });
  const commit = (status, token, writes) => request(status, ':commit', token, 'POST', { writes });
  const withdrawn = `/market_orders/${buyer.localId}~${randomUUID()}`;
  const declined = `/market_orders/${buyer.localId}~${randomUUID()}`;
  await submit(200, withdrawn, purchase, buyer.idToken);
  await submit(200, declined, purchase, buyer.idToken);
  await commit(403, seller.idToken, [change(withdrawn, 'cancelled')]);
  await commit(200, buyer.idToken, [change(withdrawn, 'cancelled')]);
  await commit(403, buyer.idToken, [change(declined, 'declined')]);
  await commit(200, seller.idToken, [change(declined, 'declined')]);
  await commit(403, seller.idToken, [change(requestPath, 'accepted')]);
  await commit(403, seller.idToken, stockUpdate(requestPath, 0, 5000));
  await commit(403, buyer.idToken, [change(requestPath, 'accepted'), ...stockUpdate(requestPath, 0, 5000)]);
  const contenders = [[requestPath, buyer.idToken], [secondRequest, other.idToken]];
  const results = await Promise.all(contenders.map(([path]) => fetch(`${endpoint}:commit`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${seller.idToken}` },
    body: JSON.stringify({ writes: [change(path, 'accepted'), ...stockUpdate(path, 0, 5000)] }),
  })));
  assert.deepEqual(results.map((result) => result.status).sort(), [200, 403],
    (await Promise.all(results.map((result) => result.text()))).join('\n'));
  const winnerIndex = results.findIndex((result) => result.ok);
  const [reservedOrder, reservedBuyer] = contenders[winnerIndex];
  const [remainingOrder] = contenders[1 - winnerIndex];
  const instructions = [orderUpdate(reservedOrder, { pickupInstructions: { stringValue: 'Pickup at the main entrance' } })];
  await commit(403, reservedBuyer, instructions);
  await commit(200, seller.idToken, instructions);
  await request(200, reservedOrder, reservedBuyer);
  await request(403, `${listing}/operations/stock`, reservedBuyer);
  await request(403, `${listing}/operations/stock`, other.idToken);
  await commit(403, seller.idToken, [update(listing, { unit: { stringValue: 'piece' } })]);
  await commit(200, seller.idToken, [update(listing, { status: { stringValue: 'paused' } })]);
  await request(403, listing, reservedBuyer);
  await commit(200, reservedBuyer, [change(reservedOrder, 'cancelled'), ...stockUpdate(reservedOrder, 5000, 0)]);
  await commit(403, reservedBuyer, [change(reservedOrder, 'cancelled'), ...stockUpdate(reservedOrder, 10000, 0)]);
  await commit(200, seller.idToken, [update(listing, { status: { stringValue: 'active' } })]);
  await commit(200, seller.idToken, [change(remainingOrder, 'accepted'), ...stockUpdate(remainingOrder, 0, 5000)]);
  await commit(200, seller.idToken, [change(remainingOrder, 'completed'), ...stockUpdate(remainingOrder, 0, 0)]);
  await commit(403, seller.idToken, [change(remainingOrder, 'cancelled'), ...stockUpdate(remainingOrder, 5000, 0)]);
  const finalStock = await fetch(`${endpoint}${listing}`, { headers: { Authorization: `Bearer ${seller.idToken}` } });
  assert.equal((await finalStock.json()).fields.availableQuantity.integerValue, '0');
  await writeProfile(403, buyer.idToken, { status: 'closed' });
  await writeProfile(403, seller.idToken, { status: 'closed', displayName: 'Retained name' });
  await writeProfile(200, seller.idToken, { status: 'closed' });
  await request(403, profile, buyer.idToken);
  await request(403, listing, buyer.idToken);
  await districtSellers(['Second farm']);
  await writeProfile(403, seller.idToken, profileFields);
  await submit(403, `/market_orders/${buyer.localId}~${randomUUID()}`, purchase, buyer.idToken);
  await request(200, requestPath, buyer.idToken);
  await writeProfile(200, buyer.idToken, { status: 'closed' }, null, `/market_profiles/${buyer.localId}`);
  await writeProfile(403, buyer.idToken, profileFields, null, `/market_profiles/${buyer.localId}`);
});
